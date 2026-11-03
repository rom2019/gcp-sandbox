# ==============================================================================
# Scope, Shared Condition Expressions & Optional Folders
# ==============================================================================

locals {
  # 1. 정책을 부착할 상위 리소스 경로 결정
  #    - policy_scope = "organization" -> organizations/<org_id>
  #    - policy_scope = "folder"       -> 지정된 folders/<target_folder_id> 또는 자동 생성 실습 폴더
  policy_parent = (
    var.policy_scope == "organization" ? "organizations/${var.org_id}" :
    var.target_folder_id != "" ? "folders/${var.target_folder_id}" :
    google_folder.handson_lab[0].name
  )

  # 2. iam.managed.allowedPolicyMembers(차세대 DRS)에 허용할 조직 PrincipalSet 목록
  drs_allowed_principal_sets = [
    for id in distinct(concat([var.org_id], var.drs_allowed_org_ids)) :
    "//cloudresourcemanager.googleapis.com/organizations/${id}"
  ]

  # 3. 목적별 독립 Tag 조건식 헬퍼 (baseline / audit_first / opt_in 파일에서 공통 참조)
  tag_cond = {
    for k, v in local.exemption_tag_keys :
    k => "resource.matchTagId('${google_tags_tag_key.exempt[k].id}', '${google_tags_tag_value.exempt_true[k].id}')"
  }
}

# policy_scope = "folder" 이고 기존 target_folder_id가 비어 있을 때 자동 생성되는 격리 실습 폴더
resource "google_folder" "handson_lab" {
  count = var.policy_scope == "folder" && var.target_folder_id == "" ? 1 : 0

  display_name        = var.handson_folder_display_name
  parent              = "organizations/${var.org_id}"
  deletion_protection = false
}

# 선택 사항: 표준 환경 폴더 구조 (Prod, Dev, Shared)
resource "google_folder" "env" {
  for_each = var.create_env_folders ? toset(["Prod", "Dev", "Shared"]) : toset([])

  display_name = each.value
  parent       = "organizations/${var.org_id}"
}
