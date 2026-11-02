# ==============================================================================
# Organization Policy Catalog (Single Source of Truth)
# ==============================================================================
# 모든 정책을 단일 카탈로그(local.policy_catalog) 한 곳에서 직관적으로 정의합니다.
# - 각 정책은 필요한 속성만 간결하게 선언하며, 생략된 선택 속성(null)은 main.tf에서 자동 정규화됩니다.
# - 티어 구분:
#   1) baseline    (12종, 기본 ENFORCED)  : 기존 워크로드 중단 위험이 없는 기본 보안 가드레일
#   2) audit_first (7종,  기본 DRY_RUN)   : 네이티브 dry_run_spec 및 리소스 태그 예외를 지원하는 .managed. 정책
#   3) opt_in      (7종,  기본 UNMANAGED) : 사전 자산 스캔 및 프로젝트 태그 부착 후 개별 활성화하는 레거시 정책
#   4) migration   (1종,  조건부 활성)    : allowed_import_source_org_ids 지정 시에만 프로젝트 반입 허용

locals {
  # iam.managed.allowedPolicyMembers(차세대 DRS)에 허용할 조직 PrincipalSet 목록
  drs_allowed_principal_sets = [
    for id in distinct(concat([var.org_id], var.drs_allowed_org_ids)) :
    "//cloudresourcemanager.googleapis.com/organizations/${id}"
  ]

  # 목적별 독립 Tag 조건식 헬퍼 (동일 프로젝트/리소스에 다중 예외 조합 가능)
  tag_cond = {
    for k, v in local.exemption_tag_keys :
    k => "resource.matchTagId('${google_tags_tag_key.exempt[k].id}', '${google_tags_tag_value.exempt_true[k].id}')"
  }

  policy_catalog = {
    # ==========================================================================
    # [Tier 1: Baseline Guardrails] 기본 보안 가드레일 (12종 — 기본값 ENFORCED)
    # ==========================================================================

    # B-01. IAM 허용 주체 제한 (차세대 DRS — 레거시 iam.allowedPolicyMemberDomains 대체)
    "iam.managed.allowedPolicyMembers" = {
      tier = "baseline"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt public or external IAM when tagged"
            description = "public_iam 예외 태그 부착 프로젝트/리소스는 외부 또는 allUsers IAM 허용"
            expression  = local.tag_cond["public_iam"]
          }
        },
        {
          enforce = "TRUE"
          parameters = jsonencode({
            allowedPrincipalSets  = local.drs_allowed_principal_sets
            allowedMemberSubjects = var.drs_allowed_member_subjects
          })
        },
      ]
    }

    # B-02. 신규 프로젝트 생성 시 기본 서비스 계정(Default SA)에 Editor 자동 부여 차단
    "iam.automaticIamGrantsForDefaultServiceAccounts" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-03. 서비스 계정 키 외부 유출 감지 시 자동 비활성화 (DISABLE_KEY)
    "iam.serviceAccountKeyExposureResponse" = {
      tier                = "baseline"
      inherit_from_parent = false
      rules               = [{ allowed_values = ["DISABLE_KEY"] }]
    }

    # B-04. VM 직렬 포트(Serial Port) 접근 통합 차단 (Managed, GA)
    "compute.managed.disableSerialPortAccess" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-05. 신규 프로젝트 생성 시 취약한 default VPC 자동 생성 건너뛰기
    "compute.skipDefaultNetworkCreation" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-06. VPC 외부 IPv6 비활성화
    "compute.disableVpcExternalIpv6" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-07. Shared VPC 호스트 프로젝트 Lien(삭제 방지 잠금) 임의 제거 차단
    "compute.restrictXpnProjectLienRemoval" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-08. Cloud SQL 공인 IP 할당 차단 (Managed, GA — 비소급 적용 + public_sql 태그 예외 지원)
    "sql.managed.restrictPublicIp" = {
      tier = "baseline"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt public Cloud SQL when tagged"
            description = "public_sql 예외 태그 부착 프로젝트/인스턴스는 Cloud SQL 공인 IP 허용"
            expression  = local.tag_cond["public_sql"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # B-09. Cloud SQL 승인된 네트워크(Authorized Networks) 추가 차단 (Managed, GA — 비소급 적용)
    "sql.managed.restrictAuthorizedNetworks" = {
      tier = "baseline"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt Cloud SQL authorized networks when tagged"
            description = "public_sql 예외 태그 부착 프로젝트/인스턴스는 Authorized Networks 허용"
            expression  = local.tag_cond["public_sql"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # B-10. 신규 프로젝트 기본 내부 DNS를 Zonal DNS 전용으로 설정 (리전 장애 전파 방지)
    "compute.setNewProjectDefaultToZonalDNSOnly" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # B-11. Essential Contacts(보안·장애 중요 알림) 허용 도메인 제한 (Managed, GA)
    "essentialcontacts.managed.allowedContactDomains" = {
      tier = "baseline"
      rules = [
        {
          enforce    = "TRUE"
          parameters = jsonencode({ allowedDomains = var.allowed_contact_domains })
        },
      ]
    }

    # B-12. Compute Engine 중첩 가상화(Nested Virtualization) 비활성화 (Managed, GA)
    "compute.managed.disableNestedVirtualization" = {
      tier  = "baseline"
      rules = [{ enforce = "TRUE" }]
    }

    # ==========================================================================
    # [Tier 2: Audit-First Managed Policies] 사전 감사형 정책 (7종 — 기본값 DRY_RUN)
    # ==========================================================================

    # A-01. 서비스 계정 키(JSON) 신규 생성 차단 (Managed, GA)
    "iam.managed.disableServiceAccountKeyCreation" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt SA key creation when tagged"
            description = "sa_key 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["sa_key"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # A-02. 외부 생성 서비스 계정 공개키 업로드 차단 (Managed, GA)
    "iam.managed.disableServiceAccountKeyUpload" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt SA key upload when tagged"
            description = "sa_key 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["sa_key"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # A-03. Compute Engine OS Login 강제 (Managed, GA)
    "compute.managed.requireOsLogin" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt OS Login when tagged"
            description = "os_login 예외 태그 부착 프로젝트/VM 허용"
            expression  = local.tag_cond["os_login"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # A-04. 신뢰할 수 있는 부팅 디스크 이미지 프로젝트만 허용 (Managed, Public Preview — trusted_image_projects 지정 시 활성)
    "compute.managed.trustedImageProjects" = {
      tier    = "audit_first"
      enabled = length(var.trusted_image_projects) > 0
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt trusted image check when tagged"
            description = "trusted_image 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["trusted_image"]
          }
        },
        {
          enforce = "TRUE"
          parameters = jsonencode({
            allowedValues = var.trusted_image_projects
            deniedValues  = []
          })
        },
      ]
    }

    # A-05. 프로토콜 포워딩 유형 제한 (Managed, GA — INTERNAL만 허용하여 외부 IP 우회 포워딩 차단)
    "compute.managed.restrictProtocolForwardingCreationForTypes" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt external protocol forwarding when tagged"
            description = "external_ip 예외 태그 부착 프로젝트/리소스 허용"
            expression  = local.tag_cond["external_ip"]
          }
        },
        {
          enforce    = "TRUE"
          parameters = jsonencode({ allowedSchemes = ["INTERNAL"] })
        },
      ]
    }

    # A-06. Compute Engine VM 외부 공인 IPv4 할당 차단 (Managed, GA — DRY_RUN 및 개별 VM 태그 예외 지원)
    "compute.managed.vmExternalIpAccess" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt VM external IP when tagged"
            description = "external_ip 예외 태그 부착 프로젝트 또는 개별 VM 허용"
            expression  = local.tag_cond["external_ip"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # A-07. Cloud Run 서비스 IAM Invoker 인증 체크 필수화 (Managed, GA — 무인증 퍼블릭 노출 방지)
    "run.managed.requireInvokerIam" = {
      tier = "audit_first"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt Cloud Run Invoker IAM check when tagged"
            description = "serverless 예외 태그 부착 프로젝트 또는 개별 Cloud Run 서비스 허용"
            expression  = local.tag_cond["serverless"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # ==========================================================================
    # [Tier 3: Opt-In Workload Controls] 선택 적용 워크로드 통제 정책 (7종 — 기본값 UNMANAGED)
    # - 주의: 아래 레거시 제약조건들은 프로젝트/폴더 단위 태그(project_tag_exemptions)만 평가하며,
    #   버킷이나 Cloud Run 서비스에 직접 붙인 리소스 태그는 평가하지 않습니다.
    # ==========================================================================

    # O-01. [소급 차단 주의!] Cloud Storage 퍼블릭 액세스 방지 (예외는 반드시 프로젝트/폴더 단위로 부여)
    "storage.publicAccessPrevention" = {
      tier = "opt_in"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt public GCS project when tagged"
            description = "public_storage 예외 태그 부착 프로젝트/폴더 허용"
            expression  = local.tag_cond["public_storage"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # O-02. Cloud Storage 균일한 버킷 수준 액세스(UBLA) 강제 (비소급 — 신규 버킷 대상)
    "storage.uniformBucketLevelAccess" = {
      tier = "opt_in"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt UBLA when tagged"
            description = "public_storage 예외 태그 부착 프로젝트/폴더 허용"
            expression  = local.tag_cond["public_storage"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # O-03. Cloud Run 인그레스 제한 (내부 트래픽 및 Cloud Load Balancing 경유만 허용)
    "run.allowedIngress" = {
      tier = "opt_in"
      rules = [
        {
          allow_all = "TRUE"
          condition = {
            title       = "Exempt Cloud Run ingress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 직접 외부 인그레스(all) 허용"
            expression  = local.tag_cond["serverless"]
          }
        },
        {
          allowed_values = ["internal", "internal-and-cloud-load-balancing"]
        },
      ]
    }

    # O-04. Cloud Run VPC 이그레스 설정 강제
    "run.allowedVPCEgress" = {
      tier = "opt_in"
      rules = [
        {
          allow_all = "TRUE"
          condition = {
            title       = "Exempt Cloud Run VPC egress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 VPC 이그레스 강제 제외"
            expression  = local.tag_cond["serverless"]
          }
        },
        {
          allowed_values = ["private-ranges-only", "all-traffic"]
        },
      ]
    }

    # O-05. Cloud Functions (1st Gen) 인그레스 제한
    "cloudfunctions.allowedIngressSettings" = {
      tier = "opt_in"
      rules = [
        {
          allow_all = "TRUE"
          condition = {
            title       = "Exempt Cloud Functions ingress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 모든 인그레스 허용"
            expression  = local.tag_cond["serverless"]
          }
        },
        {
          allowed_values = ["ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"]
        },
      ]
    }

    # O-06. Cloud Functions (1st Gen) VPC 커넥터 이그레스 설정 제한
    "cloudfunctions.allowedVpcConnectorEgressSettings" = {
      tier = "opt_in"
      rules = [
        {
          allow_all = "TRUE"
          condition = {
            title       = "Exempt Cloud Functions VPC egress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 이그레스 제한 제외"
            expression  = local.tag_cond["serverless"]
          }
        },
        {
          allowed_values = ["PRIVATE_RANGES_ONLY", "ALL_TRAFFIC"]
        },
      ]
    }

    # O-07. Cloud Functions (1st Gen) VPC 커넥터 연결 필수화
    "cloudfunctions.requireVPCConnector" = {
      tier = "opt_in"
      rules = [
        {
          enforce = "FALSE"
          condition = {
            title       = "Exempt Cloud Functions VPC connector requirement when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 필수화 제외"
            expression  = local.tag_cond["serverless"]
          }
        },
        { enforce = "TRUE" },
      ]
    }

    # ==========================================================================
    # [선택] 타 GCP Organization으로부터 프로젝트/폴더 반입 허용 게이트웨이
    # - 참고: Shared VPC 무중단 Cross-Org 이관 시 원본 조직(Source Org)에서도 아래 2개 정책이 함께 열려 있어야 합니다:
    #   1) constraints/resourcemanager.allowedExportDestinations = ["under:organizations/<TARGET_ORG_ID>"]
    #   2) constraints/resourcemanager.allowEnabledServicesForExport = ["SHARED_VPC"]
    # ==========================================================================
    "resourcemanager.allowedImportSources" = {
      tier    = "migration"
      enabled = length(var.allowed_import_source_org_ids) > 0
      rules = [
        {
          allowed_values = [for id in distinct(var.allowed_import_source_org_ids) : "under:organizations/${id}"]
        },
      ]
    }
  }
}
