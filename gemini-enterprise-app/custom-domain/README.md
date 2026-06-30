# Gemini Enterprise App Custom Domain Setup

이 프로젝트는 **Gemini Enterprise App** 을 커스텀 도메인(예: `gemini.gomdol.cloud`)으로 접속할 수 있도록 Google Cloud Global External Application Load Balancer, Internet Network Endpoint Group, Google 관리형 SSL 인증서, HTTP(포트 80) -> HTTPS(포트 443) 리디렉션 및 URL 리디렉션 라우팅 규칙을 Terraform 코드로 자동 구성합니다.

---

## Architecture

```
                        ┌─────────────────────────────────────────────────────────┐
                        │                   Google Cloud Project                  │
                        │                                                         │
  User Browser          │  ┌──────────────────────────────────────────────────┐  │
      │                 │  │       Global External Application Load Balancer   │  │
      │  DNS A Record   │  │                                                   │  │
      ▼                 │  │  ┌─────────────┐      ┌────────────────────────┐ │  │
 ┌──────────────┐       │  │  │ Forwarding  │      │   Target HTTP Proxy    │ │  │
 │  Custom      │       │  │  │ Rule (80)   │─────▶│  (HTTP→HTTPS 301)     │ │  │
 │  Domain      │       │  │  └─────────────┘      └────────────────────────┘ │  │
 │  gemini.     │──────▶│  │                                                   │  │
 │  gomdol.     │       │  │  ┌─────────────┐      ┌────────────────────────┐ │  │
 │  cloud       │       │  │  │ Forwarding  │      │   Target HTTPS Proxy   │ │  │
 └──────────────┘       │  │  │ Rule (443)  │─────▶│  + Managed SSL Cert   │ │  │
      │                 │  │  └─────────────┘      └───────────┬────────────┘ │  │
      │                 │  │                                    │              │  │
      │                 │  │                        ┌───────────▼────────────┐ │  │
      │                 │  │                        │       URL Map          │ │  │
      │                 │  │                        │  Route Rules           │ │  │
      │                 │  │                        │  (prefix_match → 302   │ │  │
      │                 │  │                        │   URL Redirect)        │ │  │
      │                 │  │                        └───────────┬────────────┘ │  │
      │                 │  │                                    │              │  │
      │                 │  │                        ┌───────────▼────────────┐ │  │
      │                 │  │                        │   Backend Service      │ │  │
      │                 │  │                        │ + Internet NEG         │ │  │
      │                 │  │                        │ (INTERNET_FQDN_PORT)   │ │  │
      │                 │  │                        └────────────────────────┘ │  │
      │                 │  └──────────────────────────────────────────────────┘  │
      │                 └─────────────────────────────────────────────────────────┘
      │
      │  302 Redirect
      ▼
┌─────────────────────────────────┐
│  Gemini Enterprise App          │
│  vertexaisearch.cloud.google.com│
│  (Google Identity 인증 포함)    │
└─────────────────────────────────┘
```

### 트래픽 흐름

| 단계 | 설명 |
|------|------|
| **1. DNS 조회** | `gemini.gomdol.cloud` → Load Balancer 외부 고정 IP (A 레코드) |
| **2. HTTP (포트 80)** | Target HTTP Proxy가 301로 HTTPS 영구 리디렉션 |
| **3. HTTPS (포트 443)** | Google 관리형 SSL 인증서로 TLS 종료 |
| **4. URL Map** | 경로(`prefix_match`) 기반으로 302 리디렉션 규칙 적용 |
| **5. 최종 리디렉션** | 브라우저가 `vertexaisearch.cloud.google.com`으로 이동, Google Identity 인증 수행 |

---

## 🔗 Related Links (관련 링크)
* [Google Cloud Codelab 가이드](https://codelabs.developers.google.com/agentspace-networking-customdomain-wif?hl=ko#3)
* [Google Slide 발표 자료](https://docs.google.com/presentation/d/1OtpC_bp9dfOaDF__snVEU1h49LTJGhkkGWMB27dnVFA/edit?resourcekey=0-o4nnC1LddMatXflTMgd-ug&slide=id.g3efff886865_0_2#slide=id.g3efff886865_0_2)

---

## 🚀 배포 가이드

### 1. 사전 요구사항
* [Terraform](https://developer.hashicorp.com/terraform/downloads) v1.5.0 이상 설치
* Google Cloud CLI (`gcloud`) 인증 완료
  ```bash
  gcloud auth application-default login --billing-project=YOUR_PROJECT_ID
  ```
* `cloudresourcemanager.googleapis.com` API 수동 사전 활성화 (Terraform bootstrap 필수)
  ```bash
  gcloud services enable cloudresourcemanager.googleapis.com --project=YOUR_PROJECT_ID
  ```

### 2. 변수 설정 (`terraform.tfvars`)
`terraform.tfvars.example`을 복사하여 본인의 GCP Project ID 및 Gemini App CID 경로를 설정합니다.

```bash
cp terraform.tfvars.example terraform.tfvars
```

```hcl
project_id  = "YOUR_PROJECT_ID"
domain_name = "YOUR_CUSTOM_DOMAIN"

routes = [
  {
    prefix_match           = "/"
    priority               = 1
    host_redirect          = "vertexaisearch.cloud.google.com"
    path_redirect          = "/us/home/cid/YOUR_APP_CID"
    redirect_response_code = "FOUND"
  }
]
```

### 3. 배포 실행

```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

---

## 🌐 배포 후 DNS 등록 및 확인

1. **DNS A 레코드 추가**:
   `terraform apply` 완료 후 출력되는 `load_balancer_ip` 값을 확인하여 DNS 호스트에(예: `gomdol.cloud`) A 레코드를 추가합니다.
   * **Name / Host**: `gemini` (또는 `gemini.gomdol.cloud`)
   * **Record Type**: `A`
   * **Target IP**: `<load_balancer_ip>`
   * **TTL**: `300`

2. **Google 관리형 SSL 인증서 활성화 확인**:
   DNS A 레코드가 인프라 IP로 정상 전파되면 Google에서 SSL 인증서를 자동 발급합니다 (약 15~30분 소요).
   ```bash
   gcloud compute ssl-certificates describe geapp-managed-cert --global
   ```

3. **접속 테스트**:
   * `http://gemini.gomdol.cloud` (80 포트) 접속 시 `https://gemini.gomdol.cloud` 로 301 자동 리디렉션되는지 확인합니다.
   * 최종적으로 Gemini Enterprise App 으로 연결되는지 확인합니다.

---

## 🧹 리소스 정리 (Teardown)

생성한 리소스를 모두 정리하려면 아래 명령어를 실행합니다.

```bash
terraform destroy
```
