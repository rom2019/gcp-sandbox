# BigQuery Reservation - Principal 기반 할당 데모 환경

BigQuery 예약(Reservation) 할당에 **`principal` 속성**을 사용하여, 쿼리를 실행하는
**사용자/서비스 계정 단위**로 특정 예약에 라우팅하는 신규 기능의 고객 데모용
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


---
## 2. 아키텍처

```
[관리 프로젝트 project_id]
   ├── google_bigquery_reservation.demo (Enterprise, baseline 100 slots, autoscale +100)
   │      │
   │      ├── assignment: vip_user           (principal = 특정 사용자 vip_user_email)
   │      │      assignee = projects/{demo_project_id}
   │      │      reservation = demo-principal-assignment-reservation
   │      │
   │      └── assignment: vip_service_account (principal = 특정 서비스 계정 vip_service_account_email)
   │             assignee = projects/{demo_project_id}
   │             reservation = demo-principal-assignment-reservation
   │
   └── reservations/none (기본 주문형/On-Demand 할당)
          └── assignment: project_default   (principal 없음, 기본 라우팅)
                 assignee = projects/{demo_project_id}
                 reservation = "projects/.../reservations/none"
```

같은 `demo_project_id`에서 실행되는 쿼리는:
- **`vip_user_email` 사용자**가 실행 → `vip_user` 할당으로 라우팅 (**예약 슬롯 사용**, `reservation_id` = `...:US.demo-principal-assignment-reservation`)
- **`vip_service_account_email` 서비스 계정**이 실행 → `vip_service_account` 할당으로 라우팅 (**예약 슬롯 사용**, `reservation_id` = `...:US.demo-principal-assignment-reservation`)
- **그 외 일반 사용자**가 실행 → `project_default` 기본 할당으로 라우팅 (**주문형 요금제 적용**, `reservation_id` = `null`)

이 방식으로 **"특정 VIP 분석가 및 핵심 서비스 계정에만 예약 슬롯을 부여하고, 일반 사용자는 주문형(On-demand)으로 자동 분기"**하는 시나리오를 확실하게 시연할 수 있습니다.

---

## 3. 사전 준비 사항

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

## 4. 사용 방법

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

## 5. 시연 및 검증 방법

### 5.1 할당 조회 및 principal 매핑 확인 (bq CLI)

```bash
ADMIN_PROJECT_ID=<project_id> \
LOCATION=<reservation_location> \
RESERVATION_NAME=<reservation_name> \
TARGET_PROJECT_ID=<demo_project_id> \
./scripts/verify_assignments.sh
```

### 5.2 쿼리 라우팅 검증 (SQL)

`scripts/demo_queries.sql` 참고. 핵심 라우팅 확인 쿼리:

```sql
-- 최근 실행된 작업이 어떤 예약으로 라우팅되었는지 확인
SELECT job_id, user_email, reservation_id, creation_time
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{TARGET_PROJECT_ID}'
ORDER BY creation_time DESC
LIMIT 20;
```

### 5.3 실제 시연 시나리오 단계

1. **[VIP ETL 서비스 계정 시연]**: `vip_service_account_email`을 사용하여 `bq_wlm_demo.sample_orders` 테이블에 샘플 데이터 대량 적재 및 일별 요약(`daily_summary`) ETL 실행 (`scripts/demo_queries.sql` 1번 쿼리)
2. **[VIP 사용자 분석 쿼리 시연]**: `vip_user_email` 계정으로 로그인하여 데모 테이블 분석 쿼리 실행 (`scripts/demo_queries.sql` 2번 쿼리)
3. **[일반 사용자 분석 쿼리 시연]**: 다른(일반) 계정으로 동일한 분석 쿼리 실행
4. **[결과 대조 및 라우팅 검증]**: 위 5.2 쿼리(`INFORMATION_SCHEMA.JOBS_BY_PROJECT`)로 실행 주체별 `reservation_id`가 서로 다름을 대조 확인
   → VIP 사용자(`admin@...`) 및 서비스 계정은 **예약 슬롯(`demo-principal-assignment-reservation`)**, 일반 사용자(`test@...`)는 **주문형(`null`)**으로 분기됨

---

## 6. 코드 구조

```
.
├── versions.tf                    # Terraform/Provider 버전 제약
├── variables.tf                   # 입력 변수
├── main.tf                        # 예약 + 일반/Principal 기반 할당 리소스
├── dataset.tf                     # 데모용 Dataset 및 Table (sample_orders, daily_summary)
├── service_accounts.tf            # 데모용 서비스 계정 생성 + BigQuery IAM 권한 부여
├── outputs.tf                     # 출력값 (Reservation, Assignment, Dataset, Table ID 등)
├── terraform.tfvars.example       # 변수 값 예시
├── README.md
└── scripts/
    ├── verify_assignments.sh      # 할당 조회/검증 (bq CLI)
    └── demo_queries.sql           # 라우팅 검증용 SQL 모음 (샘플 적재, 분석, 결과 검증)
```

---

## 7. 참고 사항 및 주의점

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

