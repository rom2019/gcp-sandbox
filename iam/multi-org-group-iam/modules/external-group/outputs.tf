output "id" {
  description = "생성된 Cloud Identity 그룹 리소스 ID (예: groups/01abc...)"
  type        = string
  value       = google_cloud_identity_group.this.id
}

output "email" {
  description = "생성된 Cloud Identity 그룹 이메일 주소"
  type        = string
  value       = google_cloud_identity_group.this.group_key[0].id
}

output "iam_member" {
  description = "GCP IAM 리소스 바인딩에 바로 사용할 주체 문자열 (group:<email>)"
  type        = string
  value       = "group:${google_cloud_identity_group.this.group_key[0].id}"
}
