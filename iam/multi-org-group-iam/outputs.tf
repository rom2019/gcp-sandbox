output "organization" {
  description = "자동 조회된 신규 조직 메타데이터 (domain, org_id, directory_customer_id)"
  type = object({
    domain                = string
    org_id                = string
    directory_customer_id = string
  })
  value = {
    domain                = var.additional_domain
    org_id                = data.google_organization.target.org_id
    directory_customer_id = data.google_organization.target.directory_customer_id
  }
}

output "groups" {
  description = "생성된 Cloud Identity 그룹 이메일 목록"
  type        = map(string)
  value       = { for k, g in google_cloud_identity_group.groups : k => g.group_key[0].id }
}

output "app_dev_folder_id" {
  description = "생성된 app-dev 하위 폴더 리소스 ID (예: folders/123456789012)"
  type        = string
  value       = google_folder.app_dev.name
}
