# ==============================================================================
# Organization Policy Catalog (3 Operational Tiers + Optional Cross-Org Import)
# ==============================================================================
# 모든 정책을 아래 3개의 범용 운영 티어로 구분하여 제어합니다:
# 1. baseline    (12종, 기본값 ENFORCED)  : 기존 워크로드 중단 위험이 없는 기본 보안 가드레일
# 2. audit_first (6종,  기본값 DRY_RUN)   : 네이티브 dry_run_spec 감사 후 전환하는 .managed. 정책
# 3. opt_in      (8종,  기본값 UNMANAGED) : 사전 자산 스캔 및 예외 태그 부착 후 선택 활성화하는 정책
# +  migration   (1종,  선택 활성화)      : allowed_import_source_org_ids 지정 시에만 프로젝트 반입 허용

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

  # 1) 리소스 ID에 의존하지 않는 정적 메타데이터 (terraform plan 전에도 활성 정책 목록 계산 가능)
  policy_tier_metadata = {
    # --- Optional Cross-Org Import ---
    "resourcemanager.allowedImportSources" = {
      tier         = "migration"
      enabled_when = length(var.allowed_import_source_org_ids) > 0
    }

    # --- Tier 1: Baseline Guardrails (12) ---
    "iam.managed.allowedPolicyMembers"                = { tier = "baseline", enabled_when = true }
    "iam.automaticIamGrantsForDefaultServiceAccounts" = { tier = "baseline", enabled_when = true }
    "iam.serviceAccountKeyExposureResponse"           = { tier = "baseline", enabled_when = true }
    "compute.managed.disableSerialPortAccess"         = { tier = "baseline", enabled_when = true }
    "compute.skipDefaultNetworkCreation"              = { tier = "baseline", enabled_when = true }
    "compute.disableVpcExternalIpv6"                  = { tier = "baseline", enabled_when = true }
    "compute.restrictXpnProjectLienRemoval"           = { tier = "baseline", enabled_when = true }
    "sql.managed.restrictPublicIp"                    = { tier = "baseline", enabled_when = true }
    "sql.managed.restrictAuthorizedNetworks"          = { tier = "baseline", enabled_when = true }
    "compute.setNewProjectDefaultToZonalDNSOnly"      = { tier = "baseline", enabled_when = true }
    "essentialcontacts.managed.allowedContactDomains" = { tier = "baseline", enabled_when = true }
    "compute.managed.disableNestedVirtualization"     = { tier = "baseline", enabled_when = true }

    # --- Tier 2: Audit-First Managed Policies (6) ---
    "iam.managed.disableServiceAccountKeyCreation"               = { tier = "audit_first", enabled_when = true }
    "iam.managed.disableServiceAccountKeyUpload"                 = { tier = "audit_first", enabled_when = true }
    "compute.managed.requireOsLogin"                             = { tier = "audit_first", enabled_when = true }
    "compute.managed.trustedImageProjects"                       = { tier = "audit_first", enabled_when = length(var.trusted_image_projects) > 0 }
    "compute.managed.restrictProtocolForwardingCreationForTypes" = { tier = "audit_first", enabled_when = true }
    "run.managed.requireInvokerIam"                              = { tier = "audit_first", enabled_when = true }

    # --- Tier 3: Opt-In Workload Controls (8) ---
    "storage.publicAccessPrevention"                   = { tier = "opt_in", enabled_when = true }
    "storage.uniformBucketLevelAccess"                 = { tier = "opt_in", enabled_when = true }
    "compute.vmExternalIpAccess"                       = { tier = "opt_in", enabled_when = true }
    "run.allowedIngress"                               = { tier = "opt_in", enabled_when = true }
    "run.allowedVPCEgress"                             = { tier = "opt_in", enabled_when = true }
    "cloudfunctions.allowedIngressSettings"            = { tier = "opt_in", enabled_when = true }
    "cloudfunctions.allowedVpcConnectorEgressSettings" = { tier = "opt_in", enabled_when = true }
    "cloudfunctions.requireVPCConnector"               = { tier = "opt_in", enabled_when = true }
  }

  tier_default_modes = {
    migration   = "ENFORCED"
    baseline    = var.baseline_policy_mode
    audit_first = var.audit_first_policy_mode
    opt_in      = var.opt_in_policy_mode
  }

  # 각 제약조건의 최종 유효 모드 ("ENFORCED" | "DRY_RUN" | "UNMANAGED")
  effective_policy_modes = {
    for constraint, meta in local.policy_tier_metadata :
    constraint => (
      !meta.enabled_when
      ? "UNMANAGED"
      : lookup(var.policy_mode_overrides, constraint, local.tier_default_modes[meta.tier])
    )
  }

  # 현재 설정에서 실제 생성·관리 대상인 제약조건 이름 목록 (scripts/generate-imports.sh 연동용)
  active_constraint_names = sort([
    for constraint, mode in local.effective_policy_modes :
    constraint if mode != "UNMANAGED"
  ])

  # 2) 제약조건별 상세 규칙(Rule) 카탈로그 정의
  policy_catalog = {
    # ==========================================================================
    # [선택] 타 GCP Organization으로부터 프로젝트/폴더 반입 허용 게이트웨이
    # - 참고: Shared VPC 무중단 Cross-Org 이관 시 원본 조직(Source Org)에서도 아래 2개 정책이 함께 열려 있어야 합니다:
    #   1) constraints/resourcemanager.allowedExportDestinations = ["under:organizations/<TARGET_ORG_ID>"]
    #   2) constraints/resourcemanager.allowEnabledServicesForExport = ["SHARED_VPC"]
    # ==========================================================================
    "resourcemanager.allowedImportSources" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = null
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = [for id in distinct(var.allowed_import_source_org_ids) : "under:organizations/${id}"]
        }
      ]
    }

    # ==========================================================================
    # [Tier 1: Baseline Guardrails] 기본 보안 가드레일 (12종 — 기본값 ENFORCED)
    # ==========================================================================

    # B-01. IAM 허용 주체 제한 (차세대 DRS — 레거시 iam.allowedPolicyMemberDomains 대체)
    "iam.managed.allowedPolicyMembers" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt public or external IAM when tagged"
            description = "public_iam 예외 태그 부착 프로젝트/리소스는 외부 또는 allUsers IAM 허용"
            expression  = local.tag_cond["public_iam"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition = null
          enforce   = "TRUE"
          allow_all = null
          deny_all  = null
          parameters = jsonencode({
            allowedPrincipalSets  = local.drs_allowed_principal_sets
            allowedMemberSubjects = var.drs_allowed_member_subjects
          })
          allowed_values = null
        }
      ]
    }

    # B-02. 신규 프로젝트 생성 시 기본 서비스 계정(Default SA)에 Editor 자동 부여 차단
    "iam.automaticIamGrantsForDefaultServiceAccounts" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-03. 서비스 계정 키 외부 유출 감지 시 자동 비활성화 (DISABLE_KEY)
    "iam.serviceAccountKeyExposureResponse" = {
      inherit_from_parent = false
      rules = [
        {
          condition      = null
          enforce        = null
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = ["DISABLE_KEY"]
        }
      ]
    }

    # B-04. VM 직렬 포트(Serial Port) 접근 통합 차단 (Managed)
    "compute.managed.disableSerialPortAccess" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-05. 신규 프로젝트 생성 시 취약한 default VPC 자동 생성 건너뛰기
    "compute.skipDefaultNetworkCreation" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-06. VPC 외부 IPv6 비활성화
    "compute.disableVpcExternalIpv6" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-07. Shared VPC 호스트 프로젝트 Lien(삭제 방지 잠금) 임의 제거 차단
    "compute.restrictXpnProjectLienRemoval" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-08. Cloud SQL 공인 IP 할당 차단 (Managed — 비소급 적용 + public_sql 태그 예외 지원)
    "sql.managed.restrictPublicIp" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt public Cloud SQL when tagged"
            description = "public_sql 예외 태그 부착 프로젝트는 Cloud SQL 공인 IP 허용"
            expression  = local.tag_cond["public_sql"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-09. Cloud SQL 승인된 네트워크(Authorized Networks) 추가 차단 (Managed — 비소급 적용)
    "sql.managed.restrictAuthorizedNetworks" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud SQL authorized networks when tagged"
            description = "public_sql 예외 태그 부착 프로젝트는 Authorized Networks 허용"
            expression  = local.tag_cond["public_sql"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-10. 신규 프로젝트 기본 내부 DNS를 Zonal DNS 전용으로 설정 (리전 장애 전파 방지)
    "compute.setNewProjectDefaultToZonalDNSOnly" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # B-11. Essential Contacts(보안·장애 중요 알림) 허용 도메인 제한 (Managed)
    "essentialcontacts.managed.allowedContactDomains" = {
      inherit_from_parent = null
      rules = [
        {
          condition = null
          enforce   = "TRUE"
          allow_all = null
          deny_all  = null
          parameters = jsonencode({
            allowedDomains = var.allowed_contact_domains
          })
          allowed_values = null
        }
      ]
    }

    # B-12. Compute Engine 중첩 가상화(Nested Virtualization) 비활성화 (Managed)
    "compute.managed.disableNestedVirtualization" = {
      inherit_from_parent = null
      rules = [
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # ==========================================================================
    # [Tier 2: Audit-First Managed Policies] 사전 감사형 정책 (6종 — 기본값 DRY_RUN)
    # ==========================================================================

    # A-01. 서비스 계정 키(JSON) 신규 생성 차단
    "iam.managed.disableServiceAccountKeyCreation" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt SA key creation when tagged"
            description = "sa_key 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["sa_key"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # A-02. 외부 생성 서비스 계정 공개키 업로드 차단
    "iam.managed.disableServiceAccountKeyUpload" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt SA key upload when tagged"
            description = "sa_key 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["sa_key"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # A-03. Compute Engine OS Login 강제
    "compute.managed.requireOsLogin" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt OS Login when tagged"
            description = "os_login 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["os_login"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # A-04. 신뢰할 수 있는 부팅 디스크 이미지 프로젝트만 허용 (trusted_image_projects 지정 시 활성)
    "compute.managed.trustedImageProjects" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt trusted image check when tagged"
            description = "trusted_image 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["trusted_image"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition = null
          enforce   = "TRUE"
          allow_all = null
          deny_all  = null
          parameters = jsonencode({
            allowedValues = var.trusted_image_projects
            deniedValues  = []
          })
          allowed_values = null
        }
      ]
    }

    # A-05. 프로토콜 포워딩 유형 제한 (INTERNAL만 허용하여 외부 IP 우회 포워딩 차단)
    "compute.managed.restrictProtocolForwardingCreationForTypes" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt external protocol forwarding when tagged"
            description = "external_ip 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["external_ip"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition = null
          enforce   = "TRUE"
          allow_all = null
          deny_all  = null
          parameters = jsonencode({
            allowedSchemes = ["INTERNAL"]
          })
          allowed_values = null
        }
      ]
    }

    # A-06. Cloud Run 서비스 IAM Invoker 인증 체크 필수화 (무인증 퍼블릭 노출 방지)
    "run.managed.requireInvokerIam" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Run Invoker IAM check when tagged"
            description = "serverless 예외 태그 부착 프로젝트/서비스 허용"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # ==========================================================================
    # [Tier 3: Opt-In Workload Controls] 선택 적용 워크로드 통제 정책 (8종 — 기본값 UNMANAGED)
    # ==========================================================================

    # O-01. [소급 차단 주의!] Cloud Storage 퍼블릭 액세스 방지
    "storage.publicAccessPrevention" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt public GCS bucket when tagged"
            description = "public_storage 예외 태그 부착 프로젝트/버킷 허용"
            expression  = local.tag_cond["public_storage"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # O-02. Cloud Storage 균일한 버킷 수준 액세스(UBLA) 강제 (비소급 — 신규 버킷 대상)
    "storage.uniformBucketLevelAccess" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt UBLA when tagged"
            description = "public_storage 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["public_storage"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # O-03. Compute Engine VM 외부 공인 IP 할당 차단
    "compute.vmExternalIpAccess" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt VM external IP when tagged"
            description = "external_ip 예외 태그 부착 프로젝트 허용"
            expression  = local.tag_cond["external_ip"]
          }
          enforce        = null
          allow_all      = "TRUE"
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = null
          allow_all      = null
          deny_all       = "TRUE"
          parameters     = null
          allowed_values = null
        }
      ]
    }

    # O-04. Cloud Run 인그레스 제한 (내부 트래픽 및 Cloud Load Balancing 경유만 허용)
    "run.allowedIngress" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Run ingress when tagged"
            description = "serverless 예외 태그 부착 프로젝트/서비스는 직접 외부 인그레스(all) 허용"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = null
          allow_all      = "TRUE"
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition  = null
          enforce    = null
          allow_all  = null
          deny_all   = null
          parameters = null
          allowed_values = [
            "internal",
            "internal-and-cloud-load-balancing",
          ]
        }
      ]
    }

    # O-05. Cloud Run VPC 이그레스 설정 강제
    "run.allowedVPCEgress" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Run VPC egress when tagged"
            description = "serverless 예외 태그 부착 프로젝트/서비스는 VPC 이그레스 강제 제외"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = null
          allow_all      = "TRUE"
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition  = null
          enforce    = null
          allow_all  = null
          deny_all   = null
          parameters = null
          allowed_values = [
            "private-ranges-only",
            "all-traffic",
          ]
        }
      ]
    }

    # O-06. Cloud Functions (1st Gen) 인그레스 제한
    "cloudfunctions.allowedIngressSettings" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Functions ingress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 모든 인그레스 허용"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = null
          allow_all      = "TRUE"
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition  = null
          enforce    = null
          allow_all  = null
          deny_all   = null
          parameters = null
          allowed_values = [
            "ALLOW_INTERNAL_ONLY",
            "ALLOW_INTERNAL_AND_GCLB",
          ]
        }
      ]
    }

    # O-07. Cloud Functions (1st Gen) VPC 커넥터 이그레스 설정 제한
    "cloudfunctions.allowedVpcConnectorEgressSettings" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Functions VPC egress when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 이그레스 제한 제외"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = null
          allow_all      = "TRUE"
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition  = null
          enforce    = null
          allow_all  = null
          deny_all   = null
          parameters = null
          allowed_values = [
            "PRIVATE_RANGES_ONLY",
            "ALL_TRAFFIC",
          ]
        }
      ]
    }

    # O-08. Cloud Functions (1st Gen) VPC 커넥터 연결 필수화
    "cloudfunctions.requireVPCConnector" = {
      inherit_from_parent = null
      rules = [
        {
          condition = {
            title       = "Exempt Cloud Functions VPC connector requirement when tagged"
            description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 필수화 제외"
            expression  = local.tag_cond["serverless"]
          }
          enforce        = "FALSE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        },
        {
          condition      = null
          enforce        = "TRUE"
          allow_all      = null
          deny_all       = null
          parameters     = null
          allowed_values = null
        }
      ]
    }
  }
}
