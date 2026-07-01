# 1. Reserved Global External IPv4 Address
resource "google_compute_global_address" "default" {
  name = "${local.actual_bucket_name}-ip"
}

# 2. Google-Managed SSL Certificate for Custom Domain
resource "google_compute_managed_ssl_certificate" "default" {
  name = "${local.actual_bucket_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }
}

# 3. Backend Bucket with Cloud CDN
resource "google_compute_backend_bucket" "default" {
  name        = "${local.actual_bucket_name}-backend"
  description = "Backend storage bucket for ${var.domain_name}"
  bucket_name = google_storage_bucket.website.name
  enable_cdn  = var.enable_cdn
}

# 4. URL Map for HTTPS Traffic
resource "google_compute_url_map" "https" {
  name            = "${local.actual_bucket_name}-url-map"
  default_service = google_compute_backend_bucket.default.id
}

# 5. Target HTTPS Proxy
resource "google_compute_target_https_proxy" "default" {
  name             = "${local.actual_bucket_name}-https-proxy"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# 6. Global Forwarding Rule for HTTPS (Port 443)
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${local.actual_bucket_name}-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}
