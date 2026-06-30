# ────────────────────────────────────────────────────────────────────
# Terraform 입력 변수 정의 (variables.tf)
# ────────────────────────────────────────────────────────────────────

# 1. Google Cloud 프로젝트 ID
variable "project_id" {
  type        = string
  description = "인프라 리소스가 배포될 Google Cloud 프로젝트 ID (예: agentspace-451402)."
}

# 2. 기본 리전 설정
variable "region" {
  type        = string
  description = "GCP 리소스 기본 배치 리전 (예: us-central1)."
  default     = "us-central1"
}

# 3. 연결할 커스텀 도메인
variable "domain_name" {
  type        = string
  description = "Gemini Enterprise App에 연결할 고객 커스텀 도메인 (예: gemini.gomdol.cloud)."
  default     = "gemini.gomdol.cloud"
}

# 4. Gemini Enterprise App 백엔드 FQDN (도메인)
variable "backend_fqdn" {
  type        = string
  description = "Google 관리형 Gemini Enterprise App (Vertex AI Search / Agent Space) 엔드포인트 도메인."
  default     = "vertexaisearch.cloud.google.com"
}

# 5. 커스텀 도메인 경로별 URL 리디렉션 라우팅 규칙 목록
variable "routes" {
  type = list(object({
    prefix_match           = string                    # 요청 매칭 경로 (예: "/" 또는 "/drive-app")
    priority               = number                    # 라우팅 우순위 (낮은 숫자가 높은 우선순위)
    host_redirect          = string                    # 리디렉션 대상 호스트 (예: vertexaisearch.cloud.google.com)
    path_redirect          = string                    # 리디렉션 대상 URL 경로 (예: /home/cid/xxxx-xxxx)
    redirect_response_code = optional(string, "FOUND") # HTTP 리디렉션 응답 코드 (FOUND = 302, MOVED_PERMANENTLY_DEFAULT = 301)
  }))
  description = "커스텀 도메인 요청 경로를 Gemini Enterprise App 실제 서비스 URL로 매핑하는 리디렉션 규칙 목록."
  default = [
    {
      prefix_match           = "/"
      priority               = 1
      host_redirect          = "vertexaisearch.cloud.google.com"
      path_redirect          = "/"
      redirect_response_code = "FOUND"
    }
  ]
}

# 6. Google Cloud DNS 관리 여부
variable "enable_cloud_dns" {
  type        = bool
  description = "Google Cloud DNS를 통해 A 레코드를 자동 생성/관리할지 여부 (기본값: false)."
  default     = false
}

# 7. Cloud DNS 영역 이름 (enable_cloud_dns = true 일 때 사용)
variable "dns_zone_name" {
  type        = string
  description = "Cloud DNS Managed Zone 이름 (enable_cloud_dns가 true일 때 필수)."
  default     = "gomdol-cloud-zone"
}
