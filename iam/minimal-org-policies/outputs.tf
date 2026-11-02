output "policy_target_parent" {
  description = "조직 정책이 실제 부착된 상위 리소스 경로 (organizations/<ORG_ID> 또는 folders/<FOLDER_ID>)"
  value       = local.policy_parent
}

output "handson_folder_id" {
  description = "policy_scope = 'folder' 및 target_folder_id 미지정 시 자동 생성된 실습/검증 폴더 리소스명"
  value       = length(google_folder.handson_lab) > 0 ? google_folder.handson_lab[0].name : null
}

output "exemption_tag_values" {
  description = "목적별 독립 예외 태그 값 ID 및 namespaced_name 맵"
  value = {
    for k, v in google_tags_tag_value.exempt_true : k => {
      tag_key_id     = google_tags_tag_key.exempt[k].id
      tag_value_id   = v.id
      namespaced_ref = v.namespaced_name
    }
  }
}

output "env_folder_ids" {
  description = "생성된 표준 환경 폴더 ID 맵 (create_env_folders = true 설정 시)"
  value = {
    for k, f in google_folder.env : k => f.name
  }
}

output "policy_governance_summary" {
  description = "현재 설정된 적용 범위, DRS 허용 대상 및 선언적 예외 태그 요약"
  value = {
    policy_scope                    = var.policy_scope
    policy_parent                   = local.policy_parent
    drs_allowed_principal_sets      = local.drs_allowed_principal_sets
    declared_project_tag_exemptions = var.project_tag_exemptions
  }
}
