-- ============================================================
-- BigQuery Reservation Principal 기반 할당 - 검증 및 데모용 쿼리 모음
-- ============================================================
-- 테스트 시나리오:
--   1) [할당된 테스트 SA(Principal)로 ETL 및 데이터 적재]
--      - bq-wlm-test-user-01 계정으로 샘플 데이터 적재 및 일별 요약 실행
--      - gcloud/bq에서 impersonation 실행 -> 예약 슬롯으로 라우팅됨
--   2) [할당된 SA vs 미할당 일반 계정] 분석 쿼리 실행
--      - 각각 쿼리를 실행하여 실행 주체에 따라 예약 슬롯 / 주문형으로 자동 분기되는지 확인
--   3) [결과 대조 및 라우팅 검증]
--      - INFORMATION_SCHEMA.JOBS_BY_PROJECT 로 실행 주체별 reservation_id 대조
--   4) [할당 목록 확인]
--      - INFORMATION_SCHEMA.ASSIGNMENTS 로 리전별 생성된 Principal 할당 목록 조회
--
-- 아래 쿼리들은 BigQuery 콘솔 쿼리 편집기 또는 bq query 명령으로 실행하세요.
-- 변수 치환 대상:
--   - {PROJECT_ID}        : GCP 프로젝트 ID (예: bg-wlm-test)
--   - {LOCATION}          : 리전 (예: asia-northeast3)
--   - {DATASET_ID}        : 데이터셋 ID (예: bq_wlm_demo_asia_northeast3)
--   - {RESERVATION_NAME}  : 예약 이름 (예: test-res-asia-northeast3)
--   - {ASSIGNED_SA_EMAIL} : 할당된 서비스 계정 (예: bq-wlm-test-user-01@{PROJECT_ID}.iam.gserviceaccount.com)


-- ============================================================
-- 0. [사전 설정] 서비스 계정 가장(Impersonation) gcloud 가이드
-- ============================================================
-- 0-1) 본인 계정에 Token Creator 권한 부여 (최초 1회, 관리자 계정으로 실행):
--   gcloud projects add-iam-policy-binding {PROJECT_ID} \
--     --member="user:$(gcloud config get-value account)" \
--     --role="roles/iam.serviceAccountTokenCreator"
--
-- 0-2) 서비스 계정 가장(Impersonation) 활성화:
--   gcloud config set auth/impersonate_service_account bq-wlm-test-user-01@{PROJECT_ID}.iam.gserviceaccount.com
--
-- 0-3) 가장(Impersonation) 해제 (관리자 계정으로 복귀 및 모니터링 시 사용):
--   gcloud config unset auth/impersonate_service_account
--
-- 0-4) 현재 가장 상태 확인:
--   gcloud config get-value auth/impersonate_service_account


-- ============================================================
-- 1. [Principal 할당 서비스 계정] 샘플 데이터 적재 & 요약 ETL

-- ============================================================
-- 서비스 계정 가장(impersonation) 실행 예시 (터미널 / Cloud Shell):
--   bq query --use_legacy_sql=false \
--     --impersonate_service_account=bq-wlm-test-user-01@{PROJECT_ID}.iam.gserviceaccount.com \
--     --project_id={PROJECT_ID} \
--     --location={LOCATION} \
--     '<아래 1-1 또는 1-2 쿼리>'

-- (1-1) 주문 샘플 데이터 대량 생성 및 적재 (10,000건)
INSERT INTO `{PROJECT_ID}.{DATASET_ID}.sample_orders`
  (order_id, customer_id, category, amount, order_timestamp)
SELECT
  GENERATE_UUID() AS order_id,
  CONCAT('CUST-', CAST(CAST(FLOOR(RAND() * 1000) AS INT64) AS STRING)) AS customer_id,
  CASE CAST(FLOOR(RAND() * 5) AS INT64)
    WHEN 0 THEN 'Electronics'
    WHEN 1 THEN 'Fashion'
    WHEN 2 THEN 'Home'
    WHEN 3 THEN 'Books'
    ELSE 'Grocery'
  END AS category,
  ROUND(CAST(RAND() * 500 + 10 AS NUMERIC), 2) AS amount,
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL CAST(FLOOR(RAND() * 30) AS INT64) DAY) AS order_timestamp
FROM UNNEST(GENERATE_ARRAY(1, 10000));

-- (1-2) 일별 매출 요약 ETL 집계 적재
INSERT INTO `{PROJECT_ID}.{DATASET_ID}.daily_summary`
  (summary_date, category, total_orders, total_revenue)
SELECT
  DATE(order_timestamp) AS summary_date,
  category,
  COUNT(1) AS total_orders,
  SUM(amount) AS total_revenue
FROM `{PROJECT_ID}.{DATASET_ID}.sample_orders`
GROUP BY summary_date, category;


-- ============================================================
-- 2. [할당 계정 / 미할당 일반 계정] 분석 쿼리 실행
-- ============================================================
-- 할당된 SA(bq-wlm-test-user-01@...) 및 일반 미할당 계정으로 각각 실행하여
-- 동일 쿼리가 실행 주체에 따라 각기 다른 예약/주문형으로 라우팅되는지 확인합니다.

-- (2-1) 데모 테이블 대상 카테고리별 매출 분석
-- bq CLI 실행 예시:
--   bq query --use_legacy_sql=false \
--     --project_id="{PROJECT_ID}" \
--     --location="{LOCATION}" \
--     "SELECT
--        category,
--        COUNT(1) AS order_count,
--        AVG(amount) AS avg_amount,
--        SUM(amount) AS total_amount
--      FROM \`{PROJECT_ID}.{DATASET_ID}.sample_orders\`
--      GROUP BY category
--      ORDER BY total_amount DESC;"

SELECT
  category,
  COUNT(1) AS order_count,
  AVG(amount) AS avg_amount,
  SUM(amount) AS total_amount
FROM `{PROJECT_ID}.{DATASET_ID}.sample_orders`
GROUP BY category
ORDER BY total_amount DESC;


-- (2-2) BigQuery 공개 데이터셋 대상 슬롯 소모형 집계 쿼리 (대용량 쿼리 테스트용)
-- ※ 공개 데이터셋은 Multi-region US 에 위치하므로 --location=US 로 실행합니다.
-- bq CLI 실행 예시:
--   bq query --use_legacy_sql=false \
--     --project_id="{PROJECT_ID}" \
--     --location="US" \
--     "SELECT
--        state,
--        gender,
--        year,
--        name,
--        SUM(number) AS total_count
--      FROM \`bigquery-public-data.usa_names.usa_1910_current\`
--      WHERE year >= 2000
--      GROUP BY 1, 2, 3, 4
--      ORDER BY total_count DESC
--      LIMIT 50;"

SELECT
  state,
  gender,
  year,
  name,
  SUM(number) AS total_count
FROM `bigquery-public-data.usa_names.usa_1910_current`
WHERE year >= 2000
GROUP BY 1, 2, 3, 4
ORDER BY total_count DESC
LIMIT 50;



-- ============================================================
-- 3. [검증] 최근 실행된 쿼리 작업의 예약 라우팅 결과 확인
-- ============================================================
-- [관리자 계정 자격] 전체 사용자 실행 주체별 예약 라우팅 대조 (JOBS_BY_PROJECT)
--   (먼저 gcloud config unset auth/impersonate_service_account 실행)
--   bq query --use_legacy_sql=false \
--     --project_id="{PROJECT_ID}" \
--     --location="{LOCATION}" \
--     "SELECT
--        creation_time,
--        user_email,
--        reservation_id,
--        total_slot_ms,
--        SUBSTR(REPLACE(query, '\n', ' '), 1, 40) AS query_preview
--      FROM \`region-{LOCATION}\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
--      WHERE project_id = '{PROJECT_ID}'
--        AND job_type = 'QUERY'
--      ORDER BY creation_time DESC
--      LIMIT 20;"

-- (기본 쿼리: 관리자 콘솔용)
SELECT
  creation_time,
  user_email,
  reservation_id,
  total_slot_ms,
  total_bytes_billed,
  SUBSTR(REPLACE(query, '\n', ' '), 1, 40) AS query_preview
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{PROJECT_ID}'
  AND job_type = 'QUERY'
ORDER BY creation_time DESC
LIMIT 20;




-- ============================================================
-- 4. [검증] 현재 활성 할당(Assignment) 목록 및 Principal 확인
-- ============================================================
-- bq CLI 실행 예시:
--   bq query --use_legacy_sql=false \
--     --project_id="{PROJECT_ID}" \
--     --location="{LOCATION}" \
--     "SELECT
--        assignment_id,
--        reservation_name,
--        job_type,
--        assignee_id,
--        assignee_type,
--        REGEXP_EXTRACT(ddl, r'''principal\s*=\s*['\x22]([^'\x22]+)['\x22]''') AS principal
--      FROM \`region-{LOCATION}\`.INFORMATION_SCHEMA.ASSIGNMENTS
--      WHERE reservation_name = '{RESERVATION_NAME}';"

SELECT
  assignment_id,
  reservation_name,
  job_type,
  assignee_id,
  assignee_type,
  -- DDL 옵션에서 principal 속성 추출
  REGEXP_EXTRACT(ddl, r"""principal\s*=\s*['"]([^'"]+)['"]""") AS principal,
  ddl
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.ASSIGNMENTS
WHERE reservation_name = '{RESERVATION_NAME}';

