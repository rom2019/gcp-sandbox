# ==============================================================================
# Orthogonal Resource Manager Tags, Declarative Bindings & Optional Folders
# ==============================================================================
# 핵심 설계 포인트:
# GCP Resource Manager는 동일한 TagKey 아래의 서로 다른 TagValue를 하나의 프로젝트/리소스에
# 중복 바인딩할 수 없습니다 (HTTP 400 충돌).
# 따라서 예외 도메인별로 독립된 8개의 TagKey(예: exempt-sa-key=true, exempt-serverless=true)를
# 분리 생성하여, 하나의 프로젝트나 개별 리소스(GCS 버킷, Cloud Run 서비스)에
# 복수의 정책 예외를 충돌 없이 조합 부착할 수 있도록 구성합니다.

locals {
  exemption_tag_keys = {
    sa_key = {
      short_name  = "${var.tag_key_prefix}-sa-key"
      description = "불가피한 외부 연동(서드파티 SaaS 등)을 위해 서비스 계정 키 생성 및 업로드 예외 허용"
    }
    public_iam = {
      short_name  = "${var.tag_key_prefix}-public-iam"
      description = "대외 공개 서비스(allUsers) 또는 외부 협업을 위해 IAM 허용 주체 제한(DRS) 예외 허용"
    }
    public_storage = {
      short_name  = "${var.tag_key_prefix}-public-storage"
      description = "공개 정적 에셋 버킷 등을 위해 Cloud Storage Public Access Prevention / UBLA 예외 허용"
    }
    external_ip = {
      short_name  = "${var.tag_key_prefix}-external-ip"
      description = "특수 목적 VM/게이트웨이에 외부 공인 IP 및 외부 프로토콜 포워딩 예외 허용"
    }
    public_sql = {
      short_name  = "${var.tag_key_prefix}-public-sql"
      description = "외부 연동용 Cloud SQL 인스턴스에 Public IP 및 Authorized Networks 예외 허용"
    }
    os_login = {
      short_name  = "${var.tag_key_prefix}-os-login"
      description = "기존 메타데이터 SSH 키 기반 자동화 워크로드의 OS Login 강제 예외 허용"
    }
    trusted_image = {
      short_name  = "${var.tag_key_prefix}-trusted-image"
      description = "외부 마켓플레이스 또는 서드파티 벤더 부팅 디스크 이미지 예외 허용"
    }
    serverless = {
      short_name  = "${var.tag_key_prefix}-serverless"
      description = "공개 웹훅·오픈 API용 Cloud Run 및 Cloud Functions 인그레스/VPC 이그레스/Invoker IAM 예외 허용"
    }
  }

  # 프로젝트 단위 선언적 예외 태그 바인딩 평탄화: "project_id:exemption_key" => { project_id, exemption }
  flattened_project_exemptions = merge([
    for project_id, exemptions in var.project_tag_exemptions : {
      for ex in distinct(exemptions) :
      "${project_id}:${ex}" => {
        project_id = project_id
        exemption  = ex
      }
    }
  ]...)

  # 개별 리전 리소스(GCS 버킷, Cloud Run 서비스 등) 단위 선언적 예외 태그 바인딩 맵
  flattened_regional_exemptions = {
    for item in var.regional_resource_tag_exemptions :
    "${item.location}:${item.parent}:${item.exemption}" => item
  }
}

resource "google_tags_tag_key" "exempt" {
  for_each = local.exemption_tag_keys

  parent      = "organizations/${var.org_id}"
  short_name  = each.value.short_name
  description = each.value.description
}

resource "google_tags_tag_value" "exempt_true" {
  for_each = local.exemption_tag_keys

  parent      = google_tags_tag_key.exempt[each.key].id
  short_name  = "true"
  description = "${each.value.short_name} 예외 활성화"
}

# 프로젝트 ID를 숫자형 Project Number로 변환하여 TagBinding API의 ID/Number 드리프트 방지
data "google_project" "exempt_target" {
  for_each = toset(keys(var.project_tag_exemptions))

  project_id = each.key
}

# 선언적 프로젝트 단위 예외 태그 바인딩
resource "google_tags_tag_binding" "project_exemption" {
  for_each = local.flattened_project_exemptions

  parent    = "//cloudresourcemanager.googleapis.com/projects/${data.google_project.exempt_target[each.value.project_id].number}"
  tag_value = google_tags_tag_value.exempt_true[each.value.exemption].id
}

# 선언적 리전 리소스(개별 GCS 버킷, Cloud Run 서비스 등) 단위 정밀 예외 태그 바인딩
resource "google_tags_location_tag_binding" "resource_exemption" {
  for_each = local.flattened_regional_exemptions

  parent    = each.value.parent
  location  = each.value.location
  tag_value = google_tags_tag_value.exempt_true[each.value.exemption].id
}

# policy_scope = "folder" 이고 기존 target_folder_id가 지정되지 않았을 때 자동 생성되는 실습/검증 폴더
resource "google_folder" "handson_lab" {
  count = var.policy_scope == "folder" && var.target_folder_id == "" ? 1 : 0

  display_name = var.handson_folder_display_name
  parent       = "organizations/${var.org_id}"
}

# 선택 사항: 표준 환경 폴더 구조 (Prod, Dev, Shared)
resource "google_folder" "env" {
  for_each = var.create_env_folders ? toset(["Prod", "Dev", "Shared"]) : toset([])

  display_name = each.value
  parent       = "organizations/${var.org_id}"
}
