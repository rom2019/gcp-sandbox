# BigQuery Reservation - User Assignment 한도 확장(10 → 100) 검증

본 Terraform 환경은 BigQuery Reservation의 **User Assignment(Principal 기반 할당) 최대 생성 개수가 기존 기본 10개에서 100개로 상향(확장)** 됨에 따라, **Google Cloud 전 지역(Multi-region 및 개별 리전 35개 이상)에 해당 한도 확장이 정상 적용되었는지 테스트 및 검증하기 위한 목적으로 생성된 코드입니다.**

> 참고 공식 문서: [워크로드 할당 관리 - BigQuery](https://docs.cloud.google.com/bigquery/docs/reservations-assignments?hl=ko)

---

## 1. 개요 및 테스트 목적

- **기존 한도**: BigQuery 예약의 사용자별(`principal`) 할당은 프로젝트당 **기본 10개로 제한**되어 있었습니다.
- **확장된 한도**: 사용자 할당의 최대 개수가 기본 10개에서 **최대 100개로 대폭 상향**되었습니다.
- **테스트 목적**:
  1. 전 세계 BigQuery 지원 리전(US, EU, APAC, EMEA 등 35개 이상 리전) 전체에 걸쳐 한도 확장이 누락 없이 배포되었는지 검증
  2. 리전당 10개 이상의 Principal 할당(최대 100개 이상)을 프로비저닝하여 할당 초과 오류(Quota/Limit Exceeded) 없이 정상 생성되는지 확인
  3. 일괄 생성된 Principal 할당이 각 리전의 예약에 정확하게 바인딩되고 쿼리 라우팅에 활용될 수 있는지 자동화 스크립트로 전수 조사


---

## 2. 아키텍처 및 테스트 구성

```
[관리 프로젝트 (project_id)]
   │
   ├── [Multi-Region: US, EU]
   │      ├── google_bigquery_reservation (Enterprise, baseline=0, autoscale=100)
   │      └── google_bigquery_reservation_assignment (10~100+ User/SA Principals)
   │
   ├── [Asia-Pacific: asia-northeast3(Seoul), asia-northeast1(Tokyo), ...]
   │      ├── google_bigquery_reservation (Enterprise, baseline=0, autoscale=100)
   │      └── google_bigquery_reservation_assignment (10~100+ User/SA Principals)
   │
   ├── [Americas: us-central1, us-east1, us-west1, ...]
   │      ├── google_bigquery_reservation (Enterprise, baseline=0, autoscale=100)
   │      └── google_bigquery_reservation_assignment (10~100+ User/SA Principals)
   │
   └── [Europe & MEA: europe-west1, europe-west3, me-central1, ...]
          ├── google_bigquery_reservation (Enterprise, baseline=0, autoscale=100)
          └── google_bigquery_reservation_assignment (10~100+ User/SA Principals)
```

- **비용 최적화**: 각 리전별 예약은 `slot_capacity = 0`(기준 슬롯 0개) 및 `autoscale.max_slots = 100`으로 설정되어 유휴(Idle) 상태에서는 슬롯 비용이 발생하지 않습니다.
- **Principal 생성**: `google_service_account`를 통해 `var.assignment_count` (예: 10~100개) 만큼의 테스트용 Service Account를 일괄 생성한 뒤, 각 리전의 예약에 `principal` 형태로 2차원 매핑하여 할당합니다.

---

## 3. 사전 준비 사항

1. **권한**: 관리 프로젝트에 대해 다음 IAM 역할 중 하나 필요
   - `BigQuery Admin` (`roles/bigquery.admin`)
   - `BigQuery Resource Admin` (`roles/bigquery.resourceAdmin`)
   - (필수 권한: `bigquery.reservationAssignments.create`, `bigquery.reservations.create`, `iam.serviceAccounts.create`)
2. **API 활성화**:
   - `bigqueryreservation.googleapis.com`
   - `cloudresourcemanager.googleapis.com`
   - `bigquery.googleapis.com`
   - `iam.googleapis.com`
3. **Terraform & Provider**:
   - Terraform: `>= 1.7.0`
   - Google Provider: `>= 7.36.0` (principal 필드 지원)
4. **인증**:
   ```bash
   gcloud auth application-default login
   ```

---

## 4. 사용 방법

### 4.1 설정 파일 준비

`terraform.tfvars` 파일을 생성하고 테스트할 리전 및 리전당 할당 개수를 설정합니다.

```hcl
# terraform.tfvars 예시
project_id       = "bg-wlm-test"
assignment_count = 100   # 10개 초과(최대 100개) 테스트를 위한 계정 수 설정

# 테스트할 리전 목록 (미지정 시 variables.tf에 정의된 35개 전체 리전 적용)
regions = [
  "US",
  "EU",
  "asia-northeast3",
  "asia-northeast1",
  "us-central1",
  "europe-west3"
]
```

### 4.2 인프라 배포 (할당 생성 테스트)

```bash
# 1) 초기화
terraform init -upgrade

# 2) 실행 계획 확인
terraform plan

# 3) 리전별 예약 및 Principal 할당 일괄 생성
terraform apply
```

### 4.3 인프라 정리 (destroy)

```bash
terraform destroy
```

---

## 5. 리전별 한도 적용 검증 방법

### 5.1 전 지역 할당 개수 자동 전수조사 (`verify_assignments.sh`)

제공된 스크립트를 통해 모든 리전의 예약에 생성된 Principal 할당 개수를 `bq CLI`로 일괄 조회하고 10개 이상 정상 적용되었는지 확인합니다.

```bash
PROJECT_ID="bg-wlm-test" ./scripts/verify_assignments.sh
```

**출력 예시:**
```text
======================================================
 BigQuery Multi-Region Principal Assignment 검증
 Project: bg-wlm-test
======================================================

 [OK]   Region: US                        | Reservation: test-res-us                    | Assignments: 100개
 [OK]   Region: EU                        | Reservation: test-res-eu                    | Assignments: 100개
 [OK]   Region: asia-northeast3           | Reservation: test-res-asia-northeast3       | Assignments: 100개
 ...
======================================================
 검증 요약
  - 성공/조회 리전 수 : 35 / 35
  - 총 생성된 할당 수 : 3500
======================================================
```

### 5.2 라우팅 검증 쿼리

생성된 할당 및 실제 쿼리 실행 시의 예약 분기 동작을 확인하려면 아래 쿼리를 실행하세요.

```sql
-- 1) 최근 실행된 작업의 실행 주체별 예약 라우팅 결과 대조
SELECT
  creation_time,
  user_email,
  reservation_id,       -- 할당된 SA는 'test-res-...', 일반 사용자는 'NULL(주문형)'
  total_slot_ms,
  SUBSTR(REPLACE(query, '\n', ' '), 1, 40) AS query_preview
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{PROJECT_ID}'
  AND job_type = 'QUERY'
ORDER BY creation_time DESC
LIMIT 10;

-- 2) 리전별 활성 할당 목록 및 principal 매핑 확인
SELECT
  assignment_id,
  reservation_name,
  job_type,
  assignee_id,
  REGEXP_EXTRACT(ddl, r"""principal\s*=\s*['"]([^'"]+)['"]""") AS principal
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.ASSIGNMENTS
WHERE reservation_name = '{RESERVATION_NAME}';
```


---

## 6. 코드 구조

```
.
├── versions.tf                    # Terraform/Provider 버전 제약 (Google Provider >= 7.36.0)
├── variables.tf                   # 프로젝트, 리전 목록(35개+), 할당 개수(기본 10/100) 변수
├── main.tf                        # 리전별 BigQuery Reservation 및 Principal 할당 일괄 생성
├── service_accounts.tf            # 할당 테스트용 Service Account 대량 생성 및 IAM 권한
├── dataset.tf                     # 쿼리 테스트용 데모 Dataset 설정
├── outputs.tf                     # 리전별 생성 통계 및 예약/계정 출력값
├── terraform.tfvars.example       # 설정 변수 예시 파일
├── README.md                      # 프로젝트 설명 및 테스트 가이드 문서
└── scripts/
    ├── verify_assignments.sh      # 전 지역 Principal 할당 개수 전수 검증 스크립트 (bq CLI)
    └── demo_queries.sql           # 라우팅 확인용 INFORMATION_SCHEMA 쿼리 모음
```

---

