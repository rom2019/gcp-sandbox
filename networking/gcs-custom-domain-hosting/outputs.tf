output "external_ip" {
  description = "The external Global IP address assigned to the Load Balancer. Point your DNS A record to this IP."
  value       = google_compute_global_address.default.address
}

output "bucket_name" {
  description = "The name of the Cloud Storage Bucket created for hosting static content"
  value       = google_storage_bucket.website.name
}

output "ssl_certificate_id" {
  description = "The ID of the Managed SSL Certificate"
  value       = google_compute_managed_ssl_certificate.default.id
}

output "dns_instruction" {
  description = "Instructions for DNS record setup"
  value       = "Create an DNS 'A' Record pointing '${var.domain_name}' to IP '${google_compute_global_address.default.address}'"
}
