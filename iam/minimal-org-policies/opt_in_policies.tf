# ==============================================================================
# [Tier 3: Opt-In Workload Controls] 선택 적용 워크로드 통제 정책 (7종 — 초기 주석 처리)
# ==============================================================================
# 아래 7개 레거시 제약조건은 GCP API상 네이티브 Dry-Run(dry_run_spec)을 지원하지 않으며,
# 버킷·서비스 등 하위 리소스 직접 태그가 아닌 프로젝트/폴더 단위 태그(project_tag_exemptions)만 평가합니다.
#
# [안전한 활성화 방법]
# 1. Cloud Asset Inventory로 기존 공개 버킷·외부 노출 서비스를 먼저 스캔합니다.
# 2. 예외가 필요한 프로젝트 ID를 terraform.tfvars의 project_tag_exemptions에 추가하고 apply 합니다.
# 3. 준비가 완료된 정책 블록만 주석(/* ... */)을 해제하고 terraform apply -parallelism=1 을 실행합니다.

/*
# O-01. [소급 차단 주의!] Cloud Storage 퍼블릭 액세스 방지
# - ENFORCED 즉시 기존 공개 버킷의 외부 읽기까지 차단(403)되므로 반드시 공개 버킷 소속 프로젝트에
#   project_tag_exemptions = { "<PROJECT_ID>" = ["public_storage"] } 선부착 후 주석을 해제하세요.
resource "google_org_policy_policy" "storage_public_access_prevention" {
  name   = "${local.policy_parent}/policies/storage.publicAccessPrevention"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt public GCS project when tagged"
        description = "public_storage 예외 태그 부착 프로젝트/폴더 허용"
        expression  = local.tag_cond["public_storage"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}
*/

/*
# O-02. Cloud Storage 균일한 버킷 수준 액세스(UBLA) 강제 (비소급 — 신규 생성 버킷 대상)
resource "google_org_policy_policy" "storage_uniform_bucket_level_access" {
  name   = "${local.policy_parent}/policies/storage.uniformBucketLevelAccess"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt UBLA when tagged"
        description = "public_storage 예외 태그 부착 프로젝트/폴더 허용"
        expression  = local.tag_cond["public_storage"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}
*/

/*
# O-03. Cloud Run 인그레스 제한 (내부 트래픽 및 Cloud Load Balancing 경유만 허용)
resource "google_org_policy_policy" "run_allowed_ingress" {
  name   = "${local.policy_parent}/policies/run.allowedIngress"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud Run ingress when tagged"
        description = "serverless 예외 태그 부착 프로젝트는 직접 외부 인그레스(all) 허용"
        expression  = local.tag_cond["serverless"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        allowed_values = [
          "internal",
          "internal-and-cloud-load-balancing",
        ]
      }
    }
  }
}
*/

/*
# O-04. Cloud Run VPC 이그레스 설정 강제
resource "google_org_policy_policy" "run_allowed_vpc_egress" {
  name   = "${local.policy_parent}/policies/run.allowedVPCEgress"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud Run VPC egress when tagged"
        description = "serverless 예외 태그 부착 프로젝트는 VPC 이그레스 강제 제외"
        expression  = local.tag_cond["serverless"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        allowed_values = [
          "private-ranges-only",
          "all-traffic",
        ]
      }
    }
  }
}
*/

/*
# O-05. Cloud Functions (1st Gen) 인그레스 제한
resource "google_org_policy_policy" "cloudfunctions_allowed_ingress" {
  name   = "${local.policy_parent}/policies/cloudfunctions.allowedIngressSettings"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud Functions ingress when tagged"
        description = "serverless 예외 태그 부착 프로젝트는 모든 인그레스 허용"
        expression  = local.tag_cond["serverless"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        allowed_values = [
          "ALLOW_INTERNAL_ONLY",
          "ALLOW_INTERNAL_AND_GCLB",
        ]
      }
    }
  }
}
*/

/*
# O-06. Cloud Functions (1st Gen) VPC 커넥터 이그레스 설정 제한
resource "google_org_policy_policy" "cloudfunctions_allowed_vpc_egress" {
  name   = "${local.policy_parent}/policies/cloudfunctions.allowedVpcConnectorEgressSettings"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud Functions VPC egress when tagged"
        description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 이그레스 제한 제외"
        expression  = local.tag_cond["serverless"]
      }
      allow_all = "TRUE"
    }
    rules {
      values {
        allowed_values = [
          "PRIVATE_RANGES_ONLY",
          "ALL_TRAFFIC",
        ]
      }
    }
  }
}
*/

/*
# O-07. Cloud Functions (1st Gen) VPC 커넥터 연결 필수화
resource "google_org_policy_policy" "cloudfunctions_require_vpc_connector" {
  name   = "${local.policy_parent}/policies/cloudfunctions.requireVPCConnector"
  parent = local.policy_parent

  spec {
    rules {
      condition {
        title       = "Exempt Cloud Functions VPC connector requirement when tagged"
        description = "serverless 예외 태그 부착 프로젝트는 VPC 커넥터 필수화 제외"
        expression  = local.tag_cond["serverless"]
      }
      enforce = "FALSE"
    }
    rules {
      enforce = "TRUE"
    }
  }
}
*/

# ==============================================================================
# [선택: 조직 간 이관 게이트웨이] 타 GCP Organization 프로젝트 반입 허용
# ==============================================================================
# - var.allowed_import_source_org_ids 에 원본 조직 ID 입력 시에만 자동 활성화됩니다.
# - 참고: Shared VPC 무중단 이관 시 원본 조직(Source Org)에서도 아래 2개 정책이 함께 열려 있어야 합니다:
#   1) constraints/resourcemanager.allowedExportDestinations = ["under:organizations/<TARGET_ORG_ID>"]
#   2) constraints/resourcemanager.allowEnabledServicesForExport = ["SHARED_VPC"]
resource "google_org_policy_policy" "allowed_import_sources" {
  count = length(var.allowed_import_source_org_ids) > 0 ? 1 : 0

  name   = "${local.policy_parent}/policies/resourcemanager.allowedImportSources"
  parent = local.policy_parent

  spec {
    rules {
      values {
        allowed_values = [
          for id in distinct(var.allowed_import_source_org_ids) :
          "under:organizations/${id}"
        ]
      }
    }
  }
}
