########################################
# 1. BigQuery Reservation (슬롯 풀) 생성
########################################
# Enterprise/Enterprise Plus 버전으로 예약을 생성합니다.
# principal 기반 할당(preview) 기능 데모를 위해서는 Standard 버전이 아닌
# Enterprise 이상의 버전을 사용하는 것을 권장합니다.
resource "google_bigquery_reservation" "demo" {
  provider = google

  name     = var.reservation_name
  project  = var.project_id
  location = var.reservation_location

  edition           = var.reservation_edition
  slot_capacity     = var.baseline_slot_capacity
  ignore_idle_slots = false # 다른 예약의 유휴 슬롯 사용 허용

  concurrency = 0 # 가용 리소스에 따라 쿼리 동시성 자동 조정

  autoscale {
    max_slots = var.autoscale_max_slots
  }

}

########################################
# 2. 프로젝트 수준 기본 "주문형(On-demand / none)" 할당
########################################
# principal이 설정되지 않은 일반 기본 할당입니다.
# reservations/none 을 지정하여 기본적으로 주문형(on-demand) 요금제를 사용하게 합니다.
# → VIP principal(admin@, vip_etl SA)이 아닌 일반 사용자(test@ 등)는
#   이 none 할당을 통해 예약 슬롯 대신 주문형(on-demand)으로 쿼리가 실행됩니다.
resource "google_bigquery_reservation_assignment" "project_default" {
  provider = google

  assignee    = "projects/${var.demo_project_id}"
  job_type    = "QUERY"
  reservation = "projects/${var.project_id}/locations/${var.reservation_location}/reservations/none"
}

########################################
# 3. Principal 기반 할당 - 특정 사용자(Google 계정)
########################################
# 동일한 프로젝트(demo_project_id) 범위 내에서, principal이 지정된 할당은
# principal이 없는 위의 일반 할당보다 우선 적용됩니다.
# 즉, vip_user_email 사용자가 실행하는 쿼리는 project_default 할당이 아닌
# 이 할당을 통해 라우팅됩니다.
#
# principal 형식(IAM v2 주 구성원 식별자):
#   사용자(Google 계정) : principal://goog/subject/{EMAIL}
resource "google_bigquery_reservation_assignment" "vip_user" {
  provider = google

  assignee    = "projects/${var.demo_project_id}"
  job_type    = "QUERY"
  reservation = google_bigquery_reservation.demo.id
  principal   = "principal://goog/subject/${var.vip_user_email}"
}

########################################
# 4. Principal 기반 할당 - 특정 서비스 계정
########################################
# 서비스 계정(예: ETL 파이프라인, BI 백엔드 서비스 계정)이 실행하는 쿼리를
# 전용 예약으로 라우팅하는 데모입니다.
#
# principal 형식:
#   서비스 계정 : principal://iam.googleapis.com/projects/-/serviceAccounts/{SA_EMAIL}
#
# 서비스 계정 자체는 service_accounts.tf 에서 생성되며, 쿼리 실행에 필요한
# BigQuery 권한(jobUser, dataEditor/dataViewer)도 함께 부여됩니다.
# 예약(Reservation)에 대한 라우팅은 이 할당(assignment) 리소스 자체가 처리하므로
# 별도의 예약 접근 권한은 필요하지 않습니다.
resource "google_bigquery_reservation_assignment" "vip_service_account" {
  provider = google

  assignee    = "projects/${var.demo_project_id}"
  job_type    = "QUERY"
  reservation = google_bigquery_reservation.demo.id
  principal   = "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.vip_etl.email}"

  depends_on = [google_service_account.vip_etl]
}
