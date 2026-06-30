# ────────────────────────────────────────────────────────────────────
# 1. 필수 Google Cloud API 서비스 활성화
# ────────────────────────────────────────────────────────────────────
# GCP 프로젝트에서 인프라 구성에 필요한 필수 API 목록을 정의하고 활성화합니다.
locals {
  required_apis = compact([
    "compute.googleapis.com",    # Compute Engine & Load Balancer API
    "orgpolicy.googleapis.com",  # Organization Policy API (조직 정책 제약 해제용)
    var.enable_cloud_dns ? "dns.googleapis.com" : null, # Cloud DNS API (선택사항)
  ])
}

# 루프(for_each)를 사용하여 필요한 GCP API 서비스를 일괄 활성화합니다.
resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false # terraform destroy 시 API 자체는 비활성화하지 않음
}

# ────────────────────────────────────────────────────────────────────
# 2. 조직 정책 (Organization Policy) 해제
# ────────────────────────────────────────────────────────────────────
# 인터넷 NEG(Internet Network Endpoint Group) 생성을 차단하는 조직 정책 제약을 프로젝트 수준에서 해제합니다.
resource "google_project_organization_policy" "disable_internet_neg" {
  project    = var.project_id
  constraint = "constraints/compute.disableInternetNetworkEndpointGroup"

  boolean_policy {
    enforced = false # INEG 생성 허용 (제약 조건 비활성화)
  }

  depends_on = [google_project_service.apis]
}

# 로드밸런서 타입 생성 제한(restrictLoadBalancerCreationForTypes) 해제
resource "google_project_organization_policy" "allow_lb_types" {
  project    = var.project_id
  constraint = "constraints/compute.restrictLoadBalancerCreationForTypes"

  list_policy {
    allow {
      all = true # 모든 타입의 로드밸런서 생성 허용
    }
  }

  depends_on = [google_project_service.apis]
}

# 조직 정책 변경 사항이 GCP Compute Engine API 전파 캐시에 반영되도록 60초간 대기합니다.
resource "time_sleep" "wait_for_org_policy" {
  create_duration = "60s"

  triggers = {
    allow_lb_types       = google_project_organization_policy.allow_lb_types.id
    disable_internet_neg = google_project_organization_policy.disable_internet_neg.id
  }

  depends_on = [
    google_project_organization_policy.disable_internet_neg,
    google_project_organization_policy.allow_lb_types
  ]
}

# ────────────────────────────────────────────────────────────────────
# 3. 전역 고정 외부 IP 주소 예약 (Global External IP)
# ────────────────────────────────────────────────────────────────────
# 외부 애플리케이션 부하 분산기(LB)가 수신할 전역 IPv4 고정 IP 주소를 예약합니다.
resource "google_compute_global_address" "external_ip" {
  name       = "geapp-external-ip"
  project    = var.project_id
  ip_version = "IPV4"

  depends_on = [google_project_service.apis]
}

# ────────────────────────────────────────────────────────────────────
# 4. 인터넷 NEG (Global Internet Network Endpoint Group) 및 엔드포인트
# ────────────────────────────────────────────────────────────────────
# Google 관리형 Gemini Enterprise App (Vertex AI Search) 백엔드 FQDN 연결용 인터넷 NEG 생성
resource "google_compute_global_network_endpoint_group" "geapp_ineg" {
  name                  = "geapp-ineg"
  project               = var.project_id
  network_endpoint_type = "INTERNET_FQDN_PORT" # 도메인 기반 외부 백엔드 타입
  default_port          = 443

  depends_on = [
    google_project_service.apis,
    google_project_organization_policy.disable_internet_neg,
    time_sleep.wait_for_org_policy
  ]
}

# 인터넷 NEG에 Gemini Enterprise App FQDN (vertexaisearch.cloud.google.com:443) 엔드포인트 등록
resource "google_compute_global_network_endpoint" "geapp_endpoint" {
  global_network_endpoint_group = google_compute_global_network_endpoint_group.geapp_ineg.name
  project                       = var.project_id
  fqdn                          = var.backend_fqdn
  port                          = 443
}

# ────────────────────────────────────────────────────────────────────
# 5. 전역 백엔드 서비스 (Global Backend Service)
# ────────────────────────────────────────────────────────────────────
# 부하 분산기와 인터넷 NEG 백엔드를 연결하는 전역 HTTPS 백엔드 서비스
resource "google_compute_backend_service" "geapp_bes" {
  name                  = "geapp-ineg-bes"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED" # 최신 외부 관리형 애플리케이션 부하 분산기
  protocol              = "HTTPS"
  port_name             = "https"

  backend {
    group = google_compute_global_network_endpoint_group.geapp_ineg.id
  }
}

# ────────────────────────────────────────────────────────────────────
# 6. SSL 인증서 구성 (Google 관리형 인증서 또는 자체 서명 인증서)
# ────────────────────────────────────────────────────────────────────
# 옵션 1: Google 관리형 무료 SSL 인증서 (권장 - DNS A 레코드 전파 후 자동 갱신/발급)
resource "google_compute_managed_ssl_certificate" "geapp_managed_cert" {
  count   = var.ssl_cert_type == "managed" ? 1 : 0
  name    = "geapp-managed-cert"
  project = var.project_id

  managed {
    domains = [var.domain_name]
  }
}

# 옵션 2: 개발/테스트용 자체 서명 인증서 (ssl_cert_type = "self_signed" 일 때)
resource "tls_private_key" "self_signed" {
  count     = var.ssl_cert_type == "self_signed" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count           = var.ssl_cert_type == "self_signed" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Gemini Enterprise App"
  }

  dns_names = [var.domain_name]

  validity_period_hours = 8760 # 유효기간: 1년

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_compute_ssl_certificate" "geapp_self_signed_cert" {
  count       = var.ssl_cert_type == "self_signed" ? 1 : 0
  name        = "geapp-self-signed-cert"
  project     = var.project_id
  private_key = tls_private_key.self_signed[0].private_key_pem
  certificate = tls_self_signed_cert.self_signed[0].cert_pem
}

# ────────────────────────────────────────────────────────────────────
# 7. HTTPS URL Map (호스트 및 경로 규칙 기반 URL 리디렉션)
# ────────────────────────────────────────────────────────────────────
# 커스텀 도메인(gemini.gomdol.cloud)으로 들어오는 요청을 Gemini Enterprise App 실제 URL로 리디렉션하는 URL Map
resource "google_compute_url_map" "geapp_lb" {
  name            = "geapp-lb"
  project         = var.project_id
  default_service = google_compute_backend_service.geapp_bes.id

  # 커스텀 도메인 호스트 규칙 설정
  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "geapp-matcher"
  }

  # 경로 매처 및 URL 리디렉션(UrlRedirect) 동적 규칙 구성
  path_matcher {
    name            = "geapp-matcher"
    default_service = google_compute_backend_service.geapp_bes.id

    dynamic "route_rules" {
      for_each = var.routes
      content {
        priority = route_rules.value.priority

        match_rules {
          prefix_match = route_rules.value.prefix_match
        }

        # Gemini App 실제 URL 경로 및 호스트로 HTTP 리디렉션
        url_redirect {
          host_redirect          = route_rules.value.host_redirect
          path_redirect          = route_rules.value.path_redirect
          redirect_response_code = route_rules.value.redirect_response_code
          strip_query            = false
        }
      }
    }
  }
}

# ────────────────────────────────────────────────────────────────────
# 8. Target HTTPS Proxy
# ────────────────────────────────────────────────────────────────────
# SSL 인증서와 HTTPS URL Map을 연결하는 전역 HTTPS 대상 프록시
resource "google_compute_target_https_proxy" "https_proxy" {
  name    = "geapp-https-proxy"
  project = var.project_id
  url_map = google_compute_url_map.geapp_lb.id

  ssl_certificates = var.ssl_cert_type == "managed" ? [
    google_compute_managed_ssl_certificate.geapp_managed_cert[0].id
  ] : [
    google_compute_ssl_certificate.geapp_self_signed_cert[0].id
  ]
}


# ────────────────────────────────────────────────────────────────────
# 9. HTTPS (포트 443) 전역 포워딩 규칙 (Global Forwarding Rule)
# ────────────────────────────────────────────────────────────────────
# 예약된 외부 고정 IP의 443 포트로 들어오는 트래픽을 Target HTTPS Proxy로 전달합니다.
resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  name                  = "geapp-fr"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.external_ip.id
  target                = google_compute_target_https_proxy.https_proxy.id
  port_range            = "443"

  depends_on = [time_sleep.wait_for_org_policy]
}

# ────────────────────────────────────────────────────────────────────
# 10. HTTP (포트 80) -> HTTPS (포트 443) 자동 리디렉션
# ────────────────────────────────────────────────────────────────────
# HTTP (포트 80) 요청을 HTTPS (포트 443)로 301 Permanent Redirect하는 URL Map
resource "google_compute_url_map" "http_redirect" {
  name    = "geapp-http-redirect-map"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true                       # HTTPS로 자동으로 리디렉션
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT" # 301 Redirect
    strip_query            = false
  }
}

# Target HTTP Proxy (80 포트 리디렉션용)
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "geapp-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.http_redirect.id
}

# HTTP (포트 80) 전역 포워딩 규칙
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name                  = "geapp-http-fr"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.external_ip.id
  target                = google_compute_target_http_proxy.http_proxy.id
  port_range            = "80"

  depends_on = [time_sleep.wait_for_org_policy]
}

# ────────────────────────────────────────────────────────────────────
# 11. Cloud DNS A 레코드 (선택사항: enable_cloud_dns = true 일 때)
# ────────────────────────────────────────────────────────────────────
resource "google_dns_record_set" "a_record" {
  count        = var.enable_cloud_dns ? 1 : 0
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.external_ip.address]
  depends_on   = [google_project_service.apis]
}
