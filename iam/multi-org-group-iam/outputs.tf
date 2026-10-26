output "resolved_directory_customer_id" {
  description = "그룹 생성에 사용된 신규 조직의 Cloud Identity Directory Customer ID (C0xxxxxxx)"
  value       = local.effective_customer_id
}

output "created_groups" {
  description = "신규 조직(additional-domain.com)에 생성된 Cloud Identity 그룹 이메일 목록"
  value = {
    for k, g in google_cloud_identity_group.additional_org_groups :
    k => g.group_key[0].id
  }
}

output "sample_folder_id" {
  description = "생성된 샘플 하위 폴더 리소스 ID (create_sample_folder = false 인 경우 null)"
  value       = var.create_sample_folder ? google_folder.sample_app_folder[0].name : null
}
