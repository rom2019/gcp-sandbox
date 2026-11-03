# ==============================================================================
# [Tier 1: Baseline Guardrails] 기본 보안 가드레일 (12종 — 즉시 강제: spec)
# ==============================================================================
# 기존 운영 워크로드에 소급 중단 위험이 없는 기본 보안 정책들입니다.
# 모든 정책이 정적(Static) 리소스 블록으로 명시되어 있어, 필요 없는 정책은 주석 처리하거나
# 개별 규칙을 직접 수정하여 직관적으로 관리할 수 있습니다.

# B-01. IAM 허용 주체 제한 (차세대 DRS — 레거시 iam.allowedPolicyMemberDomains 대체)
# - 2024년 5월 이후 생성된 신규 조직에는 레거시 'iam.allowedPolicyMemberDomains'가 기본 강제되어 있으므로,
#   본 차세대 '.managed.' 정책 적용 후 중복 평가를 막기 위해 레거시 정책은 해제(delete/reset)하는 것을 권장합니다.
# - 기존에 도메인 제한 없이 외부 협업 계정이나 공개 서비스를 운영하던 조직(Brownfield)에 처음 도입할 때는
#   'spec'을 'dry_run_spec'으로 바꾸어 감사 로그를 먼저 확인한 뒤 강제 전환하는 것을 권장합니다.
resource "google_org_policy_policy" "allowed_policy_members" {
  name   = "${local.policy_parent}/policies/iam.managed.allowedPolicyMembers"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt public or external IAM when tagged"
        description = "public_iam 예외 태그 부착 프로젝트/리소스는 외부 또는 allUsers IAM 허용"
        expression  = local.tag_cond["public_iam"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedPrincipalSets  = local.drs_allowed_principal_sets
        allowedMemberSubjects = var.drs_allowed_member_subjects
      })
    }
  }
}

# B-02. 신규 프로젝트 생성 시 기본 서비스 계정(Default SA)에 Editor 자동 부여 차단
resource "google_org_policy_policy" "disable_default_sa_grants" {
  name   = "${local.policy_parent}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-03. 서비스 계정 키 외부 유출 감지 시 자동 비활성화 (DISABLE_KEY)
resource "google_org_policy_policy" "sa_key_exposure_response" {
  name   = "${local.policy_parent}/policies/iam.serviceAccountKeyExposureResponse"
  parent = local.policy_parent

  spec {
    inherit_from_parent = false
    rules {
      values {
        allowed_values = ["DISABLE_KEY"]
      }
    }
  }
}

# B-04. VM 직렬 포트(Serial Port) 접근 통합 차단 (Managed, GA)
resource "google_org_policy_policy" "disable_serial_port_access" {
  name   = "${local.policy_parent}/policies/compute.managed.disableSerialPortAccess"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-05. 신규 프로젝트 생성 시 취약한 default VPC 자동 생성 건너뛰기
resource "google_org_policy_policy" "skip_default_network" {
  name   = "${local.policy_parent}/policies/compute.skipDefaultNetworkCreation"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-06. VPC 외부 IPv6 비활성화
resource "google_org_policy_policy" "disable_vpc_external_ipv6" {
  name   = "${local.policy_parent}/policies/compute.disableVpcExternalIpv6"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-07. Shared VPC 호스트 프로젝트 Lien(삭제 방지 잠금) 임의 제거 차단
resource "google_org_policy_policy" "restrict_xpn_lien_removal" {
  name   = "${local.policy_parent}/policies/compute.restrictXpnProjectLienRemoval"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-08. Cloud SQL 공인 IP 할당 차단 (Managed, GA — 비소급 적용 + public_sql 태그 예외 지원)
resource "google_org_policy_policy" "sql_restrict_public_ip" {
  name   = "${local.policy_parent}/policies/sql.managed.restrictPublicIp"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt public Cloud SQL when tagged"
        description = "public_sql 예외 태그 부착 프로젝트/인스턴스는 Cloud SQL 공인 IP 허용"
        expression  = local.tag_cond["public_sql"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# B-09. Cloud SQL 승인된 네트워크(Authorized Networks) 추가 차단 (Managed, GA — 비소급 적용)
resource "google_org_policy_policy" "sql_restrict_authorized_networks" {
  name   = "${local.policy_parent}/policies/sql.managed.restrictAuthorizedNetworks"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud SQL authorized networks when tagged"
        description = "public_sql 예외 태그 부착 프로젝트/인스턴스는 Authorized Networks 허용"
        expression  = local.tag_cond["public_sql"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# B-10. 신규 프로젝트 기본 내부 DNS를 Zonal DNS 전용으로 설정 (리전 장애 전파 방지)
resource "google_org_policy_policy" "zonal_dns_only" {
  name   = "${local.policy_parent}/policies/compute.setNewProjectDefaultToZonalDNSOnly"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# B-11. Essential Contacts(보안·장애 중요 알림) 허용 도메인 제한 (Managed, GA)
resource "google_org_policy_policy" "allowed_contact_domains" {
  name   = "${local.policy_parent}/policies/essentialcontacts.managed.allowedContactDomains"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedDomains = var.allowed_contact_domains
      })
    }
  }
}

# B-12. Compute Engine 중첩 가상화(Nested Virtualization) 비활성화 (Managed, GA)
resource "google_org_policy_policy" "disable_nested_virtualization" {
  name   = "${local.policy_parent}/policies/compute.managed.disableNestedVirtualization"
  parent = local.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
