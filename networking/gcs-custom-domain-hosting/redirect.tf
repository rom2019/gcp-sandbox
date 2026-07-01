# 1. URL Map for HTTP to HTTPS Redirect
resource "google_compute_url_map" "http_redirect" {
  name = "${local.actual_bucket_name}-http-redirect-url-map"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# 2. Target HTTP Proxy for Redirect
resource "google_compute_target_http_proxy" "http_redirect" {
  name    = "${local.actual_bucket_name}-http-redirect-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

# 3. Global Forwarding Rule for HTTP (Port 80)
resource "google_compute_global_forwarding_rule" "http_redirect" {
  name                  = "${local.actual_bucket_name}-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect.id
  ip_address            = google_compute_global_address.default.id
}
