### Gemini Enterprise App Custom Domain Setup 

이 프로젝트는 **Gemini Enterprise App** 을 커스텀 도메인(예: `gemini.gomdol.cloud`)으로 접속할 수 있도록 Google Cloud Global External Application Load Balancer, Internet Network Endpoint Group, Google 관리형 SSL 인증서, HTTP(포트 80) -> HTTPS(포트 443) 리디렉션 및 URL 리디렉션 라우팅 규칙을 Terraform 코드로 자동 구성합니다.

---

#### 🔗 Related Links (관련 링크)
* [Google Cloud Codelab 가이드](https://codelabs.developers.google.com/agentspace-networking-customdomain-wif?hl=ko#3)
* [Google Slide 발표 자료](https://docs.google.com/presentation/d/1OtpC_bp9dfOaDF__snVEU1h49LTJGhkkGWMB27dnVFA/edit?resourcekey=0-o4nnC1LddMatXflTMgd-ug&slide=id.g3efff886865_0_2#slide=id.g3efff886865_0_2)

---

#### 🚀 배포 가이드

##### 1. 사전 요구사항
* [Terraform](https://developer.hashicorp.com/terraform/downloads) v1.5.0 이상 설치
* Google Cloud CLI (`gcloud`) 인증 완료
  ```bash
  gcloud auth application-default login
  ```

##### 2. 변수 설정 (`terraform.tfvars`)
`terraform.tfvars` 파일을 열고 본인의 GCP Project ID 및 Gemini App CID 경로를 설정합니다.

```hcl
project_id    = "REPLACE-ME"
region        = "REPLACE-ME"
domain_name   = "REPLACE-ME"
ssl_cert_type = "managed"

routes = [
  {
    prefix_match           = "/"
    priority               = 1
    host_redirect          = "vertexaisearch.cloud.google.com"
    path_redirect          = "/home/cid/YOUR_APP_CID"
    redirect_response_code = "FOUND"
  }
]
```

##### 3. 배포 실행

```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

---

#### 🌐 배포 후 DNS 등록 및 확인

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
   * `ex. http://gemini.gomdol.cloud` (80 포트) 접속 시 `ex. https://gemini.gomdol.cloud` 로 301 자동 리디렉션되는지 확인합니다.
   * 최종적으로 Gemini Enterprise App 으로 연결되는지 확인합니다.

---

#### 🧹 리소스 정리 (Teardown)

생성한 리소스를 모두 정리하려면 아래 명령어를 실행합니다.

```bash
terraform destroy
```
