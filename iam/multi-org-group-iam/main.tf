# 0. 도메인명으로 신규 GCP Organization ID 및 Cloud Identity Directory Customer ID 자동 조회
data "google_organization" "target" {
  domain = var.additional_domain
}

# State 파일에 절대 기록되지 않는 인메모리 단기(300초) Groups Settings API 토큰 발급
ephemeral "google_service_account_access_token" "groups_settings" {
  provider               = google.caller
  target_service_account = var.tf_service_account_email
  scopes                 = ["https://www.googleapis.com/auth/apps.groups.settings"]
  lifetime               = "300s"
}

locals {
  memberships = merge([
    for group_id, cfg in var.groups : {
      for email in toset([for m in cfg.members : lower(trimspace(m))]) :
      "${group_id}:${email}" => {
        group_id = group_id
        email    = email
      }
    }
  ]...)

  org_iam_bindings = merge([
    for group_id, cfg in var.groups : {
      for role in toset(cfg.org_roles) :
      "${group_id}:${role}" => {
        group_id = group_id
        role     = role
      }
    }
  ]...)

  folder_iam_bindings = merge(flatten([
    for group_id, cfg in var.groups : [
      for folder_name, roles in cfg.folder_roles : {
        for role in toset(roles) :
        "${group_id}:${folder_name}:${role}" => {
          group_id    = group_id
          folder_name = folder_name
          role        = role
        }
      }
    ]
  ])...)
}

# 1. 신규 조직 Cloud Identity에 그룹 생성 (Terraform SA 단독 Owner)
resource "google_cloud_identity_group" "groups" {
  for_each = var.groups

  parent               = "customers/${data.google_organization.target.directory_customer_id}"
  display_name         = coalesce(each.value.display_name, each.key)
  description          = each.value.description
  initial_group_config = "WITH_INITIAL_OWNER"

  group_key {
    id = "${each.key}@${var.additional_domain}"
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }
}

# 2. 외부 도메인(@main-domain.com) 멤버 추가 허용 활성화 (Groups Settings API 1회 PATCH)
# 참고: hashicorp/google 프로바이더에 Groups Settings 네이티브 리소스가 없어 그룹 생성 시 1회 PATCH하며,
# 프로세스 인자(ps)에 토큰이 노출되지 않도록 환경변수 + curl -K -(stdin) 방식으로 전달합니다.
resource "terraform_data" "enable_external_members" {
  for_each         = google_cloud_identity_group.groups
  triggers_replace = [each.value.id]

  provisioner "local-exec" {
    quiet = true
    environment = {
      SA_TOKEN    = ephemeral.google_service_account_access_token.groups_settings.access_token
      GROUP_EMAIL = each.value.group_key[0].id
    }
    command = <<-EOT
      printf 'header = "Authorization: Bearer %s"\n' "$SA_TOKEN" \
        | curl -sS --fail-with-body --retry 5 --retry-delay 4 --retry-all-errors -K - \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d '{"allowExternalMembers": "true"}' \
            "https://www.googleapis.com/groups/v1/groups/$GROUP_EMAIL?alt=json" >/dev/null
    EOT
  }
}

# 3. 허용된 메인 로그인 도메인(@main-domain.com) 사용자를 그룹 멤버(MEMBER)로 등록
resource "google_cloud_identity_group_membership" "members" {
  for_each   = local.memberships
  depends_on = [terraform_data.enable_external_members]

  group = google_cloud_identity_group.groups[each.value.group_id].id

  preferred_member_key {
    id = each.value.email
  }

  roles {
    name = "MEMBER"
  }
}

# 4. 그룹 단위 Organization 루트 레벨 Additive IAM 바인딩
resource "google_organization_iam_member" "org_roles" {
  for_each = local.org_iam_bindings

  org_id = data.google_organization.target.org_id
  role   = each.value.role
  member = "group:${google_cloud_identity_group.groups[each.value.group_id].group_key[0].id}"
}

# 5. 하위 Folder 생성 및 그룹 단위 Folder 레벨 최소 권한 격리 바인딩
resource "google_folder" "folders" {
  for_each = var.folders

  display_name        = each.key
  parent              = data.google_organization.target.name
  deletion_protection = false
}

resource "google_folder_iam_member" "folder_roles" {
  for_each = local.folder_iam_bindings

  folder = google_folder.folders[each.value.folder_name].name
  role   = each.value.role
  member = "group:${google_cloud_identity_group.groups[each.value.group_id].group_key[0].id}"
}
