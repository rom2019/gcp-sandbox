output "load_balancer_ip" {
  description = "로드밸런서의 External IP 주소 (도메인 DNS 레코드 생성 시 사용)"
  value       = google_compute_global_address.default.address
}

output "gcs_bucket_url" {
  description = "GCS 버킷 웹사이트 URL"
  value       = "http://${google_storage_bucket.website.name}.storage.googleapis.com"
}

output "workload_identity_provider_name" {
  description = "GitHub Actions에서 사용할 Workload Identity Provider 이름"
  value       = google_iam_workload_identity_pool_provider.provider.name
}

output "service_account_email" {
  description = "GitHub Actions에서 인증할 서비스 계정 이메일"
  value       = google_service_account.sa.email
}

