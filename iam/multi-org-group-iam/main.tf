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

  # 그룹별 일반 멤버 및 매니저 목록을 (group_key, email) 단위로 평탄화
  group_memberships = merge([
    for group_key, group_cfg in var.groups : {
      for email in distinct(concat(group_cfg.members, group_cfg.managers)) :
      "${group_key}:${lower(email)}" => {
        group_key    = group_key
        member_email = lower(email)
        roles        = contains(group_cfg.managers, email) ? ["MEMBER", "MANAGER"] : ["MEMBER"]
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

# 2. Groups Settings API를 호출하여 외부 도메인 멤버(allowExternalMembers) 허용 활성화
# (hashicorp/google 프로바이더에 네이티브 속성이 없어 SA Impersonation 기반 REST API로 PATCH)
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
      TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="${var.tf_service_account_email}" \
        --scopes="https://www.googleapis.com/auth/apps.groups.settings")

      GROUP_EMAIL="${each.value.group_key[0].id}"
      RESP_FILE=$(mktemp)
      trap 'rm -f "$${RESP_FILE}"' EXIT

      for i in 1 2 3 4 5; do
        HTTP_CODE=$(curl -s -o "$${RESP_FILE}" -w "%%{http_code}" \
          -X PATCH \
          -H "Authorization: Bearer $${TOKEN}" \
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

  # 보안 가드레일: allowExternalMembers 활성화 시 @gmail.com 등 비인가 외부 도메인 유입을 코드 레벨에서 원천 차단
  lifecycle {
    precondition {
      condition     = endswith(each.value.member_email, "@${lower(var.main_login_domain)}")
      error_message = "보안 정책 위반: 허용된 메인 로그인 도메인(@${var.main_login_domain}) 계정만 그룹에 추가할 수 있습니다. (입력값: ${each.value.member_email})"
    }
  }
}

# 4. 그룹 단위 Organization 루트 레벨 Additive IAM 바인딩
# (예: gcp-users 그룹에 organizationViewer + browser 부여 → 콘솔 스위처에 2개 조직 동시 노출)
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
