variable "customer_id" {
  description = "신규 GCP Organization의 Cloud Identity Directory Customer ID (예: C02xxxxxx)"
  type        = string
}

variable "group_email" {
  description = "생성할 Cloud Identity 그룹 이메일 주소 (예: gcp-users@additional-domain.com)"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.group_email))
    error_message = "유효한 그룹 이메일 주소(<prefix>@<domain>) 형식이어야 합니다."
  }
}

variable "display_name" {
  description = "Cloud Identity 그룹 표시 이름"
  type        = string
}

variable "description" {
  description = "Cloud Identity 그룹 설명"
  type        = string
  default     = ""
}

variable "main_login_domain" {
  description = "멤버로 허용할 단일 SSO 메인 로그인 도메인 (예: main-domain.com)"
  type        = string
}

variable "members" {
  description = "그룹에 MEMBER 역할로 등록할 사용자 이메일 목록 (@main_login_domain 계정만 허용)"
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.members :
      endswith(lower(trimspace(email)), "@${lower(trimspace(var.main_login_domain))}")
    ])
    error_message = "보안 정책 위반: 모든 그룹 멤버는 허용된 메인 로그인 도메인(@${var.main_login_domain}) 계정이어야 합니다."
  }
}

variable "sa_access_token" {
  description = "Groups Settings API 호출용 단기 Ephemeral 액세스 토큰 (State 미저장)"
  type        = string
  ephemeral   = true
  sensitive   = true
}
