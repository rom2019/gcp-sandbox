########################################
# Principal 할당 테스트용 서비스 계정 (10개 이상)
########################################
# 실제 개별 구글 계정 대신 프로젝트 단위의 서비스 계정을 생성하여
# 모든 리전의 BigQuery Reservation에 Principal 기반 할당을 테스트합니다.
resource "google_service_account" "test_users" {
  count        = var.assignment_count
  project      = var.project_id
  account_id   = "${var.service_account_prefix}-${format("%02d", count.index + 1)}"
  display_name = "BQ Reservation Test User ${format("%02d", count.index + 1)}"
  description  = "BigQuery multi-region user assignment limit test user (${format("%02d", count.index + 1)})"
}

# (선택) 쿼리 실행 권한 부여 (실제 쿼리 테스트 시 필요)
resource "google_project_iam_member" "test_users_job_user" {
  count   = var.assignment_count
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.test_users[count.index].email}"
}

# 데이터셋 및 테이블 조회 권한 부여 (SELECT 테스트용)
resource "google_project_iam_member" "test_users_data_viewer" {
  count   = var.assignment_count
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.test_users[count.index].email}"
}

