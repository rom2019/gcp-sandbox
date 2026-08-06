-- ============================================================
-- BigQuery Reservation Principal 기반 할당 - 시연용 쿼리 모음
-- ============================================================
-- 시연 시나리오:
--   1) demo_project_id 에서 "일반 사용자" 계정으로 쿼리 실행
--      → project_default 할당(=예약 전체 슬롯)을 통해 라우팅됨
--   2) 동일 프로젝트에서 vip_user_email 계정으로 쿼리 실행
--      → project_default가 아닌 vip_user 전용 principal 할당으로 라우팅됨
--   3) 동일 프로젝트에서 vip_service_account_email 로 쿼리 실행(예: Dataform/스케줄된 쿼리)
--      → vip_service_account 전용 principal 할당으로 라우팅됨
--
-- 아래 쿼리들은 BigQuery 콘솔 쿼리 편집기 또는 bq query 명령으로 실행하세요.
-- REPLACE 대상: {LOCATION}, {RESERVATION_NAME}, {TARGET_PROJECT_ID}

-- ------------------------------------------------------------
-- (A) 특정 작업(Job)이 어떤 예약을 사용했는지 확인
-- ------------------------------------------------------------
SELECT
  job_id,
  user_email,
  reservation_id,
  total_slot_ms,
  creation_time
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE project_id = '{TARGET_PROJECT_ID}'
  AND job_type = 'QUERY'
ORDER BY creation_time DESC
LIMIT 20;

-- ------------------------------------------------------------
-- (B) 현재 활성 할당(assignment) 목록과 DDL 정의(principal, 한도 등) 확인
-- ------------------------------------------------------------
SELECT
  assignment_id,
  reservation_name,
  job_type,
  assignee_id,
  assignee_type,
  ddl
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.ASSIGNMENTS
WHERE reservation_name = '{RESERVATION_NAME}';

-- ------------------------------------------------------------
-- (C) 특정 프로젝트가 사용 중인 예약 확인 (일반 할당 기준)
-- ------------------------------------------------------------
SELECT
  assignment_id
FROM `region-{LOCATION}`.INFORMATION_SCHEMA.ASSIGNMENTS_BY_PROJECT
WHERE assignee_id = '{TARGET_PROJECT_ID}'
  AND job_type = 'QUERY';

-- ------------------------------------------------------------
-- (D) 세션에서 특정 예약을 강제 지정하여 쿼리 (재정의 데모)
--     principal 우선순위와 별개로, 이 방식으로 특정 예약을
--     명시적으로 지정할 수도 있습니다.
-- ------------------------------------------------------------
SET @@reservation = 'projects/{ADMIN_PROJECT_ID}/locations/{LOCATION}/reservations/{RESERVATION_NAME}';
SELECT 1 AS demo_forced_reservation;

-- ------------------------------------------------------------
-- (E) principal 기반 할당을 SQL DDL로 직접 만들어보는 예시
--     (Terraform 대신 즉석 데모/워크숍에서 빠르게 보여줄 때 유용)
-- ------------------------------------------------------------
CREATE ASSIGNMENT
  `{ADMIN_PROJECT_ID}.region-{LOCATION}.{RESERVATION_NAME}.demo-adhoc-assignment`
OPTIONS (
  assignee = 'projects/{TARGET_PROJECT_ID}',
  principal = 'principal://goog/subject/another.user@example.com',
  job_type = 'QUERY');

-- 삭제할 때는:
-- DROP ASSIGNMENT
--   `{ADMIN_PROJECT_ID}.region-{LOCATION}.{RESERVATION_NAME}.demo-adhoc-assignment`;
