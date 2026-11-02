# 0. 도메인명으로 신규 GCP Organization ID 및 Cloud Identity Directory Customer ID 자동 조회
data "google_organization" "target" {
  domain = var.additional_domain
}

# State 파일에 절대 기록되지 않는 인메모리 단기(900초) Groups Settings API 토큰 발급
ephemeral "google_service_account_access_token" "groups_settings" {
  provider               = google.caller
  target_service_account = var.tf_service_account_email
  scopes                 = ["https://www.googleapis.com/auth/apps.groups.settings"]
  lifetime               = "900s"
}

# ==============================================================================
# 1. 전 임직원 기본 그룹 (Org Root: Browser) — 신규 그룹 추가 시 블록 Copy & Paste
# ==============================================================================
module "gcp_users" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
  additional_domain = var.additional_domain
  group_email       = "gcp-users@${var.additional_domain}"
  display_name      = "GCP All Users"
  description       = "Grants Browser role so additional-domain.com appears in GCP Organization Switcher"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_users_members
}

resource "google_organization_iam_member" "gcp_users_browser" {
  org_id = data.google_organization.target.org_id
  role   = "roles/browser"
  member = module.gcp_users.iam_member
}

# ==============================================================================
# 2. 플랫폼/조직 관리자 그룹 (Org Root: Folder Admin / Project Creator)
# ==============================================================================
module "gcp_org_admins" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
  additional_domain = var.additional_domain
  group_email       = "gcp-org-admins@${var.additional_domain}"
  display_name      = "GCP Organization Admins"
  description       = "Platform Administrators for folder hierarchy and project creation"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_org_admins_members
}

# Tier-0 분리: 조직 루트 IAM 및 루트 직하 Seed 프로젝트(tf-iam-admin SA) 변조를 막기 위해
# organizationAdmin은 제외하고 하위 폴더 관리 및 프로젝트 생성 권한만 부여합니다.
resource "google_organization_iam_member" "gcp_org_admins" {
  for_each = toset([
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
  ])

  org_id = data.google_organization.target.org_id
  role   = each.value
  member = module.gcp_org_admins.iam_member
}

# ==============================================================================
# 3. 앱 개발팀 폴더 및 폴더 최소 권한 그룹 (Folder: Folder Viewer / Viewer)
# ==============================================================================
resource "google_folder" "app_dev" {
  display_name        = "app-dev"
  parent              = data.google_organization.target.name
  deletion_protection = false # 실습 정리(destroy) 편의를 위해 false 설정 (프로덕션 운영 시 true 권장)
}

module "gcp_app_devs" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
  additional_domain = var.additional_domain
  group_email       = "gcp-app-devs@${var.additional_domain}"
  display_name      = "GCP App Developers (Dev)"
  description       = "Application developers scoped to the app-dev folder"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_app_devs_members
}

resource "google_folder_iam_member" "gcp_app_devs" {
  for_each = toset([
    "roles/resourcemanager.folderViewer",
    "roles/viewer",
  ])

  folder = google_folder.app_dev.name
  role   = each.value
  member = module.gcp_app_devs.iam_member
}

# ==============================================================================
# 4. 특정 Project 전담 관리자 그룹 (Project: Editor + Project IAM Admin)
# ==============================================================================
module "gcp_prj_admins" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
  additional_domain = var.additional_domain
  group_email       = "gcp-prj-admins@${var.additional_domain}"
  display_name      = "GCP Project Admins"
  description       = "Project administrators scoped strictly to designated workload projects"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_prj_admins_members
}

# 원시 역할(roles/owner) 직접 바인딩을 지양하고, 권한 범위(Blast Radius)를 지정된 프로젝트 내부로만 한정합니다.
# 참고: projectIamAdmin은 해당 프로젝트 내에서 Owner와 동등한 역할 위임이 가능하므로,
# 부여 가능한 역할을 제한하려면 IAM Condition(iam.googleapis.com/modifiedGrantsByRole)을 추가하세요.
resource "google_project_iam_member" "gcp_prj_admins_editor" {
  for_each = var.gcp_prj_admins_project_ids

  project = each.value
  role    = "roles/editor"
  member  = module.gcp_prj_admins.iam_member
}

resource "google_project_iam_member" "gcp_prj_admins_iam_admin" {
  for_each = var.gcp_prj_admins_project_ids

  project = each.value
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = module.gcp_prj_admins.iam_member
}
