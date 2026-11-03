# ==============================================================================
# 1. Target Organization & Scope Configuration (적용 대상 조직 및 범위)
# ==============================================================================

variable "org_id" {
  description = "대상 GCP Organization의 숫자형 ID (예: '123456789012')"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id에는 숫자형 GCP Organization ID(예: '123456789012')를 입력해야 합니다."
  }
}

variable "policy_scope" {
  description = <<-EOT
    조직 정책을 부착할 계층 범위:
    - "folder"       : 하위 폴더 단위에만 격리 적용 (사전 Hands-On 실습, 정책 영향도 검증, 공유 테스트 조직용 기본값)
    - "organization" : Organization 루트(organizations/<org_id>) 전체에 본 배포
  EOT
  type        = string
  default     = "folder"

  validation {
    condition     = contains(["organization", "folder"], var.policy_scope)
    error_message = "policy_scope는 'organization' 또는 'folder' 중 하나여야 합니다."
  }
}

variable "target_folder_id" {
  description = <<-EOT
    policy_scope = "folder" 설정 시 정책을 부착할 기존 폴더의 숫자형 ID (예: '9876543210').
    비워두면("") handson_folder_display_name 이름으로 실습용 격리 폴더를 자동 생성합니다.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.target_folder_id == "" || can(regex("^[0-9]+$", var.target_folder_id))
    error_message = "target_folder_id는 비워두거나 'folders/' 접두어를 제외한 숫자형 폴더 ID여야 합니다."
  }
}

variable "handson_folder_display_name" {
  description = "policy_scope = 'folder' 이고 target_folder_id가 비어 있을 때 자동 생성할 실습/검증 폴더 표시 이름"
  type        = string
  default     = "policy-handson-lab"
}

variable "create_env_folders" {
  description = "조직 하위에 표준 환경 폴더(Prod, Dev, Shared)를 함께 생성할지 여부"
  type        = bool
  default     = false
}

# ==============================================================================
# 2. Parameterized Policy Inputs (도메인·신뢰 이미지 등 파라미터 설정)
# ==============================================================================

variable "drs_allowed_org_ids" {
  description = <<-EOT
    iam.managed.allowedPolicyMembers(차세대 DRS)에 현재 조직(org_id) 외에 추가로 IAM 바인딩을 허용할 외부/관계사 GCP Organization 숫자형 ID 목록.
    - 단일 조직 격리 운영(또는 multi-org-group-iam의 신규 조직 그룹 위임 패턴 사용) 시 빈 리스트([])를 유지하세요.
    - 타 조직 소속 서비스 계정·그룹·사용자를 현재 조직 리소스에 직접 IAM 바인딩해야 하는 경우에만 해당 Org ID를 추가합니다.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.drs_allowed_org_ids : can(regex("^[0-9]+$", id))])
    error_message = "drs_allowed_org_ids의 모든 항목은 숫자형 GCP Organization ID여야 합니다."
  }
}

variable "drs_allowed_member_subjects" {
  description = "iam.managed.allowedPolicyMembers에 개별 예외 허용할 주체 목록 (예: ['user:partner@example.com', 'serviceAccount:ci@proj.iam.gserviceaccount.com'])"
  type        = list(string)
  default     = []
}

variable "allowed_contact_domains" {
  description = "essentialcontacts.managed.allowedContactDomains(보안·장애 중요 알림) 수신을 허용할 이메일 도메인 목록 ('@'로 시작, 필수 입력)"
  type        = list(string)

  validation {
    condition     = length(var.allowed_contact_domains) > 0 && alltrue([for d in var.allowed_contact_domains : startswith(d, "@")])
    error_message = "최소 1개 이상의 '@domain.com' 형식 이메일 도메인이 필요합니다."
  }
}

variable "trusted_image_projects" {
  description = <<-EOT
    compute.managed.trustedImageProjects (Public Preview)에 허용할 부팅 디스크 이미지 소스 목록.
    주의: Google-Managed 제약조건 규격상 문자열 프로젝트 ID가 아닌 'projects/<PROJECT_NUMBER>', 'folders/<FOLDER_ID>', 'organizations/<ORG_ID>' 숫자 ID 형식이어야 합니다.
    비워두면([]) 해당 정책 리소스를 생성하지 않습니다.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.trusted_image_projects : can(regex("^(organizations|folders|projects)/[0-9]+$", p))])
    error_message = "trusted_image_projects 항목은 'organizations/숫자', 'folders/숫자', 또는 'projects/숫자' 형식이어야 합니다."
  }
}

# ==============================================================================
# 3. Declarative Tag Exemptions (목적별 독립 예외 태그 및 선언적 바인딩)
# ==============================================================================

variable "tag_key_prefix" {
  description = "예외 처리용 Resource Manager TagKey 접두어 (기본값 'exempt' -> exempt-sa-key 등 생성. 공유 테스트 조직 내 이름 충돌 방지 시 변경 가능)"
  type        = string
  default     = "exempt"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,25}$", var.tag_key_prefix))
    error_message = "tag_key_prefix는 영문 소문자로 시작하는 2~26자 소문자/숫자/하이픈 조합이어야 합니다."
  }
}

variable "project_tag_exemptions" {
  description = <<-EOT
    프로젝트 단위로 부착할 목적별 예외 태그 선언 맵 (키: 프로젝트 ID, 값: 예외 도메인 키 목록).
    조직·폴더·프로젝트에 부착된 태그는 모든 제약조건(.managed. 및 레거시 Opt-In 전체)에서 상속 평가됩니다.
    지원 예외 키: "sa_key" | "public_iam" | "public_storage" | "external_ip" | "public_sql" | "os_login" | "trusted_image" | "serverless"
    예시:
      project_tag_exemptions = {
        "public-assets-prod" = ["public_storage"]
        "legacy-cicd-prod"   = ["sa_key", "serverless"]
      }
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue(flatten([
      for proj_id, exemptions in var.project_tag_exemptions : [
        for ex in exemptions : contains([
          "sa_key",
          "public_iam",
          "public_storage",
          "external_ip",
          "public_sql",
          "os_login",
          "trusted_image",
          "serverless",
        ], ex)
      ]
    ]))
    error_message = "project_tag_exemptions에는 지원되는 8종 예외 키(sa_key, public_iam, public_storage, external_ip, public_sql, os_login, trusted_image, serverless)만 지정할 수 있습니다."
  }
}

variable "regional_resource_tag_exemptions" {
  description = <<-EOT
    프로젝트 전체 대신 개별 리전/존 서비스 리소스(Cloud Run 서비스, Compute Engine VM 등)에 직접 예외 태그를 바인딩하는 목록.
    [주의] 하위 서비스 리소스에 직접 부착한 태그는 Google-Managed('.managed.') 제약조건(예: run.managed.requireInvokerIam, compute.managed.vmExternalIpAccess)에서만 평가됩니다.
    storage.publicAccessPrevention, run.allowedIngress 등 레거시(Opt-In) 제약조건은 반드시 project_tag_exemptions(프로젝트 단위)를 사용하세요.
    예시:
      regional_resource_tag_exemptions = [
        {
          parent    = "//run.googleapis.com/projects/my-app-prod/locations/asia-northeast3/services/public-webhook"
          location  = "asia-northeast3"
          exemption = "serverless"
        }
      ]
  EOT
  type = list(object({
    parent    = string
    location  = string
    exemption = string
  }))
  default = []

  validation {
    condition = alltrue([
      for item in var.regional_resource_tag_exemptions : contains([
        "sa_key",
        "public_iam",
        "public_storage",
        "external_ip",
        "public_sql",
        "os_login",
        "trusted_image",
        "serverless",
      ], item.exemption)
    ])
    error_message = "regional_resource_tag_exemptions의 exemption 필드는 지원되는 8종 예외 키 중 하나여야 합니다."
  }
}

# ==============================================================================
# 4. Optional Cross-Org Migration & Auth Settings (선택: 조직 간 이관 및 인증 설정)
# ==============================================================================

variable "allowed_import_source_org_ids" {
  description = <<-EOT
    (선택) 타 GCP Organization으로부터 현재 조직으로 프로젝트/폴더 반입(resourcemanager.allowedImportSources)을 허용할 원본 GCP Organization 숫자형 ID 목록.
    조직 간 프로젝트 이관이 필요 없는 경우 빈 리스트([])로 두며, 이관 완료 후에도 []로 되돌려 반입 경로를 닫는 것을 권장합니다.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.allowed_import_source_org_ids : can(regex("^[0-9]+$", id))])
    error_message = "allowed_import_source_org_ids의 모든 항목은 숫자형 GCP Organization ID여야 합니다."
  }
}

variable "tf_service_account_email" {
  description = "(선택) Keyless Service Account Impersonation으로 실행할 Terraform 전용 서비스 계정 이메일 (예: 'tf-iam-admin@iam-seed-prod-01.iam.gserviceaccount.com', null이면 로컬 ADC 계정 사용)"
  type        = string
  default     = null
}

variable "billing_project_id" {
  description = "(선택) API 쿼터 차감 기준이 될 부트스트랩/Seed 프로젝트 ID (예: 'iam-seed-prod-01')"
  type        = string
  default     = null
}
