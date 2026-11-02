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
    - "folder"       : 하위 폴더 단위에만 격리 적용 (사전 Hands-On 실습, 정책 영향도 검증, 공유 테스트 조직용 권장)
    - "organization" : Organization 루트(organizations/<org_id>) 전체에 본 배포
  EOT
  type        = string
  default     = "organization"

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
# 2. Policy Tier Modes & Per-Policy Granular Overrides (티어별 기본 모드 및 개별 제어)
# ==============================================================================

variable "baseline_policy_mode" {
  description = <<-EOT
    [Baseline Guardrails — 12종] 기존 운영 워크로드 중단 위험이 없는 기본 보안 가드레일 티어의 기본 모드:
    - "ENFORCED"  : (권장 기본값) 즉시 강제 적용
    - "UNMANAGED" : 일괄 비활성화 (필요한 정책만 policy_mode_overrides로 개별 활성화할 때 사용)
  EOT
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["ENFORCED", "UNMANAGED"], var.baseline_policy_mode)
    error_message = "baseline_policy_mode는 'ENFORCED' 또는 'UNMANAGED' 중 하나여야 합니다."
  }
}

variable "audit_first_policy_mode" {
  description = <<-EOT
    [Audit-First Managed Policies — 7종] 네이티브 dry_run_spec을 지원하는 Google-Managed(.managed.) 정책 티어의 기본 모드:
    - "DRY_RUN"   : (권장 기본값) 리소스 차단 없이 Cloud Audit Logs에 위반 내역만 기록
    - "ENFORCED"  : 감사 완료 및 예외 태그 부착 후 전체 강제 차단 전환
    - "UNMANAGED" : 미적용
  EOT
  type        = string
  default     = "DRY_RUN"

  validation {
    condition     = contains(["DRY_RUN", "ENFORCED", "UNMANAGED"], var.audit_first_policy_mode)
    error_message = "audit_first_policy_mode는 'DRY_RUN', 'ENFORCED', 'UNMANAGED' 중 하나여야 합니다."
  }
}

variable "opt_in_policy_mode" {
  description = <<-EOT
    [Opt-In Workload Controls — 7종] API상 dry_run_spec 미지원으로 사전 자산 점검 및 프로젝트 단위 예외 태그 부착이 필요한 레거시 스토리지·서버리스 정책 티어의 기본 모드:
    - "UNMANAGED" : (권장 기본값) 초기에는 미적용 상태로 두고 준비된 정책부터 policy_mode_overrides로 순차 활성화
    - "ENFORCED"  : 예외 태그 선부착 완료 후 전체 강제 적용
  EOT
  type        = string
  default     = "UNMANAGED"

  validation {
    condition     = contains(["UNMANAGED", "ENFORCED"], var.opt_in_policy_mode)
    error_message = "opt_in_policy_mode는 'UNMANAGED' 또는 'ENFORCED' 중 하나여야 합니다."
  }
}

variable "policy_mode_overrides" {
  description = <<-EOT
    개별 제약조건('constraints/' 접두어 제외) 단위로 실행 모드를 덮어쓰는 맵 (티어 기본값보다 우선 적용).
    허용 모드: "ENFORCED" | "DRY_RUN" (.managed. 제약조건 전용) | "UNMANAGED"
    예시:
      policy_mode_overrides = {
        "run.managed.requireInvokerIam"  = "ENFORCED"
        "storage.publicAccessPrevention" = "ENFORCED"
        "compute.disableVpcExternalIpv6" = "UNMANAGED"
      }
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.policy_mode_overrides :
      contains(["ENFORCED", "DRY_RUN", "UNMANAGED"], v)
    ])
    error_message = "policy_mode_overrides의 각 값은 'ENFORCED', 'DRY_RUN', 'UNMANAGED' 중 하나여야 합니다."
  }

  validation {
    condition = alltrue([
      for k in keys(var.policy_mode_overrides) : contains([
        "iam.managed.allowedPolicyMembers",
        "iam.automaticIamGrantsForDefaultServiceAccounts",
        "iam.serviceAccountKeyExposureResponse",
        "compute.managed.disableSerialPortAccess",
        "compute.skipDefaultNetworkCreation",
        "compute.disableVpcExternalIpv6",
        "compute.restrictXpnProjectLienRemoval",
        "sql.managed.restrictPublicIp",
        "sql.managed.restrictAuthorizedNetworks",
        "compute.setNewProjectDefaultToZonalDNSOnly",
        "essentialcontacts.managed.allowedContactDomains",
        "compute.managed.disableNestedVirtualization",
        "iam.managed.disableServiceAccountKeyCreation",
        "iam.managed.disableServiceAccountKeyUpload",
        "compute.managed.requireOsLogin",
        "compute.managed.trustedImageProjects",
        "compute.managed.restrictProtocolForwardingCreationForTypes",
        "compute.managed.vmExternalIpAccess",
        "run.managed.requireInvokerIam",
        "storage.publicAccessPrevention",
        "storage.uniformBucketLevelAccess",
        "run.allowedIngress",
        "run.allowedVPCEgress",
        "cloudfunctions.allowedIngressSettings",
        "cloudfunctions.allowedVpcConnectorEgressSettings",
        "cloudfunctions.requireVPCConnector",
      ], k)
    ])
    error_message = "policy_mode_overrides에 지원되지 않는 제약조건 이름이 포함되어 있습니다. ('constraints/' 접두어를 제외한 정확한 제약조건 이름을 확인하세요.)"
  }

  validation {
    condition = alltrue([
      for k, v in var.policy_mode_overrides :
      v != "DRY_RUN" || can(regex("\\.managed\\.", k))
    ])
    error_message = "'DRY_RUN' 모드는 네이티브 dry_run_spec을 지원하는 Google-Managed('.managed.') 제약조건에만 설정할 수 있습니다."
  }
}

# ==============================================================================
# 3. Parameterized Policy Inputs (도메인·신뢰 이미지 등 파라미터 설정)
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
  description = "essentialcontacts.managed.allowedContactDomains(보안·장애 중요 알림) 수신을 허용할 이메일 도메인 목록 ('@'로 시작)"
  type        = list(string)
  default = [
    "@example.com",
  ]

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
# 4. Declarative Tag Exemptions (목적별 독립 예외 태그 및 선언적 바인딩)
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
# 5. Optional Cross-Org Migration & Auth Settings (선택: 조직 간 이관 및 인증 설정)
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
