variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region (e.g. asia-northeast3)"
  type        = string
  default     = "asia-northeast3"
}

variable "domain_name" {
  description = "Custom domain name (e.g. docs.example.com)"
  type        = string
}

variable "bucket_name" {
  description = "Name of the GCS bucket. If empty, a domain_name-based name will be automatically generated."
  type        = string
  default     = ""
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for the backend bucket"
  type        = bool
  default     = true
}
