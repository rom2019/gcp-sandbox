-- ============================================================
-- BigQuery Reservation Principal 기반 할당 - 시연용 쿼리 모음
-- ============================================================
-- 시연 시나리오:
--   1) [VIP 서비스 계정 ETL 시연]
--      - vip_etl 서비스 계정으로 샘플 데이터 적재 및 일별 요약 ETL 실행
--      - gcloud/bq에서 impersonation 또는 SA 키로 실행
--   2) [VIP 사용자 분석 쿼리 시연]
--      - vip_user_email 계정으로 로그인하여 분석 쿼리 실행
--   3) [일반 사용자 분석 쿼리 시연]
--      - 일반 계정으로 동일한 분석 쿼리 실행
--   4) [결과 대조 및 라우팅 검증]
--      - INFORMATION_SCHEMA.JOBS_BY_PROJECT 로 실행 주체별 reservation_id 대조
--
-- 아래 쿼리들은 BigQuery 콘솔 쿼리 편집기 또는 bq query 명령으로 실행하세요.
-- REPLACE 대상: {LOCATION}, {RESERVATION_NAME}, {TARGET_PROJECT_ID}, {ADMIN_PROJECT_ID}

-- ============================================================
-- 1. [VIP ETL 서비스 계정 전용] 샘플 데이터 적재 & 일별 요약 ETL
-- ============================================================
-- 서비스 계정 가장(impersonation) 실행 예시 (Cloud Shell / 로컬 터미널):
--   bq query --use_legacy_sql=false \
--     --impersonate_service_account=bq-reservation-demo-etl@{TARGET_PROJECT_ID}.iam.gserviceaccount.com \
--     --project_id={TARGET_PROJECT_ID} \
--     --location={LOCATION} \
--     '<아래 1-1 또는 1-2 쿼리>'

-- (1-1) 주문 샘플 데이터 대량 생성 및 적재 (10,000건)
INSERT INTO `{TARGET_PROJECT_ID}.bq_wlm_demo.sample_orders`
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
INSERT INTO `{TARGET_PROJECT_ID}.bq_wlm_demo.daily_summary`
  (summary_date, category, total_orders, total_revenue)
SELECT
  DATE(order_timestamp) AS summary_date,
  category,
  COUNT(1) AS total_orders,
  SUM(amount) AS total_revenue
FROM `{TARGET_PROJECT_ID}.bq_wlm_demo.sample_orders`
GROUP BY summary_date, category;


-- ============================================================
-- 2. [VIP 사용자 / 일반 사용자] 분석 쿼리 실행
-- ============================================================
-- vip_user_email 계정 및 일반 계정으로 각각 콘솔에서 실행하여
-- 동일 쿼리가 사용자 ID에 따라 각기 다른 예약으로 라우팅되는지 확인합니다.

-- (2-1) 데모 테이블 대상 카테고리별 매출 분석
SELECT
  category,
  COUNT(1) AS order_count,
  AVG(amount) AS avg_amount,
  SUM(amount) AS total_amount
FROM `{TARGET_PROJECT_ID}.bq_wlm_demo.sample_orders`
GROUP BY category
ORDER BY total_amount DESC;

-- (2-2) BigQuery 공개 데이터셋 대상 슬롯 소모형 집계 쿼리 (대용량 쿼리 테스트용)
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
-- 각 작업(Job)의 user_email(실행 주체)과 매핑된 reservation_id를 확인합니다.
SELECT
  job_id,
  user_email,
  reservation_id,
  total_slot_ms,
  total_bytes_billed,
  query,
  creation_time
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{TARGET_PROJECT_ID}'
  AND job_type = 'QUERY'
ORDER BY creation_time DESC
LIMIT 20;


-- ============================================================
-- 4. [검증] 현재 활성 할당(Assignment) 목록 및 Principal 확인
-- ============================================================
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


-- ============================================================
-- 5. [부가 기능] 세션 내 특정 예약 수동 재정의 (SET @@reservation)
-- ============================================================
-- principal 우선순위와 별개로, 세션 단위로 특정 예약을 강제 지정할 수도 있습니다.
SET @@reservation = 'projects/{ADMIN_PROJECT_ID}/locations/{LOCATION}/reservations/{RESERVATION_NAME}';
SELECT 1 AS demo_forced_reservation;


-- ============================================================
-- 6. [부가 기능] SQL DDL로 principal 기반 할당을 즉석 생성하는 예시
-- ============================================================
CREATE ASSIGNMENT
  `{ADMIN_PROJECT_ID}.region-{LOCATION}.{RESERVATION_NAME}.demo-adhoc-assignment`
OPTIONS (
  assignee = 'projects/{TARGET_PROJECT_ID}',
  principal = 'principal://goog/subject/another.user@example.com',
  job_type = 'QUERY');

-- 삭제 시:
-- DROP ASSIGNMENT
--   `{ADMIN_PROJECT_ID}.region-{LOCATION}.{RESERVATION_NAME}.demo-adhoc-assignment`;
