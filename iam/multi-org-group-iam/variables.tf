variable "additional_org_id" {
  description = "신규 분리 GCP Organization의 숫자형 ID (예: 123456789012)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.additional_org_id))
    error_message = "additional_org_id에는 숫자형 GCP Organization ID(예: 123456789012)를 입력해야 합니다."
  }
}

variable "additional_customer_id" {
  description = "(선택) 신규 조직(additional-domain.com)의 Cloud Identity Directory Customer ID (C0xxxxxxx 형식). 생략(null) 시 additional_org_id로부터 자동 조회합니다."
  type        = string
  default     = null

  validation {
    condition     = var.additional_customer_id == null || can(regex("^C[0-9a-zA-Z]+$", var.additional_customer_id))
    error_message = "additional_customer_id에는 숫자형 ORG_ID가 아니라 'C'로 시작하는 Directory Customer ID(예: C02xxxxxx)를 입력해야 합니다. 생략(주석 처리)하면 additional_org_id를 통해 자동 조회됩니다."
  }
}

variable "additional_domain" {
  description = "신규 분리 GCP Organization의 도메인 (예: additional-domain.com)"
  type        = string
}

variable "main_login_domain" {
  description = "임직원이 단일 SSO 로그인에 사용하는 기존 메인 도메인 (예: main-domain.com). 이 도메인 계정만 그룹 멤버로 허용됩니다."
  type        = string
}

variable "seed_project_id" {
  description = "API 쿼터 차감 및 Terraform Service Account가 위치한 부트스트랩(Seed) 프로젝트 ID (예: iam-seed-prod-01)"
  type        = string
}

variable "tf_service_account_email" {
  description = "Groups Admin 및 신규 조직 관리 권한이 부여된 Keyless Terraform Service Account 이메일"
  type        = string
}

variable "create_sample_folder" {
  description = "하위 폴더 단위 최소 권한 격리 검증을 위한 샘플 폴더 생성 여부"
  type        = bool
  default     = true
}

variable "sample_folder_display_name" {
  description = "생성할 샘플 하위 폴더 표시 이름 (create_sample_folder = true 인 경우 사용)"
  type        = string
  default     = "app-dev"
}

variable "groups" {
  description = "신규 조직(additional-domain.com)에 생성할 Cloud Identity 그룹 정의, 메인 도메인(@main-domain.com) 멤버 매핑 및 IAM 역할"
  type = map(object({
    email_prefix = string
    display_name = string
    description  = string
    members      = list(string)
    managers     = optional(list(string), [])
    org_roles    = optional(list(string), [])
    folder_roles = optional(list(string), [])
  }))
}
