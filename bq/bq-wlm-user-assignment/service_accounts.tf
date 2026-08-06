########################################
# Principal 기반 할당 데모용 서비스 계정
########################################
# ETL 파이프라인 등 특정 서비스 계정 단위로 예약을 라우팅하는 시나리오를
# 시연하기 위한 전용 서비스 계정입니다.
resource "google_service_account" "vip_etl" {
  project      = var.demo_project_id
  account_id   = var.vip_service_account_id
  display_name = "BQ Reservation Demo - VIP ETL Service Account"
  description  = "Principal 기반 예약 할당(preview) 데모용 서비스 계정. Reservation principal 라우팅 대상."
}

########################################
# IAM 권한 부여
########################################
# ⚠️ 주의: 아래 권한은 "예약(Reservation)에 접근하기 위한 권한"이 아니라
# "BigQuery에서 쿼리를 실행하고 데이터를 다루기 위한 일반적인 BigQuery 권한"입니다.
# principal 기반 할당으로 특정 예약에 라우팅되는 것은 별도의 권한 없이
# 할당(assignment) 자체가 자동으로 처리합니다 (아래 main.tf의 vip_service_account 참고).

# 1) BigQuery Job 실행 권한 (필수)
#    이 권한이 없으면 애초에 쿼리를 Job으로 제출할 수 없습니다.
resource "google_project_iam_member" "vip_etl_job_user" {
  project = var.demo_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.vip_etl.email}"
}

# 2) 데이터 접근 권한
#    데모 목적상 프로젝트 수준에서 부여했지만, 실제 고객 환경에서는
#    최소 권한 원칙에 따라 특정 데이터셋 수준(google_bigquery_dataset_iam_member)으로
#    좁혀서 부여하는 것을 권장합니다. (하단 "권장: 데이터셋 수준 권한" 예시 참고)
#
#    ETL(쓰기)용이면 dataEditor, 조회만 필요하면 dataViewer로 교체하세요.
resource "google_project_iam_member" "vip_etl_data_editor" {
  project = var.demo_project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.vip_etl.email}"
}

########################################
# (권장) 데이터셋 수준 권한 - 최소 권한 원칙
########################################
# 위의 프로젝트 수준 dataEditor 대신, 실제 데모 대상 데이터셋에만 권한을
# 좁혀서 부여하고 싶다면 아래처럼 google_bigquery_dataset_iam_member를 사용하세요.
# (사용하려면 위 google_project_iam_member.vip_etl_data_editor는 제거하고
#  아래 리소스의 주석을 해제한 뒤 dataset_id를 지정하세요.)
#
# resource "google_bigquery_dataset_iam_member" "vip_etl_dataset_editor" {
#   project    = var.demo_project_id
#   dataset_id = "your_demo_dataset"
#   role       = "roles/bigquery.dataEditor"
#   member     = "serviceAccount:${google_service_account.vip_etl.email}"
# }
