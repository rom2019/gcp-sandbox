output "reservation_id" {
  description = "생성된 예약의 전체 리소스 ID"
  value       = google_bigquery_reservation.demo.id
}

#output "reservation_self_link" {
#  description = "생성된 예약의 self link"
#  value       = google_bigquery_reservation.demo.self_link
#}

output "project_default_assignment_id" {
  description = "프로젝트 수준 일반 할당(principal 미설정) 리소스 ID"
  value       = google_bigquery_reservation_assignment.project_default.id
}

output "vip_user_assignment_id" {
  description = "특정 사용자(principal) 기반 할당 리소스 ID"
  value       = google_bigquery_reservation_assignment.vip_user.id
}

output "vip_service_account_assignment_id" {
  description = "특정 서비스 계정(principal) 기반 할당 리소스 ID"
  value       = google_bigquery_reservation_assignment.vip_service_account.id
}

output "vip_etl_service_account_email" {
  description = "데모용으로 생성된 서비스 계정 이메일. 데모 시연 시 이 계정으로 쿼리를 실행하세요 (예: gcloud auth activate-service-account 또는 impersonation)."
  value       = google_service_account.vip_etl.email
}

output "demo_dataset_id" {
  description = "데모용 BigQuery 데이터셋 ID"
  value       = google_bigquery_dataset.demo.dataset_id
}

output "sample_orders_table_id" {
  description = "데모용 주문 테이블 ID"
  value       = google_bigquery_table.sample_orders.table_id
}

output "daily_summary_table_id" {
  description = "데모용 일별 요약 테이블 ID"
  value       = google_bigquery_table.daily_summary.table_id
}

