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
# 2. 플랫폼/조직 관리자 그룹 (Org Root: Org Admin / Folder Admin / Project Creator)
# ==============================================================================
module "gcp_org_admins" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
  group_email       = "gcp-org-admins@${var.additional_domain}"
  display_name      = "GCP Organization Admins"
  description       = "Platform and Organization Administrators for additional-domain.com"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_org_admins_members
}

resource "google_organization_iam_member" "gcp_org_admins" {
  for_each = toset([
    "roles/resourcemanager.organizationAdmin",
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
  deletion_protection = false
}

module "gcp_app_devs" {
  source            = "./modules/external-group"
  customer_id       = data.google_organization.target.directory_customer_id
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
  group_email       = "gcp-prj-admins@${var.additional_domain}"
  display_name      = "GCP Project Admins"
  description       = "Project administrators scoped to designated workload projects"
  main_login_domain = var.main_login_domain
  sa_access_token   = ephemeral.google_service_account_access_token.groups_settings.access_token
  members           = var.gcp_prj_admins_members
}

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
