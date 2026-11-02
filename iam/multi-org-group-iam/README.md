# Multi-Org Cloud Identity Group & GCP IAM Automation (Single SSO Login)

단일 로그인 메인 도메인(`user@main-domain.com`)을 그대로 유지하면서, 신규 분리된 GCP Organization(`additional-domain.com`)의 **Cloud Identity 그룹 생성 · 외부 도메인 멤버 매핑 · GCP IAM 권한 바인딩**을 **Keyless Service Account Impersonation + 최신 Terraform (`>= 1.17.0`)** 으로 자동화하는 컨셉 데모 및 실습 가이드입니다.

---

## 1. 배경 및 아키텍처 개요

### 1.1 해결하려는 문제와 핵심 설계 원칙

자회사 분사, 신규 사업부 독립 등으로 별도 GCP Organization(`additional-domain.com`)을 추가 구축할 때 흔히 다음 요구사항이 충돌합니다.

- **단일 SSO 로그인 유지**: 전 임직원은 기존 IdP와 연동된 **`user@main-domain.com`** 계정 하나로만 Google Cloud에 로그인하고, 콘솔 상단 **Organization Switcher**에서 두 조직을 즉시 오갈 수 있어야 합니다.
- **수동 UI 운영 및 DRS 제약**: `@main-domain.com`은 신규 조직 기준 외부 도메인 계정이므로 콘솔 `IAM & Admin > Groups` UI에서 직접 그룹을 생성·편집할 수 없으며, 신규 조직의 DRS(Domain Restricted Sharing) 정책은 기본적으로 자기 도메인(`C02xxxxxx`) 주체만 허용합니다.

> [!IMPORTANT]
> **핵심 아키텍처 (Keyless SA Impersonation + DRS 무변경 격리)**
> 1. **100% 신규 조직 그룹 단위 IAM 바인딩**: 부트스트랩 SA 가장 권한(`Token Creator`)부터 조직·폴더·프로젝트 권한까지 모든 GCP IAM 주체를 **`group:gcp-*@additional-domain.com`** 으로 통일하고, **그룹 내부 멤버(`MEMBER`)** 만 `*@main-domain.com`으로 등록합니다.
> 2. **DRS 기본 격리 100% 유지**: IAM 바인딩 주체가 모두 `additional-domain.com`(`C02xxxxxx`) 소속 그룹이므로 신규 조직 DRS에 `main-domain.com`(`C01xxxxxx`)을 열 필요가 없으며, `@main-domain.com` 개인 계정 직접 바인딩 실수는 DRS가 서버 측에서 원천 차단합니다.
> 3. **State 미저장 Ephemeral 단기 토큰 & Keyless 운영**: `superadmin@additional-domain.com`은 최초 부트스트랩(Step 1~2) 1회 후 로그아웃하고, 일상 운영은 SA JSON 키 없이 Terraform `ephemeral "google_service_account_access_token"`(메모리 전용 단기 토큰)과 Impersonation으로만 수행합니다.

### 1.2 End-to-End 아키텍처 흐름

```mermaid
flowchart LR
    subgraph Zone1["Zone 1: 메인 로그인 도메인 (main-domain.com)"]
        User["일반 임직원 (SSO 로그인)\nuser@main-domain.com"]
        Admin["플랫폼 관리자 / CI 파이프라인\ncloud-admin@main-domain.com"]
    end

    subgraph Zone2["Zone 2: 신규 조직 부트스트랩 제어부 (additional-domain.com)"]
        OpGroup["부트스트랩 그룹\ngcp-tf-operators@additional-domain.com"]
        SA["Keyless Terraform SA\ntf-iam-admin (Seed 프로젝트)"]
        Policy["보안 정책 & Admin 위임\n- DRS: C02xxxxxx 단독 격리 유지\n- Admin Console: SA에 Groups Admin 할당"]
    end

    subgraph Zone3["Zone 3: 그룹 및 GCP 리소스 계층 (additional-domain.com)"]
        CIG["Cloud Identity 그룹\ngcp-*@additional-domain.com\n(allowExternalMembers = true)"]
        OrgIAM["GCP 계층별 IAM 바인딩\n- Org Root: Browser / Org Admin\n- Folder: 폴더 단위 조회 격리\n- Project: 지정 프로젝트 전담 Admin"]
    end

    Admin -->|"소속 멤버"| OpGroup
    OpGroup -->|"1. Token Creator 그룹 위임\n(1-hop SA Impersonation)"| SA
    Policy -.->|"C02 전용 DRS & 권한 제어"| SA
    SA -->|"2. 그룹 생성 & Ephemeral 토큰 기반\n외부 멤버 허용 PATCH"| CIG
    SA -->|"3. @main-domain.com 멤버(MEMBER) 등록"| CIG
    SA -->|"4. 100% 그룹 단위 IAM 바인딩"| OrgIAM
    OrgIAM -.->|"5. 콘솔 스위처에 2개 조직 동시 노출"| User
```

### 1.3 아키텍처 패턴 선택 가이드

| 비교 항목 | 패턴 A: 신규 조직 독립 그룹 *(본 에셋)* | 패턴 B: 메인 도메인 그룹 직접 바인딩 *(단순화 대안)* |
| :--- | :--- | :--- |
| **IAM 바인딩 주체** | `group:gcp-*@additional-domain.com` (멤버만 `*@main-domain.com`) | `group:*@main-domain.com`을 신규 조직 리소스에 직접 바인딩 |
| **신규 조직 DRS 정책** | **`C02xxxxxx` 단독 허용 유지** (`C01` 개인 계정 직접 바인딩 원천 차단) | DRS에 **`C01xxxxxx` 추가 허용 필수** (`C01` 개인 계정 직접 바인딩도 열림) |
| **그룹 소유 및 수명주기** | 신규 조직 Terraform SA가 독립 소유 (분사·매각 시 본사 의존성 없음) | 본사(`main-domain.com`) Google Workspace / IdP 관리팀에 종속 |
| **권장 시나리오** | 자회사 분사·규제 분리 조직, 본사 디렉터리 권한 없이 독립 IAM 운영 필요 시 | 두 조직이 영구적으로 동일 본사 거버넌스 아래 통합 관리되는 경우 |

---

## 2. 디렉터리 구조 및 샘플 그룹 매트릭스

```text
multi-org-group-iam/
├── README.md                        # 아키텍처 개요 및 Step-by-Step 환경 셋업 가이드
├── versions.tf                      # Terraform(>= 1.17.0) / Google Provider(~> 8.0), Keyless SA Impersonation 설정
├── variables.tf                     # 핵심 3개 환경 변수(도메인·SA), 그룹별 멤버 리스트 및 대상 프로젝트 ID 목록
├── main.tf                          # 서브모듈 호출 + Org / Folder / Project 단위 정적(Static) IAM 복붙 블록
├── outputs.tf                       # 명시적 타입(type) 계약이 적용된 조직 메타데이터, 그룹 이메일, 폴더 ID 출력
├── terraform.tfvars.example         # main-domain.com / additional-domain.com 기준 평면(Flat) 변수 템플릿
└── modules/
    └── external-group/              # 그룹 생성(SA 단독 Owner) + 외부 멤버 허용 PATCH + @main-domain 검증 서브모듈
        ├── versions.tf
        ├── variables.tf
        ├── main.tf
        └── outputs.tf
```

| 샘플 그룹 (`@additional-domain.com`) | 생성 방식 | 바인딩 범위 | GCP IAM 역할 | 소속 멤버 (`@main-domain.com`) 및 목적 |
| :--- | :--- | :--- | :--- | :--- |
| **`gcp-tf-operators@`** | Step 1~2 (1회) | `tf-iam-admin` SA | `roles/iam.serviceAccountTokenCreator` | IaC 실행 관리자 — DRS에 `C01`을 열지 않고 Keyless SA Impersonation 수행 |
| **`gcp-users@`** *(필수)* | Terraform | Org Root | `roles/browser` | 신규 조직 접근 전 임직원 — **콘솔 조직 스위처에 두 조직 동시 표시** 및 트리 탐색 |
| **`gcp-org-admins@`** | Terraform | Org Root | `roles/resourcemanager.organizationAdmin`<br>`roles/resourcemanager.folderAdmin`<br>`roles/resourcemanager.projectCreator` | 클라우드 플랫폼 관리팀 — 조직·폴더 계층 구조 및 프로젝트 생성 총괄 |
| **`gcp-app-devs@`** | Terraform | `app-dev` Folder | `roles/resourcemanager.folderViewer`<br>`roles/viewer` | 서비스 개발팀 — 담당 폴더 및 하위 프로젝트 리소스만 조회 격리 |
| **`gcp-prj-admins@`** | Terraform | 지정 Projects (`gcp_prj_admins_project_ids`) | `roles/editor`<br>`roles/resourcemanager.projectIamAdmin` | 특정 프로젝트 전담 관리자 — 지정된 워크로드 프로젝트들에 대해서만 리소스 편집 및 프로젝트 IAM 관리 권한 부여 |

> [!TIP]
> 타 팀 프로젝트 목록 노출까지 차단하고 **상단 Organization Switcher 노출만** 허용하려면 [`main.tf`](./main.tf)의 `gcp_users_browser` 리소스 `role`을 `"roles/resourcemanager.organizationViewer"`로 변경하세요.

---

## 3. Step-by-Step 환경 셋업 실습 가이드

### Step 0. 사전 준비

- **필수 로컬 도구**:
  - [Terraform](https://developer.hashicorp.com/terraform/downloads) **`v1.17.0` 이상** (최신 `v1.17.1` 권장, `hashicorp/google ~> 8.0`)
  - Google Cloud SDK (`gcloud` — 초기 부트스트랩 및 로컬 ADC 로그인용), `curl` (`terraform apply` 런타임에는 `terraform`과 `curl`만 사용되며 `python3` 불필요)
- **Before 상태 확인**: `cloud-admin@main-domain.com`으로 GCP Console에 로그인했을 때 상단 조직 드롭다운에 `main-domain.com`만 보이고 `additional-domain.com`은 표시되지 않는 것을 확인합니다.

---

### Step 1. 초기 부트스트랩 (1/2) — Seed 프로젝트, Keyless SA 및 운영자 그룹 생성

> [!NOTE]
> Step 1~2는 신규 조직 구축 시 최고 관리자(**`superadmin@additional-domain.com`**)로 **최초 1회만 수행**합니다.

```bash
# 1. Super Admin 로그인 및 식별자 확인
gcloud auth login superadmin@additional-domain.com
gcloud organizations list      # DISPLAY_NAME, ID(숫자형 ORG_ID), DIRECTORY_CUSTOMER_ID(C0...) 확인
gcloud billing accounts list   # 연결할 Billing Account ID 확인

# 2. 환경 변수 설정
export ADDITIONAL_DOMAIN="additional-domain.com"
export ADDITIONAL_ORG_ID="123456789012"
export ADDITIONAL_CUSTOMER_ID="C02xxxxxx"
export BILLING_ID="01XXXX-XXXXXX-XXXXXX"
export SEED_PROJECT_ID="iam-seed-prod-01"

# 3. Seed 프로젝트 생성, 빌링 연결 및 필수 API 5종 활성화
gcloud projects create "${SEED_PROJECT_ID}" --organization="${ADDITIONAL_ORG_ID}"
gcloud billing projects link "${SEED_PROJECT_ID}" --billing-account="${BILLING_ID}"
gcloud config set project "${SEED_PROJECT_ID}"

gcloud services enable \
  cloudidentity.googleapis.com \
  groupssettings.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="${SEED_PROJECT_ID}"

# 4. Keyless Terraform Service Account 생성 (JSON 키 발급 없음) 및 권한 부여
gcloud iam service-accounts create tf-iam-admin \
  --display-name="Terraform Group and IAM Automation SA" \
  --project="${SEED_PROJECT_ID}"

export TF_SA_EMAIL="tf-iam-admin@${SEED_PROJECT_ID}.iam.gserviceaccount.com"

for ROLE in \
  roles/resourcemanager.organizationAdmin \
  roles/resourcemanager.folderAdmin; do
  gcloud organizations add-iam-policy-binding "${ADDITIONAL_ORG_ID}" \
    --member="serviceAccount:${TF_SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None
done

gcloud projects add-iam-policy-binding "${SEED_PROJECT_ID}" \
  --member="serviceAccount:${TF_SA_EMAIL}" \
  --role="roles/serviceusage.serviceUsageConsumer"

# 5. 부트스트랩 운영자 그룹 생성 및 그룹 단위 SA Impersonation(Token Creator) 부여 (DRS 변경 불필요)
export TF_OPERATOR_GROUP="gcp-tf-operators@${ADDITIONAL_DOMAIN}"

gcloud identity groups create "${TF_OPERATOR_GROUP}" \
  --customer="${ADDITIONAL_CUSTOMER_ID}" \
  --display-name="GCP Terraform Operators" \
  --description="Bootstrap group allowed to impersonate tf-iam-admin Service Account" \
  --billing-project="${SEED_PROJECT_ID}"

# 신규 그룹 생성 직후 IAM 백엔드 전파 대기 ("Group not found" 방지)
sleep 20

gcloud iam service-accounts add-iam-policy-binding "${TF_SA_EMAIL}" \
  --member="group:${TF_OPERATOR_GROUP}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project="${SEED_PROJECT_ID}"
```

---

### Step 2. 초기 부트스트랩 (2/2) — Google Admin Console 1회 설정

`superadmin@additional-domain.com`으로 **`https://admin.google.com`** 에 접속하여 아래 3가지를 설정합니다.

1. **Terraform SA에 `Groups Admin` 할당 (Domain-Wide Delegation 불필요)**:
   - **Account > Admin roles > Groups Admin > Admins > Assign service accounts** 클릭 → `tf-iam-admin@iam-seed-prod-01.iam.gserviceaccount.com` 등록
2. **조직 내 그룹의 외부 멤버 허용 옵션 활성화**:
   - **Apps > Google Workspace > Groups for Business** (*OFF 상태면 `ON for everyone` 전환*) → **Sharing settings > Sharing options** → **`Allow group owners to add external members`** 체크 후 **Save**
3. **부트스트랩 그룹(`gcp-tf-operators`)에 외부 멤버 허용 및 운영자 등록**:
   - **Directory > Groups > `gcp-tf-operators@additional-domain.com`** 선택
   - **Access settings** → **`Allow external members`** **ON** 저장
   - **Members > Add members** → `cloud-admin@main-domain.com`을 **`Member`** 역할로 추가

설정을 마친 뒤 **1~5분간 IAM 전파를 대기**하고 `superadmin@additional-domain.com` 세션에서 로그아웃합니다.

---

### Step 3. 단일 로그인 계정(`cloud-admin@main-domain.com`) 전환 및 Terraform 배포

이제부터 모든 일상 운영은 메인 SSO 도메인 계정으로만 수행합니다.

```bash
# 1. 메인 도메인 관리자 계정으로 ADC 인증 전환
gcloud auth login cloud-admin@main-domain.com
gcloud auth application-default login

# 2. 변수 파일 생성 (필수 입력값은 additional_domain, main_login_domain, tf_service_account_email 단 3개!)
cp terraform.tfvars.example terraform.tfvars
```

[`terraform.tfvars.example`](./terraform.tfvars.example)을 참고해 값을 수정한 뒤 배포합니다 (`org_id`, `directory_customer_id`, `billing_project`는 코드에서 자동 해석됩니다):

```bash
terraform init
terraform plan
terraform apply
```

#### Terraform 내부 자동화 흐름 ([`main.tf`](./main.tf) & [`modules/external-group`](./modules/external-group))

```mermaid
sequenceDiagram
    participant Admin as Caller ADC (cloud-admin / Direct WIF)
    participant TF as Terraform (>= 1.17.0)
    participant IAMC as IAM Credentials API
    participant CI as Cloud Identity Groups API
    participant GS as Groups Settings API
    participant RM as GCP Resource Manager IAM

    Admin->>TF: terraform apply
    TF->>TF: 1. 서브모듈 입력 검증 (@main-domain.com 계정 및 Project ID 형식 확인)
    TF->>RM: 2. data.google_organization 조회 -> org_id & C02xxxxxx 자동 해석
    TF->>IAMC: 3. ephemeral.google_service_account_access_token (900s 메모리 토큰, State 미저장)
    TF->>CI: 4. modules/external-group -> gcp-*@additional-domain.com 그룹 생성 (SA 단독 Owner)
    TF->>GS: 5. PATCH allowExternalMembers="true" (curl 재시도 포함) & Org/Folder/Project IAM 병렬 바인딩
    TF->>CI: 6. @main-domain.com 임직원 멤버십(MEMBER) 등록
```

---

### Step 4. 배포 후 검증 체크리스트

1. **콘솔 2개 조직 동시 노출**: `user@main-domain.com` 브라우저에서 상단 Organization 드롭다운을 열면 `main-domain.com`과 `additional-domain.com`이 나란히 노출되어 재로그인 없이 즉시 전환됩니다 *(초기 반영까지 1~5분 소요 가능)*.
2. **그룹 단위 IAM 바인딩 확인**:
   - `additional-domain.com` > `app-dev` 폴더 및 `gcp_prj_admins_project_ids`에 지정한 프로젝트 IAM에 개인 계정(`user:`) 없이 `group:gcp-*@additional-domain.com`만 바인딩되어 있는지 확인합니다.
3. **비인가 외부 도메인(`@gmail.com`) 즉시 차단 테스트**:
   - `terraform.tfvars`의 아무 그룹 멤버 변수(예: `gcp_users_members`)에 `"unauthorized-user@gmail.com"`을 임시로 넣고 `terraform plan`을 실행하면, 서브모듈 검증 규칙에 의해 차단됩니다 (확인 후 원복).

```text
Error: Invalid value for variable

  on main.tf line 25, in module "gcp_users":
  25:   members           = var.gcp_users_members

보안 정책 위반: 모든 그룹 멤버는 허용된 메인 로그인 도메인(@main-domain.com) 계정이어야 합니다.

This was checked by the validation rule at
modules/external-group/variables.tf:37,3-13.
```

---

## 4. 확장 및 운영 참고 사항

1. **신규 그룹 및 IAM 권한 확장 (Static Copy & Paste)**:
   - 반복되는 그룹 생성·외부 멤버 허용 `PATCH`·도메인 검증은 [`modules/external-group`](./modules/external-group)에 캡슐화되어 있고, 루트 [`main.tf`](./main.tf)는 중첩 `locals` 루프 없이 **정적 블록 나열 방식**으로 구성되어 있습니다.
   - 신규 팀·폴더·프로젝트 그룹이 필요하면 `main.tf`에서 `module "..."` 블록과 `google_organization_iam_member` / `google_folder_iam_member` / `google_project_iam_member` 블록을 그대로 복사·붙여넣기한 뒤 `terraform init && terraform apply`를 실행하세요.
2. **원격 GCS State 백엔드 & CI/CD 연동**:
   - 협업 및 지속 운영 시 Seed 프로젝트 내 GCS 버킷을 생성하고 [`versions.tf`](./versions.tf)의 `backend "gcs"` 주석을 해제해 원격 State를 사용하세요.
   - GitHub Actions / Cloud Build 연동 시에는 Workload Identity Federation(WIF) 주체에 `tf-iam-admin` SA의 `roles/iam.serviceAccountTokenCreator`를 부여하면 `gcloud` CLI 없이도 동일하게 동작합니다.

---

## 5. 리소스 정리 (Teardown)

```bash
# 1. Terraform 관리 리소스 일괄 삭제 (cloud-admin@main-domain.com 인증 상태)
terraform destroy

# 2. 초기 부트스트랩 리소스까지 완전히 정리할 경우 Super Admin으로 전환
gcloud auth login superadmin@additional-domain.com

export ADDITIONAL_DOMAIN="additional-domain.com"
export ADDITIONAL_ORG_ID="123456789012"
export SEED_PROJECT_ID="iam-seed-prod-01"
export TF_SA_EMAIL="tf-iam-admin@${SEED_PROJECT_ID}.iam.gserviceaccount.com"
export TF_OPERATOR_GROUP="gcp-tf-operators@${ADDITIONAL_DOMAIN}"

gcloud identity groups delete "${TF_OPERATOR_GROUP}" --billing-project="${SEED_PROJECT_ID}" --quiet

for ROLE in \
  roles/resourcemanager.organizationAdmin \
  roles/resourcemanager.folderAdmin; do
  gcloud organizations remove-iam-policy-binding "${ADDITIONAL_ORG_ID}" \
    --member="serviceAccount:${TF_SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None
done

gcloud projects delete "${SEED_PROJECT_ID}" --quiet
```

마지막으로 `https://admin.google.com` > `Account > Admin roles > Groups Admin > Admins`에서 삭제된 `tf-iam-admin` SA 할당을 해제합니다.

---

## 6. 트러블슈팅 요약

| 증상 / 주요 에러 메시지 | 원인 | 해결 방법 |
| :--- | :--- | :--- |
| `Error: Organization not found: <domain>` | `additional_domain` 오타 또는 `tf-iam-admin` SA에 조직 조회 권한 미전파 | 도메인명 확인 및 Step 1의 `organizationAdmin` 부여 후 1~2분 뒤 재실행 |
| `Error generating access token ... 403` (`iam.serviceAccounts.getAccessToken` denied) | 호출 계정이 `gcp-tf-operators@` 그룹 멤버가 아니거나 IAM 전파 지연 | Step 2-3의 외부 멤버 허용 ON 및 `Member` 등록 확인 후 1~5분 대기 |
| `Error 403 ... USER_PROJECT_DENIED` | `tf-iam-admin` SA에 Seed 프로젝트 쿼터 권한 누락 | Step 1의 Seed 프로젝트 `roles/serviceusage.serviceUsageConsumer` 바인딩 확인 |
| `Groups Settings API` `PATCH` 시 `HTTP 403/404` (`Not Authorized...` 본문 출력) | Admin Console `Groups Admin` 미할당, 외부 멤버 옵션 미체크 또는 전파 지연 | Step 2-1, 2-2 설정 확인 후 1~5분 전파 대기 뒤 `terraform apply` 재실행 |
| 콘솔 드롭다운에 신규 조직이 바로 안 보임 | 그룹 멤버십 → GCP IAM 캐시 전파 지연(1~5분) 또는 `gcp-users` 누락 | 1~5분 대기 후 브라우저 강력 새로고침(`Ctrl+Shift+R` / `Cmd+Shift+R`) |
