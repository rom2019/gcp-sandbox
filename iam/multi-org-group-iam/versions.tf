terraform {
  required_version = ">= 1.17.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # 프로덕션 운영 시 Seed 프로젝트 내 버전 관리(Versioning)가 활성화된 GCS 버킷 사용을 권장합니다.
  # backend "gcs" {
  #   bucket = "iam-seed-prod-01-tfstate"
  #   prefix = "multi-org-group-iam"
  # }
}

# 기본 프로바이더: Keyless SA Impersonation으로 그룹·폴더·IAM 리소스 프로비저닝
provider "google" {
  impersonate_service_account = var.tf_service_account_email
  billing_project             = regex("@([^.]+)\\.iam\\.gserviceaccount\\.com$", var.tf_service_account_email)[0]
  user_project_override       = true

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
  ]
}

# 호출자(로컬 ADC 또는 CI/CD Direct WIF) 원본 자격 증명 프로바이더: 1-hop 단기 Ephemeral 토큰 발급 전용
provider "google" {
  alias = "caller"
}
