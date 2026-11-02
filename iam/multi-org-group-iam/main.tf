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
    for group_id, members in var.groups : {
      for email in toset([for m in members : lower(trimspace(m))]) :
      "${group_id}:${email}" => {
        group_id = group_id
        email    = email
      }
    }
  ]...)
}

# 1. 신규 조직 Cloud Identity에 그룹 생성 (Terraform SA 단독 Owner)
resource "google_cloud_identity_group" "groups" {
  for_each = var.groups

  parent               = "customers/${data.google_organization.target.directory_customer_id}"
  display_name         = each.key
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

# ==============================================================================
# 4. Organization 루트 레벨 그룹 IAM 바인딩 (신규 그룹 추가 시 블록 Copy & Paste)
# ==============================================================================

# 전 임직원 기본 그룹: 상단 Organization Switcher에 신규 조직 노출 및 계층 탐색 허용
resource "google_organization_iam_member" "gcp_users_browser" {
  org_id = data.google_organization.target.org_id
  role   = "roles/browser"
  member = "group:${google_cloud_identity_group.groups["gcp-users"].group_key[0].id}"
}

# 플랫폼/조직 관리자 그룹: 폴더 계층 구조, 프로젝트 생성 및 조직 IAM 관리 권한
resource "google_organization_iam_member" "gcp_org_admins" {
  for_each = toset([
    "roles/resourcemanager.organizationAdmin",
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
  ])

  org_id = data.google_organization.target.org_id
  role   = each.value
  member = "group:${google_cloud_identity_group.groups["gcp-org-admins"].group_key[0].id}"
}

# ==============================================================================
# 5. 하위 Folder 생성 및 Folder 레벨 최소 권한 격리 바인딩 (필요한 만큼 Copy & Paste)
# ==============================================================================

resource "google_folder" "app_dev" {
  display_name        = "app-dev"
  parent              = data.google_organization.target.name
  deletion_protection = false
}

resource "google_folder_iam_member" "gcp_app_devs" {
  for_each = toset([
    "roles/resourcemanager.folderViewer",
    "roles/viewer",
  ])

  folder = google_folder.app_dev.name
  role   = each.value
  member = "group:${google_cloud_identity_group.groups["gcp-app-devs"].group_key[0].id}"
}
