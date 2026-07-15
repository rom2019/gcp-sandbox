# GitHub Actions 및 Workload Identity Federation 기반 GCS & Cloud CDN 자동 배포

본 프로젝트는 서비스 계정 키(Service Account Key JSON) 없이 **Workload Identity Federation (WIF)**을 사용하여 GitHub Actions에서 Google Cloud Storage (GCS)로 정적 웹사이트를 안전하게 배포하고, Global HTTP Load Balancer 및 Cloud CDN 캐시를 자동으로 무효화하는 인프라 및 CI/CD 파이프라인을 구축합니다.

Language: [English](README-en.md) | [한국어](README.md)

---

## 🏗 아키텍처 개요

```mermaid
flowchart LR
    A[GitHub Actions Push] -->|1. OIDC 토큰 교환| B(GCP STS / WIF)
    B -->|2. 임시 Access Token 발급| A
    A -->|3. 정적 파일 동기화| C[(GCS 버킷)]
    A -->|4. CDN 캐시 무효화| D[Cloud CDN / 로드밸런서]
    E[최종 사용자] -->|HTTP 요청| D
    D -->|Cache Miss| C
```

### 주요 구성 요소:
- **Workload Identity Federation (WIF)**: 영구적인 서비스 계정 키 생성 없이 GitHub OIDC 토큰으로 GCP 인증 수행 (Keyless 인증).
- **서비스 계정 (`github-deployer`)**: 최소 권한 원칙에 따라 GCS 쓰기 권한(`roles/storage.objectAdmin`) 및 CDN 무효화 권한(`roles/compute.loadBalancerAdmin`)만 보유.
- **GCS 버킷**: 정적 웹 파일(`index.html`, `404.html`) 호스팅.
- **글로벌 외부 HTTP 로드밸런서 & Cloud CDN**: 전 세계 Edge 캐싱 제공, 빠른 웹사이트 전달 및 단일 외부 IP 제공.

---

## 📁 디렉터리 구조

```text
networking/github-to-gcs-cdn-deployer/
├── main.tf           # Terraform 리소스 (WIF, 서비스계정, GCS, CDN & 로드밸런서)
├── variables.tf      # 변수 정의
├── terraform.tfvars  # 배포 대상 GCP 프로젝트 및 GitHub 저장소 설정
├── outputs.tf        # 출력값 (로드밸런서 IP, WIF Provider ID, SA 이메일)
├── public/           # 정적 웹사이트 소스 파일 디렉터리
│   ├── index.html
│   └── 404.html
├── README.md         # 프로젝트 안내 문서 (한국어)
└── README-en.md      # 프로젝트 안내 문서 (영어)
```

---

## 🚀 배포 가이드

### 1단계: Terraform을 통한 GCP 인프라 구축

1. Terraform 디렉터리로 이동합니다:
   ```bash
   cd networking/github-to-gcs-cdn-deployer
   ```

2. `terraform.tfvars` 설정 파일을 본인의 환경에 맞게 수정합니다:
   ```hcl
   project_id  = "YOUR_GCP_PROJECT_ID"
   github_repo = "YOUR_GITHUB_ORGANIZATION/YOUR_REPO_NAME"
   bucket_name = "YOUR_UNIQUE_BUCKET_NAME"
   region      = "asia-northeast3"
   ```

3. Terraform 초기화 및 배포를 실행합니다:
   ```bash
   terraform init
   terraform apply
   ```

4. 출력된 결과값(Outputs)을 확인합니다:
   - `workload_identity_provider_name`
   - `service_account_email`
   - `load_balancer_ip`

---

### 2단계: GitHub Actions 워크플로우 구성

저장소 루트 디렉터리에 `.github/workflows/deploy-cdn.yml` 파일을 작성합니다:

```yaml
name: GCS 및 Cloud CDN 정적 웹사이트 자동 배포

on:
  push:
    branches:
      - main
    paths:
      - 'networking/github-to-gcs-cdn-deployer/public/**'
  workflow_dispatch:

permissions:
  contents: read
  id-token: write # WIF 인증에 필수 권한

jobs:
  deploy:
    name: GCS 업로드 및 Cloud CDN 캐시 무효화
    runs-on: ubuntu-latest
    steps:
      - name: 소스코드 체크아웃
        uses: actions/checkout@v4

      - name: Google Cloud 인증 (WIF)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'YOUR_WORKLOAD_IDENTITY_PROVIDER_NAME'
          service_account: 'YOUR_SERVICE_ACCOUNT_EMAIL'

      - name: GCS 버킷으로 정적 파일 업로드
        uses: google-github-actions/upload-cloud-storage@v2
        with:
          path: 'networking/github-to-gcs-cdn-deployer/public'
          destination: 'YOUR_GCS_BUCKET_NAME'
          parent: false

      - name: Cloud SDK 설정
        uses: google-github-actions/setup-gcloud@v2

      - name: Cloud CDN 캐시 전체 무효화
        run: |
          gcloud compute url-maps invalidate-cdn-cache website-url-map \
            --path="/*" \
            --async
```

---

### 3단계: 웹사이트 변경사항 배포 확인

`public/index.html` 등의 수정사항을 커밋 후 `main` 브랜치로 push합니다:

```bash
git add .
git commit -m "feat: Deploy static website via WIF"
git push origin main
```

---

## 🔒 보안 특장점 (Security Best Practices)

1. **키 없는 인증 (Keyless Authentication)**: GCP 서비스 계정 JSON 비대칭키를 발급하지 않으므로 키 유출 및 관리 위험 차단.
2. **엄격한 속성 조건 (`attribute_condition`)**: OIDC Provider 생성 시 `assertion.repository == "OWNER/REPO"` 조건을 필수 부여하여 지정된 GitHub 리포지토리의 토큰만 인증 허용 (스푸핑 방지).
3. **최소 권한 부여 (Least Privilege)**: 배포용 서비스 계정에 버킷 관리 및 CDN 무효화에 필요한 역할만 한정적으로 부여.

---

## 🔗 관련 링크 (Related Links)

- [Presentation Slide](https://docs.google.com/presentation/d/1vfKqzFKMFIhH9vhhXUMAg8upt1yDoZWbquCFHLiaQ00/edit?slide=id.p1#slide=id.p1)

