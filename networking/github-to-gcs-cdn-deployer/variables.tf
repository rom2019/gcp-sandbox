variable "project_id" {
  description = "리소스가 배포될 GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "리전 리소스가 생성될 GCP 리전"
  type        = string
  default     = "asia-northeast3"
}

variable "bucket_name" {
  description = "생성할 GCS 버킷 이름 (전역적으로 유일해야 함)"
  type        = string
}

variable "github_repo" {
  description = "GitHub 리포지토리 이름 ('owner/repo' 형식)"
  type        = string
}

