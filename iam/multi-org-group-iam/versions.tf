terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
  }
}

provider "google" {
  # 단일 로그인 계정(예: cloud-admin@main-domain.com)으로 ADC 로그인 후
  # SA JSON 키 발급 없이 Service Account Impersonation 방식으로 동작합니다.
  impersonate_service_account = var.tf_service_account_email
  user_project_override       = true
  billing_project             = var.seed_project_id

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/cloud-identity.groups",
    "https://www.googleapis.com/auth/apps.groups.settings",
  ]
}
