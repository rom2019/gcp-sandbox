variable "additional_domain" {
  description = "신규 분리 GCP Organization 도메인 (예: additional-domain.com)"
  type        = string
}

variable "main_login_domain" {
  description = "임직원이 단일 SSO 로그인에 사용하는 메인 도메인 (예: main-domain.com). 이 도메인 계정만 그룹 멤버로 허용됩니다."
  type        = string
}

variable "tf_service_account_email" {
  description = "Groups Admin 및 신규 조직 관리 권한이 부여된 Keyless Terraform Service Account 이메일"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^.]+\\.iam\\.gserviceaccount\\.com$", var.tf_service_account_email))
    error_message = "유효한 GCP Service Account 이메일(<name>@<project-id>.iam.gserviceaccount.com)을 입력해야 합니다."
  }
}

# ==============================================================================
# 그룹별 소속 멤버 (@main_login_domain 계정 목록) 및 대상 프로젝트 ID
# ==============================================================================

variable "gcp_users_members" {
  description = "신규 조직 접근 전 임직원 그룹(gcp-users) 멤버 목록 — 상단 조직 스위처 노출용"
  type        = set(string)
  default     = []
}

variable "gcp_org_admins_members" {
  description = "조직 플랫폼 관리자 그룹(gcp-org-admins) 멤버 목록 — 폴더 계층 및 프로젝트 생성 담당"
  type        = set(string)
  default     = []
}

variable "gcp_app_devs_members" {
  description = "앱 개발팀 폴더(app-dev) 최소 권한 그룹(gcp-app-devs) 멤버 목록"
  type        = set(string)
  default     = []
}

variable "gcp_prj_admins_members" {
  description = "특정 워크로드 프로젝트 전담 관리자 그룹(gcp-prj-admins) 멤버 목록"
  type        = set(string)
  default     = []
}

variable "gcp_prj_admins_project_ids" {
  description = "gcp-prj-admins 그룹에 프로젝트 최고 관리 권한(Editor + Project IAM Admin)을 부여할 대상 GCP Project ID 목록"
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for pid in var.gcp_prj_admins_project_ids :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", pid))
    ])
    error_message = "유효한 GCP Project ID(소문자·숫자·하이픈 6~30자)를 입력해야 합니다."
  }
}
