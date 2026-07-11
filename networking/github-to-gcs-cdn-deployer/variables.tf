variable "project_id" {
  description = "The GCP Project ID to deploy resources into."
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources."
  type        = string
  default     = "asia-northeast3"
}

variable "bucket_name" {
  description = "The name of the GCS bucket to create. Must be globally unique."
  type        = string
}

variable "github_repo" {
  description = "The GitHub repository in 'owner/repo' format (e.g., 'myuser/myrepo')."
  type        = string
}
