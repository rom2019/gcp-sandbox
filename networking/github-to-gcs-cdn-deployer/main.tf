terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Workload Identity Federation (WIF) 구성
resource "google_iam_workload_identity_pool" "pool" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Pool"
  description               = "GitHub Actions 인증용 Identity Pool"
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository == \"${var.github_repo}\""
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 2. 배포용 서비스 계정 (Service Account)
resource "google_service_account" "sa" {
  account_id   = "github-deployer"
  display_name = "GitHub Deployer Service Account"
}

# GitHub Actions가 서비스 계정 역할을 수임할 수 있도록 IAM 권한 바인딩
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${var.github_repo}"
}

# 3. 웹사이트 정적 파일 호스팅용 GCS 버킷
resource "google_storage_bucket" "website" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

# GCS 버킷 개체에 대한 공개(Public) 읽기 권한 부여
resource "google_storage_bucket_iam_member" "public_rule" {
  bucket = google_storage_bucket.website.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# 서비스 계정에 GCS 버킷 쓰기 및 관리 권한 부여
resource "google_storage_bucket_iam_member" "sa_gcs_write" {
  bucket = google_storage_bucket.website.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.sa.email}"
}

# 서비스 계정에 Cloud CDN 캐시 무효화 권한 부여
resource "google_project_iam_member" "sa_lb_admin" {
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.sa.email}"
}

# 4. 글로벌 외부 HTTP 로드밸런서 및 Cloud CDN 설정
resource "google_compute_global_address" "default" {
  name = "website-lb-ip"
}

resource "google_compute_backend_bucket" "website" {
  name        = "website-backend-bucket"
  bucket_name = google_storage_bucket.website.name
  enable_cdn  = true
  cdn_policy {
    cache_mode  = "CACHE_ALL_STATIC"
    default_ttl = 3600
    client_ttl  = 3600
    max_ttl     = 86400
  }
}

resource "google_compute_url_map" "default" {
  name            = "website-url-map"
  default_service = google_compute_backend_bucket.website.id
}

resource "google_compute_target_http_proxy" "default" {
  name    = "website-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "website-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_address = google_compute_global_address.default.address
}
