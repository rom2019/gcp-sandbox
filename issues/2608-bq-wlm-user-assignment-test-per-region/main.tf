########################################
# 1. 리전별 BigQuery Reservation 생성
########################################
# var.regions 에 정의된 모든 리전에 각각 Enterprise 에디션의 예약을 생성합니다.
# slot_capacity = 0 및 autoscale max_slots = 100 으로 설정하여
# 유휴(Idle) 상태에서는 슬롯 비용이 발생하지 않도록 최적화합니다.
resource "google_bigquery_reservation" "region_res" {
  for_each = toset(var.regions)

  provider = google
  project  = var.project_id
  location = each.key
  name     = "${var.reservation_prefix}-${lower(each.key)}"

  edition           = var.reservation_edition
  slot_capacity     = var.baseline_slot_capacity
  ignore_idle_slots = false
  concurrency       = 0

  autoscale {
    max_slots = var.autoscale_max_slots
  }
}

########################################
# 2. 리전 x 사용자 매핑 Local 구조 생성
########################################
# (리전 수) x (리전당 할당 계정 수) 2차원 조합을 평탄화(flatten/merge)하여
# 각 할당 리소스에 대한 고유 Key 와 설정값을 구성합니다.
locals {
  region_assignments = merge([
    for region in var.regions : {
      for idx, sa in google_service_account.test_users :
      "${region}_user_${format("%02d", idx + 1)}" => {
        region      = region
        user_idx    = idx + 1
        sa_email    = sa.email
        reservation = google_bigquery_reservation.region_res[region].id
      }
    }
  ]...)
}

########################################
# 3. 리전별 Principal(User/SA) 할당 일괄 생성
########################################
# 모든 리전의 예약에 대해 각각 10개 이상의 Principal 할당을 생성합니다.
# principal 형식: principal://iam.googleapis.com/projects/-/serviceAccounts/{SA_EMAIL}
resource "google_bigquery_reservation_assignment" "region_assignment" {
  for_each = local.region_assignments

  provider    = google
  assignee    = "projects/${var.project_id}"
  job_type    = "QUERY"
  reservation = each.value.reservation
  principal   = "principal://iam.googleapis.com/projects/-/serviceAccounts/${each.value.sa_email}"

  depends_on = [
    google_bigquery_reservation.region_res,
    google_service_account.test_users
  ]
}
