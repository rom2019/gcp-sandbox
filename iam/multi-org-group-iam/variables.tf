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

variable "folders" {
  description = "신규 조직 루트 아래에 생성할 하위 폴더 이름 목록 (불필요 시 빈 리스트 [])"
  type        = set(string)
  default     = []
}

variable "groups" {
  description = "생성할 Cloud Identity 그룹(맵 키 = 이메일 프리픽스), 소속 멤버(@main_login_domain) 및 Org/Folder IAM 역할"
  type = map(object({
    display_name = optional(string)
    description  = optional(string, "")
    members      = optional(list(string), [])
    org_roles    = optional(list(string), [])
    folder_roles = optional(map(list(string)), {})
  }))

  validation {
    condition = alltrue(flatten([
      for g in values(var.groups) : [
        for email in g.members :
        endswith(lower(trimspace(email)), "@${lower(trimspace(var.main_login_domain))}")
      ]
    ]))
    error_message = "보안 정책 위반: 모든 그룹 멤버는 허용된 메인 로그인 도메인(@${var.main_login_domain}) 계정이어야 합니다."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.groups) : [
        for folder_name in keys(g.folder_roles) :
        contains(var.folders, folder_name)
      ]
    ]))
    error_message = "folder_roles에 지정된 폴더 이름은 반드시 var.folders 목록에 정의되어 있어야 합니다."
  }
}
