variable "project_id" {
  description = "예약(Reservation) 리소스를 소유할 관리 프로젝트(Admin Project) ID"
  type        = string
}

variable "region" {
  description = "기본 리전 (예: us-central1, asia-northeast3)"
  type        = string
  default     = "us-central1"
}

variable "reservation_location" {
  description = "BigQuery 예약(Reservation)의 위치. bq location 값과 동일해야 합니다. (예: US, asia-northeast3)"
  type        = string
  default     = "US"
}

variable "reservation_name" {
  description = "데모용 BigQuery 예약 이름"
  type        = string
  default     = "demo-principal-assignment-reservation"
}

variable "reservation_edition" {
  description = "예약 버전(Edition). principal 기반 할당은 Standard 버전에서는 지원되지 않을 수 있으므로 ENTERPRISE 이상을 권장합니다."
  type        = string
  default     = "ENTERPRISE"
}

variable "baseline_slot_capacity" {
  description = "예약에 배정할 기준(baseline) 슬롯 수"
  type        = number
  default     = 100
}

variable "autoscale_max_slots" {
  description = "오토스케일로 추가될 수 있는 최대 슬롯 수 (baseline 슬롯 수에 추가)"
  type        = number
  default     = 100
}

variable "demo_project_id" {
  description = "예약을 할당(assign)할 데모용 워크로드 프로젝트 ID (프로젝트 수준 일반 할당 대상)"
  type        = string
}

variable "vip_user_email" {
  description = "principal 기반 할당 데모 대상이 되는 특정 사용자(Google 계정)의 이메일 주소 (예: vip.analyst@example.com)"
  type        = string
}

variable "vip_service_account_id" {
  description = "principal 기반 할당 데모용으로 새로 생성할 서비스 계정의 account_id (이메일 앞부분). 예: 'bq-reservation-demo-etl' → bq-reservation-demo-etl@{demo_project_id}.iam.gserviceaccount.com 로 생성됨"
  type        = string
  default     = "bq-reservation-demo-etl"
}
