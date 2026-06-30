# ────────────────────────────────────────────────────────────────────
# Terraform 프로바이더 및 최소 버전 정의 (providers.tf)
# ────────────────────────────────────────────────────────────────────

terraform {
  # Terraform CLI 최소 필수 버전
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Provider (최신 7.x 버전을 사용하여 GCP 전역 로드밸런서 및 Org Policy 관리)
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }

    # Time Provider (조직 정책 변경 후 GCP API 전파 지연 60초 대기를 위해 사용)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# ────────────────────────────────────────────────────────────────────
# Google Cloud Provider 기본 설정
# ────────────────────────────────────────────────────────────────────
provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}
