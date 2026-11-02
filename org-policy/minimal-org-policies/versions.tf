terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0" # Google-Managed Constraint(.managed.) parameters 및 TagBinding 지원을 위해 v6.0+ 권장
    }
  }

  # 프로덕션 운영 시 로컬 state 대신 Seed 프로젝트 내 버전 관리(Versioning)가 활성화된 GCS 버킷 사용을 권장합니다.
  # backend "gcs" {
  #   bucket = "iam-seed-prod-01-tfstate"
  #   prefix = "minimal-org-policies"
  # }
}

provider "google" {
  # tf_service_account_email이 null이면 현재 로컬 Application Default Credentials(ADC) 인증 계정을 사용하며,
  # 프로덕션/팀 협업 환경에서는 JSON 키 발급 없이 Keyless Service Account Impersonation 방식으로 동작합니다.
  impersonate_service_account = var.tf_service_account_email
  user_project_override       = var.billing_project_id != null
  billing_project             = var.billing_project_id
}
