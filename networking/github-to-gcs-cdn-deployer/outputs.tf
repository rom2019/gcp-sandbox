output "load_balancer_ip" {
  description = "The IP address of the Load Balancer. Point your domain DNS here."
  value       = google_compute_global_address.default.address
}

output "gcs_bucket_url" {
  description = "The website URL of the GCS bucket."
  value       = "http://${google_storage_bucket.website.name}.storage.googleapis.com"
}

output "workload_identity_provider_name" {
  description = "The Workload Identity Provider name to use in GitHub Actions."
  value       = google_iam_workload_identity_pool_provider.provider.name
}

output "service_account_email" {
  description = "The Service Account email to use in GitHub Actions."
  value       = google_service_account.sa.email
}
