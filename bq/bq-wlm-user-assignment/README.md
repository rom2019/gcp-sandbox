# BigQuery Reservation - Principal 기반 할당(Preview) 데모 환경

BigQuery 예약(Reservation) 할당에 **`principal` 속성**을 사용하여, 쿼리를 실행하는
**사용자/서비스 계정 단위**로 특정 예약에 라우팅하는 신규 기능(Preview)의 고객 데모용
Terraform 환경입니다.

> 참고 공식 문서: [워크로드 할당 관리 - BigQuery](https://docs.cloud.google.com/bigquery/docs/reservations-assignments?hl=ko)

---

## 1. 기능 개요

- BigQuery 예약 할당(Assignment)은 선택적 `principal` 속성을 지원합니다.
- 관리자는 작업을 실행하는 **사용자 또는 서비스 계정의 ID**를 기반으로 쿼리를
  특정 예약으로 라우팅할 수 있습니다.
- **동일한 할당 대상(assignee) 리소스 내에서** principal이 일치하는 할당이,
  principal이 설정되지 않은 일반 할당보다 **우선** 적용됩니다.
- 평가 순서 (프로젝트 → 폴더 → 조직):
  1. 리소스 계층 구조를 프로젝트 → 상위 폴더 → 조직 순으로 평가
  2. 각 계층 수준에서, 작업을 실행하는 principal과 일치하는 할당을 먼저 확인
  3. 일치하는 principal 할당이 없으면 같은 수준의 일반(principal 미설정) 할당을 확인
  4. 그래도 없으면 상위 계층으로 이동하여 반복
  - ⚠️ principal이 없는 **프로젝트 수준** 일반 할당이, principal이 있는
    **폴더 수준** 할당보다 우선합니다. (계층 구조 우선순위가 principal 매칭보다 상위)
- **Preview(GA 이전) 기능**입니다. 서비스별 약관의 'GA 이전 제품 또는 서비스 약관'이
  적용되며, 지원이 제한될 수 있습니다.
- 사용자별 할당의 **프로젝트당 기본 한도는 10개**입니다.

### 지원되는 principal 형식

| ID 유형             | 형식 |
|--------------------|------|
| Google 계정(사용자)   | `principal://goog/subject/{EMAIL_ADDRESS}` |
| 서비스 계정          | `principal://iam.googleapis.com/projects/-/serviceAccounts/{SA_EMAIL}` |
| 직원 ID 풀(Workforce Identity) ID | `principal://iam.googleapis.com/locations/global/workforcePools/{POOL_ID}/subject/{SUBJECT_ID}` |
| 워크로드 아이덴티티 풀 ID | `principal://iam.googleapis.com/projects/{PROJECT_NUMBER}/locations/global/workloadIdentityPools/{POOL_ID}/subject/{SUBJECT_ID}` |

> `unknown_or_deleted_user` 는 삭제/비활성화된 계정을 나타내는 예약된(sentinel) 값이며
> 할당에 사용할 수 없습니다.

---

## 2. Terraform 지원 여부 (중요)

| 기능 | Terraform 지원 여부 | 비고 |
|---|---|---|
| 예약(Reservation) 생성 | ✅ 지원 | `google_bigquery_reservation` |
| 일반 할당(project/folder/org, principal 없음) | ✅ 지원 | `google_bigquery_reservation_assignment` |
| **Principal 기반 할당** | ✅ **지원** (`principal` 필드) | 최근 Terraform Google Provider에 추가됨 (PR #28508). **반드시 이를 포함한 버전 이상**을 사용해야 하며, 오래된 provider에서는 `principal` 인수 자체가 인식되지 않습니다. 본 코드의 `versions.tf`에서 `>= 7.36.0` 이상을 요구하도록 설정했습니다. |
| `none` 할당(주문형 가격 책정) | ✅ 지원 | `reservation = ".../reservations/none"` |
| **프로젝트 한도(Project Limit) / 일정 정책 재정의**<br>(`scheduling_policy_max_slots`, `scheduling_policy_concurrency`) | ❌ **미지원** | 공식 문서에도 이 기능은 콘솔/SQL/bq 방법만 안내되어 있고 Terraform 예시가 없습니다. → `scripts/project_limit_override.sh` (bq CLI) 참고 |
| 쿼리별 예약 재정의 (`SET @@reservation`) | N/A (런타임 동작) | Terraform 대상 아님, SQL/bq/API에서 직접 수행 |

> Terraform provider 버전이 오래되어 `principal` 인수를 인식하지 못하는 경우
> (`Unsupported argument` 오류), `terraform init -upgrade` 로 provider를 최신화하세요.

---

## 3. 아키텍처

```
[관리 프로젝트 project_id]
   └── google_bigquery_reservation.demo (Enterprise, baseline 100 slots, autoscale +100)
          │
          ├── assignment: project_default   (principal 없음, 일반 라우팅)
          │      assignee = projects/{demo_project_id}
          │
          ├── assignment: vip_user           (principal = 특정 사용자)
          │      assignee = projects/{demo_project_id}
          │      principal://goog/subject/{vip_user_email}
          │
          └── assignment: vip_service_account (principal = 특정 서비스 계정)
                 assignee = projects/{demo_project_id}
                 principal://iam.googleapis.com/projects/-/serviceAccounts/{vip_service_account_email}
```

같은 `demo_project_id`에서 실행되는 쿼리는:
- `vip_user_email` 사용자가 실행 → `vip_user` 할당으로 라우팅 (전용 슬롯)
- `vip_service_account_email` 서비스 계정이 실행 → `vip_service_account` 할당으로 라우팅
- 그 외 사용자/서비스 계정이 실행 → `project_default` 일반 할당으로 라우팅

이 방식으로 예를 들어 "특정 BI 대시보드 서비스 계정만 별도 예약으로 격리", "VIP 분석가만
전용 슬롯 보장" 같은 시나리오를 시연할 수 있습니다.

---

## 4. 데모용 서비스 계정 및 필요 권한

`service_accounts.tf`에서 principal 할당 데모 대상이 될 서비스 계정을 새로 생성하고,
BigQuery 쿼리 실행에 필요한 최소한의 권한을 함께 부여합니다.

### 왜 이 권한이 필요한가

**예약(Reservation)에 대한 별도 접근 권한은 필요하지 않습니다.** principal 기반 할당
자체가 "이 principal이 실행하는 쿼리는 이 예약을 써라"는 라우팅 규칙이기 때문에,
서비스 계정이 예약 리소스에 직접 IAM 권한을 가질 필요는 없습니다.
대신 서비스 계정이 **애초에 BigQuery에서 쿼리를 실행할 수 있어야** 하므로 아래 권한이
필요합니다.

| 역할(Role) | 부여 대상 | 필수 여부 | 설명 |
|---|---|---|---|
| `roles/bigquery.jobUser` | 프로젝트(`demo_project_id`) | **필수** | Job(쿼리) 제출 권한. 이게 없으면 쿼리 자체가 거부됨 |
| `roles/bigquery.dataEditor` (쓰기 필요시) 또는 `roles/bigquery.dataViewer` (읽기 전용) | 프로젝트 또는 데이터셋 | **필수** | 실제 테이블/데이터셋 접근 권한 |
| `roles/bigquery.reservations.use` | 예약 또는 관리 프로젝트 | 선택 | `SET @@reservation`으로 **수동 재정의**할 때만 필요. 일반적인 principal 자동 라우팅에는 불필요 |

> 코드에서는 데모 편의를 위해 프로젝트 수준으로 `dataEditor`를 부여했습니다.
> 실제 고객 환경에서는 `service_accounts.tf`에 주석 처리된
> `google_bigquery_dataset_iam_member` 예시처럼 **데이터셋 수준으로 좁혀서**
> 최소 권한 원칙을 지키는 것을 권장하세요.

### 기존 서비스 계정을 재사용하고 싶다면

고객이 이미 운영 중인 서비스 계정(예: 실제 ETL 파이프라인 SA)으로 데모하고 싶다면:
1. `service_accounts.tf`의 `google_service_account.vip_etl` 리소스와 관련 IAM 바인딩을 제거
2. `data "google_service_account" "vip_etl"` 데이터 소스로 기존 계정을 조회하도록 변경
3. `main.tf`의 `vip_service_account` 할당에서 참조하는 이메일을 데이터 소스 참조로 교체

---

## 5. 사전 준비 사항

1. **권한**: 관리 프로젝트 및 할당 대상 리소스에 대해 아래 IAM 역할 중 하나 필요
   - `BigQuery Admin`, `BigQuery Resource Admin`, 또는 `BigQuery Resource Editor`
   - (권한 상세: `bigquery.reservationAssignments.create` 포함)
2. **API 활성화** (Terraform이 자동으로 활성화하지만 사전에 켜둬도 무방):
   - `bigqueryreservation.googleapis.com`
   - `cloudresourcemanager.googleapis.com`
   - `bigquery.googleapis.com`
3. **Terraform**: `>= 1.7.0`
4. **Google Provider**: `>= 7.36.0` (principal 필드를 지원하는 버전)
5. 인증: Application Default Credentials 설정
   ```bash
   gcloud auth application-default login
   ```

---

## 6. 사용 방법

```bash
# 1) 변수 파일 준비
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 를 실제 프로젝트/계정 값으로 수정

# 2) 초기화 (최신 provider 버전 사용)
terraform init -upgrade

# 3) 계획 확인
terraform plan

# 4) 적용
terraform apply
```

> ⚠️ 예약 할당 생성 후, 쿼리를 실행하기 전 **최소 5분 이상 대기**하세요.
> 그렇지 않으면 온디맨드(주문형) 가격 책정으로 쿼리가 청구될 수 있습니다.

### 정리(destroy)

```bash
terraform destroy
```

---

## 7. 시연/검증 방법

### 6.1 Terraform 리소스로 생성되지 않는 부분(bq CLI) 확인 및 보완

```bash
# 할당 목록 및 principal 매핑 확인
ADMIN_PROJECT_ID=<project_id> \
LOCATION=<reservation_location> \
RESERVATION_NAME=<reservation_name> \
TARGET_PROJECT_ID=<demo_project_id> \
./scripts/verify_assignments.sh
```

### 6.2 프로젝트 한도(Project Limit) 데모 (Terraform 미지원 기능)

```bash
ADMIN_PROJECT_ID=<project_id> \
LOCATION=<reservation_location> \
RESERVATION_NAME=<reservation_name> \
TARGET_PROJECT_ID=<demo_project_id> \
MAX_SLOTS=50 \
MAX_CONCURRENCY=5 \
./scripts/project_limit_override.sh
```
ADMIN_PROJECT_ID=agentspace-451402 \
LOCATION=us-central1 \
RESERVATION_NAME=demo-principal-assignment-reservation \
TARGET_PROJECT_ID=agentspace-451402 \
MAX_SLOTS=50 \
MAX_CONCURRENCY=5 \
./scripts/project_limit_override.sh
### 6.3 쿼리 라우팅 검증 (SQL)

`scripts/demo_queries.sql` 참고. 핵심 쿼리:

```sql
-- 최근 실행된 작업이 어떤 예약으로 라우팅되었는지 확인
SELECT job_id, user_email, reservation_id, creation_time
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{TARGET_PROJECT_ID}'
ORDER BY creation_time DESC
LIMIT 20;
```

### 6.4 실제 시연 시나리오 제안

1. `vip_user_email` 계정으로 로그인하여 `demo_project_id`에서 쿼리 실행
2. 다른(일반) 계정으로 동일 프로젝트에서 쿼리 실행
3. 위 6.3 쿼리로 두 작업의 `reservation_id`가 서로 다름을 보여줌
   → principal 할당이 있는 사용자는 전용 슬롯, 나머지는 일반 할당 슬롯 사용
4. (선택) `vip_service_account_email`을 사용하는 Scheduled Query / Dataform / Airflow
   작업을 실행해 서비스 계정 단위 라우팅도 함께 시연

---

## 8. 코드 구조

```
.
├── versions.tf                    # Terraform/Provider 버전 제약
├── apis.tf                        # 필요한 GCP API 활성화
├── variables.tf                   # 입력 변수
├── main.tf                        # 예약 + 일반/Principal 기반 할당 리소스
├── service_accounts.tf            # 데모용 서비스 계정 생성 + BigQuery IAM 권한 부여
├── outputs.tf                     # 출력값
├── terraform.tfvars.example       # 변수 값 예시
├── README.md
└── scripts/
    ├── verify_assignments.sh      # 할당 조회/검증 (bq CLI)
    ├── project_limit_override.sh  # 프로젝트 한도 설정 (Terraform 미지원 → bq CLI)
    └── demo_queries.sql           # 라우팅 검증용 SQL 모음
```

---

## 9. 참고 사항 및 주의점

- `principal` 옵션은 **Standard 버전 예약에서는 폴더/조직 할당이 지원되지 않는 것과 별개로**,
  프로젝트 수준 할당에는 사용 가능합니다. 다만 데모에서는 Enterprise 버전을 권장합니다.
- `assignee`와 예약은 **동일 조직, 동일 위치(location)**에 있어야 합니다.
- 할당이 생성된 후 할당 대상(사용자/프로젝트)이 다른 조직으로 이동하면 예약 모니터링이
  부정확해질 수 있습니다.
- 기존 실행 중인 작업(Job)은 할당이 변경/삭제되어도 원래 할당된 예약을 계속 사용합니다.
  (새 작업부터 변경 사항 적용)
- `unknown_or_deleted_user` 값으로는 할당을 생성할 수 없습니다.
- 이 기능은 Preview 단계이므로 실제 고객 환경 적용 전 반드시 GCP 공식 문서의 최신 상태와
  GA 여부를 재확인하세요. 기능/지원 문의: `bigquery-wlm-feedback@google.com`
