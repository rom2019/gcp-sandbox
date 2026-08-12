output "total_regions_count" {
  description = "테스트 대상 리전 수"
  value       = length(var.regions)
}

output "assignments_per_region" {
  description = "리전당 생성된 Principal 할당 수"
  value       = var.assignment_count
}

output "total_assignments_count" {
  description = "전체 생성된 Principal 할당 총합"
  value       = length(local.region_assignments)
}

output "tested_regions" {
  description = "테스트된 BigQuery 리전 목록"
  value       = var.regions
}

output "service_account_emails" {
  description = "생성된 테스트용 서비스 계정 이메일 목록"
  value       = google_service_account.test_users[*].email
}

output "reservation_ids_by_region" {
  description = "리전별 생성된 예약 ID 맵"
  value       = { for r, res in google_bigquery_reservation.region_res : r => res.id }
}

output "demo_dataset_ids_by_region" {
  description = "리전별 생성된 데모 데이터셋 ID 맵"
  value       = { for r, ds in google_bigquery_dataset.demo : r => ds.dataset_id }
}

