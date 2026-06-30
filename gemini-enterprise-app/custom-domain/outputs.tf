# ────────────────────────────────────────────────────────────────────
# Terraform 결과 출력 정의 (outputs.tf)
# ────────────────────────────────────────────────────────────────────

# 1. 예약된 전역 외부 IP 주소 출력
output "load_balancer_ip" {
  description = "전역 외부 애플리케이션 부하 분산기(LB)에 할당된 외부 IP 주소."
  value       = google_compute_global_address.external_ip.address
}

# 2. 커스텀 도메인 출력
output "custom_domain" {
  description = "Gemini Enterprise App 연결에 사용되는 커스텀 도메인 이름."
  value       = var.domain_name
}

# 3. SSL 인증서 ID 출력
output "ssl_certificate_id" {
  description = "부하 분산기에 적용된 SSL 인증서 리소스 ID."
  value       = var.ssl_cert_type == "managed" ? google_compute_managed_ssl_certificate.geapp_managed_cert[0].id : google_compute_ssl_certificate.geapp_self_signed_cert[0].id
}

# 4. DNS 설정 안내 메시지 출력
output "dns_configuration_instruction" {
  description = "도메인 DNS 관리 페이지에서 등록해야 하는 A 레코드 설정 안내."
  value       = <<EOF
===================================================================
📌 DNS A 레코드 설정 안내:
Gemini Enterprise App에 '${var.domain_name}' 도메인을 연결하려면
도메인 DNS 호스트(예: gomdol.cloud DNS 관리 페이지)에서 아래 A 레코드를 추가하세요.

  호스트 / 이름 : ${var.domain_name} (또는 sub-domain 'gemini')
  레코드 타입   : A
  IP 주소       : ${google_compute_global_address.external_ip.address}
  TTL           : 300 (또는 기본값)

참고: Google 관리형 SSL 인증서는 DNS A 레코드가 위 IP 주소로 정상
전파된 후 Google 내부에서 자동으로 발급/활성화됩니다 (약 15~30분 소요).
===================================================================
EOF
}
