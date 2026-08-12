variable "project_id" {
  description = "GCP Project ID for BigQuery Reservation and Assignments"
  type        = string
  default     = "bg-wlm-test"
}

variable "assignment_count" {
  description = "리전당 생성할 Principal(User/SA) 할당 개수 (10개 이상 테스트용)"
  type        = number
  default     = 10
}

variable "service_account_prefix" {
  description = "할당 테스트용 서비스 계정 접두사"
  type        = string
  default     = "bq-wlm-test-user"
}

variable "reservation_prefix" {
  description = "리전별 BigQuery 예약 이름 접두사"
  type        = string
  default     = "test-res"
}

variable "reservation_edition" {
  description = "BigQuery 예약 버전 (Principal 할당 지원을 위해 ENTERPRISE 이상 권장)"
  type        = string
  default     = "ENTERPRISE"
}

variable "baseline_slot_capacity" {
  description = "예약의 기준 슬롯 수 (0으로 설정 시 유휴 상태에서 슬롯 비용 미발생)"
  type        = number
  default     = 0
}

variable "autoscale_max_slots" {
  description = "오토스케일링 최대 슬롯 수"
  type        = number
  default     = 100
}

variable "regions" {
  description = "User Assignment를 테스트할 BigQuery 지원 리전 목록"
  type        = list(string)
  default = [
    # Multi-regions
    "US",
    "EU",

    # Asia Pacific
    "asia-northeast3",      # Seoul
    "asia-northeast1",      # Tokyo
    "asia-northeast2",      # Osaka
    "asia-southeast1",      # Singapore
    "asia-southeast2",      # Jakarta
    "asia-east1",           # Taiwan
    "asia-east2",           # Hong Kong
    "asia-south1",          # Mumbai
    "asia-south2",          # Delhi
    "australia-southeast1", # Sydney
    "australia-southeast2", # Melbourne

    # Americas
    "us-central1",             # Iowa
    "us-east1",                # South Carolina
    "us-east4",                # Northern Virginia
    "us-east5",                # Columbus
    "us-south1",               # Dallas
    "us-west1",                # Oregon
    "us-west2",                # Los Angeles
    "us-west3",                # Salt Lake City
    "us-west4",                # Las Vegas
    "northamerica-northeast1", # Montreal
    "northamerica-northeast2", # Toronto
    "southamerica-east1",      # São Paulo
    "southamerica-west1",      # Santiago

    # Europe
    "europe-west1",      # Belgium
    "europe-west2",      # London
    "europe-west3",      # Frankfurt
    "europe-west4",      # Netherlands
    "europe-west6",      # Zurich
    "europe-west8",      # Milan
    "europe-west9",      # Paris
    "europe-west10",     # Berlin
    "europe-west12",     # Turin
    "europe-north1",     # Finland
    "europe-central2",   # Warsaw
    "europe-southwest1", # Madrid

    # Middle East & Africa
    "me-central1",  # Doha
    "me-central2",  # Dammam
    "me-west1",     # Tel Aviv
    "africa-south1" # Johannesburg
  ]
}

variable "create_demo_dataset" {
  description = "각 리전별 쿼리 테스트용 BigQuery Dataset 및 테이블 생성 여부"
  type        = bool
  default     = true
}

variable "dataset_prefix" {
  description = "데모용 데이터셋 접두사"
  type        = string
  default     = "bq_wlm_demo"
}

