# 0. additional_customer_id가 생략된 경우 additional_org_id로부터 Directory Customer ID(C0xxxxxxx) 자동 조회
data "google_organization" "additional" {
  count        = var.additional_customer_id == null ? 1 : 0
  organization = var.additional_org_id
}

locals {
  effective_customer_id = (
    var.additional_customer_id != null
    ? var.additional_customer_id
    : data.google_organization.additional[0].directory_customer_id
  )

  normalized_main_login_domain = lower(trimspace(var.main_login_domain))

  # 대소문자 혼용 입력 시 중복 키 충돌 및 MANAGER 역할 누락을 방지하기 위해 먼저 소문자·공백 정규화 수행
  normalized_groups = {
    for group_key, group_cfg in var.groups :
    group_key => {
      members  = distinct([for email in group_cfg.members : lower(trimspace(email))])
      managers = toset([for email in group_cfg.managers : lower(trimspace(email))])
    }
  }

  # 그룹별 일반 멤버 및 매니저 목록을 (group_key, email) 단위로 평탄화
  group_memberships = merge([
    for group_key, norm in local.normalized_groups : {
      for email in distinct(concat(norm.members, tolist(norm.managers))) :
      "${group_key}:${email}" => {
        group_key    = group_key
        member_email = email
        roles        = contains(norm.managers, email) ? ["MEMBER", "MANAGER"] : ["MEMBER"]
      }
    }
  ]...)

  # 그룹별 Organization 루트 레벨 IAM 역할 바인딩 평탄화
  group_org_iam_bindings = merge([
    for group_key, group_cfg in var.groups : {
      for role in toset(group_cfg.org_roles) :
      "${group_key}:${role}" => {
        group_key = group_key
        role      = role
      }
    }
  ]...)

  # 그룹별 샘플 하위 Folder 레벨 IAM 역할 바인딩 평탄화
  group_folder_iam_bindings = var.create_sample_folder ? merge([
    for group_key, group_cfg in var.groups : {
      for role in toset(group_cfg.folder_roles) :
      "${group_key}:${role}" => {
        group_key = group_key
        role      = role
      }
    }
  ]...) : {}
}

# 1. 신규 조직(additional-domain.com) Cloud Identity에 그룹 생성 (Terraform SA를 초기 Owner로 자동 지정)
resource "google_cloud_identity_group" "additional_org_groups" {
  for_each = var.groups

  display_name         = each.value.display_name
  description          = each.value.description
  parent               = "customers/${local.effective_customer_id}"
  initial_group_config = "WITH_INITIAL_OWNER"

  group_key {
    id = "${each.value.email_prefix}@${var.additional_domain}"
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }
}

# 2. IAM Credentials API로 단기 SA 토큰을 발급받아 Groups Settings API(allowExternalMembers=true) PATCH
# 참고: hashicorp/google 프로바이더에 Groups Settings 네이티브 리소스가 없어 그룹 생성 시 1회 PATCH로 동작하며,
# 이후 Admin Console에서 수동으로 설정을 변경(Drift)하더라도 Terraform이 자동 감지하지는 못합니다.
resource "terraform_data" "enable_external_members" {
  for_each = google_cloud_identity_group.additional_org_groups

  triggers_replace = [
    each.value.id,
    each.value.group_key[0].id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      USER_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token)
      IAM_RESP=$(mktemp)
      RESP_FILE=$(mktemp)
      trap 'rm -f "$${IAM_RESP}" "$${RESP_FILE}"' EXIT

      # 공유 CI 러너 등에서 프로세스 인자(ps)에 토큰이 노출되지 않도록 bash 내장 printf + curl -K -(stdin) 사용
      IAM_HTTP_CODE=$(printf 'header = "Authorization: Bearer %s"\n' "$${USER_TOKEN}" | curl -s -K - -o "$${IAM_RESP}" -w "%%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"scope":["https://www.googleapis.com/auth/apps.groups.settings"],"lifetime":"300s"}' \
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${var.tf_service_account_email}:generateAccessToken")

      if [ "$${IAM_HTTP_CODE}" != "200" ]; then
        echo "Failed to generate short-lived SA token for ${var.tf_service_account_email} (HTTP $${IAM_HTTP_CODE}):" >&2
        cat "$${IAM_RESP}" >&2
        exit 1
      fi

      TOKEN=$(python3 -c 'import json, sys; print(json.load(sys.stdin)["accessToken"])' < "$${IAM_RESP}")
      GROUP_EMAIL="${each.value.group_key[0].id}"

      for i in 1 2 3 4 5; do
        HTTP_CODE=$(printf 'header = "Authorization: Bearer %s"\n' "$${TOKEN}" | curl -s -K - -o "$${RESP_FILE}" -w "%%{http_code}" \
          -X PATCH \
          -H "Content-Type: application/json" \
          -H "Accept: application/json" \
          -d '{"allowExternalMembers": "true"}' \
          "https://www.googleapis.com/groups/v1/groups/$${GROUP_EMAIL}?alt=json")
        if [ "$${HTTP_CODE}" = "200" ]; then
          echo "Enabled allowExternalMembers=true for $${GROUP_EMAIL}"
          exit 0
        fi
        echo "Attempt $${i}/5 for $${GROUP_EMAIL} returned HTTP $${HTTP_CODE}; retrying in 4s..."
        sleep 4
      done

      echo "Failed to update group settings for $${GROUP_EMAIL}:" >&2
      cat "$${RESP_FILE}" >&2
      exit 1
    EOT
  }
}

# 3. 허용된 메인 로그인 도메인(@main-domain.com) 사용자를 그룹 멤버로 등록
resource "google_cloud_identity_group_membership" "external_domain_members" {
  for_each   = local.group_memberships
  depends_on = [terraform_data.enable_external_members]

  group = google_cloud_identity_group.additional_org_groups[each.value.group_key].id

  preferred_member_key {
    id = each.value.member_email
  }

  dynamic "roles" {
    for_each = each.value.roles
    content {
      name = roles.value
    }
  }

  # 보안 가드레일: allowExternalMembers 활성화 환경에서 Terraform 배포 경로를 통한 비인가 외부 도메인(@gmail.com 등) 오입력 차단
  lifecycle {
    precondition {
      condition     = endswith(each.value.member_email, "@${local.normalized_main_login_domain}")
      error_message = "보안 정책 위반: 허용된 메인 로그인 도메인(@${var.main_login_domain}) 계정만 그룹에 추가할 수 있습니다. (입력값: ${each.value.member_email})"
    }
  }
}

# 4. 그룹 단위 Organization 루트 레벨 Additive IAM 바인딩
# (예: gcp-users 그룹에 roles/browser 부여 → resourcemanager.organizations.get 포함으로 콘솔 스위처에 2개 조직 동시 노출)
resource "google_organization_iam_member" "group_org_roles" {
  for_each   = local.group_org_iam_bindings
  depends_on = [terraform_data.enable_external_members]

  org_id = var.additional_org_id
  role   = each.value.role
  member = "group:${google_cloud_identity_group.additional_org_groups[each.value.group_key].group_key[0].id}"
}

# 5. (선택) 하위 Folder 생성 및 그룹 단위 Folder 레벨 직무 권한 격리 바인딩
resource "google_folder" "sample_app_folder" {
  count = var.create_sample_folder ? 1 : 0

  display_name        = var.sample_folder_display_name
  parent              = "organizations/${var.additional_org_id}"
  deletion_protection = false
}

resource "google_folder_iam_member" "group_folder_roles" {
  for_each   = local.group_folder_iam_bindings
  depends_on = [terraform_data.enable_external_members]

  folder = google_folder.sample_app_folder[0].name
  role   = each.value.role
  member = "group:${google_cloud_identity_group.additional_org_groups[each.value.group_key].group_key[0].id}"
}
