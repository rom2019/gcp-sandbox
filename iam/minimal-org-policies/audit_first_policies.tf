# ==============================================================================
# [Tier 2: Audit-First Managed Policies] 사전 감사형 정책 (7종 — 초기: dry_run_spec)
# ==============================================================================
# 네이티브 Dry-Run 감사 및 하위 리소스 태그 예외를 지원하는 Google-Managed(.managed.) 정책들입니다.
#
# [운영 및 강제(ENFORCED) 승격 방법]
# 1. 초기 배포 시 'dry_run_spec' 블록으로 동작하여 실제 리소스를 차단하지 않고
#    Cloud Audit Logs(Policy 로그)에 위반 호출만 기록합니다.
# 2. 감사 로그 확인 및 예외 태그 부착을 마친 정책은 블록 이름을
#    'dry_run_spec' -> 'spec' 으로 변경하고 apply 하면 즉시 실제 강제(ENFORCED)로 전환됩니다!
#    (참고: 2024년 5월 이후 생성된 신규 Org에서 이미 Secure-by-Default로 강제 중인 정책을
#     그대로 유지하려면 처음부터 해당 블록의 'dry_run_spec'을 'spec'으로 변경하세요.)

# A-01. 서비스 계정 키(JSON) 신규 생성 차단 (Managed, GA)
resource "google_org_policy_policy" "disable_sa_key_creation" {
  name   = "${local.policy_parent}/policies/iam.managed.disableServiceAccountKeyCreation"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt SA key creation when tagged"
        description = "sa_key 예외 태그 부착 프로젝트 허용"
        expression  = local.tag_cond["sa_key"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# A-02. 외부 생성 서비스 계정 공개키 업로드 차단 (Managed, GA)
resource "google_org_policy_policy" "disable_sa_key_upload" {
  name   = "${local.policy_parent}/policies/iam.managed.disableServiceAccountKeyUpload"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt SA key upload when tagged"
        description = "sa_key 예외 태그 부착 프로젝트 허용"
        expression  = local.tag_cond["sa_key"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# A-03. Compute Engine OS Login 강제 (Managed, GA)
resource "google_org_policy_policy" "require_os_login" {
  name   = "${local.policy_parent}/policies/compute.managed.requireOsLogin"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt OS Login when tagged"
        description = "os_login 예외 태그 부착 프로젝트/VM 허용"
        expression  = local.tag_cond["os_login"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# A-04. 신뢰할 수 있는 부팅 디스크 이미지 프로젝트만 허용 (Managed, Public Preview)
# - var.trusted_image_projects 리스트에 'projects/<숫자번호>' 입력 시에만 생성됩니다.
resource "google_org_policy_policy" "trusted_image_projects" {
  count = length(var.trusted_image_projects) > 0 ? 1 : 0

  name   = "${local.policy_parent}/policies/compute.managed.trustedImageProjects"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt trusted image check when tagged"
        description = "trusted_image 예외 태그 부착 프로젝트 허용"
        expression  = local.tag_cond["trusted_image"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedValues = var.trusted_image_projects
        deniedValues  = []
      })
    }
  }
}

# A-05. 프로토콜 포워딩 유형 제한 (Managed, GA — INTERNAL만 허용하여 외부 IP 우회 포워딩 차단)
resource "google_org_policy_policy" "restrict_protocol_forwarding" {
  name   = "${local.policy_parent}/policies/compute.managed.restrictProtocolForwardingCreationForTypes"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt external protocol forwarding when tagged"
        description = "external_ip 예외 태그 부착 프로젝트/리소스 허용"
        expression  = local.tag_cond["external_ip"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
      parameters = jsonencode({
        allowedSchemes = ["INTERNAL"]
      })
    }
  }
}

# A-06. Compute Engine VM 외부 공인 IPv4 할당 차단 (Managed, GA — 개별 VM 태그 예외 지원)
resource "google_org_policy_policy" "vm_external_ip_access" {
  name   = "${local.policy_parent}/policies/compute.managed.vmExternalIpAccess"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt VM external IP when tagged"
        description = "external_ip 예외 태그 부착 프로젝트 또는 개별 VM 허용"
        expression  = local.tag_cond["external_ip"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}

# A-07. Cloud Run 서비스 IAM Invoker 인증 체크 필수화 (Managed, GA — 무인증 퍼블릭 노출 방지)
resource "google_org_policy_policy" "run_require_invoker_iam" {
  name   = "${local.policy_parent}/policies/run.managed.requireInvokerIam"
  parent = local.policy_parent

  # 강제 전환 시 'dry_run_spec' -> 'spec' 으로 변경
  dry_run_spec {
    rules {
      condition {
        title       = "Exempt Cloud Run Invoker IAM check when tagged"
        description = "serverless 예외 태그 부착 프로젝트 또는 개별 Cloud Run 서비스 허용"
        expression  = local.tag_cond["serverless"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}
