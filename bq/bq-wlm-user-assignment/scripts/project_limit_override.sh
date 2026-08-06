#!/usr/bin/env bash
#
# [Terraform 미지원 기능] 프로젝트 한도(Project Limit) / 일정 정책 재정의
# -----------------------------------------------------------------------
# GCP 공식 문서(reservations-assignments)에는 이 기능에 대해 콘솔/SQL/bq 방식만
# 안내되어 있으며, Terraform 리소스(google_bigquery_reservation_assignment)에는
# 해당 기능(scheduling_policy_max_slots / scheduling_policy_concurrency)을
# 설정하는 인수가 아직 노출되어 있지 않습니다.
#
# 따라서 이 기능은 bq CLI 또는 SQL DDL(CREATE ASSIGNMENT ... OPTIONS(...))로
# 직접 구성해야 합니다. 이 스크립트는 bq CLI 방식 예시입니다.
#
# 이 기능은 Preview(GA 이전) 단계이므로 사용 전 GCP 공식 문서의
# 최신 상태를 다시 확인하세요.
#
# 사용법:
#   ADMIN_PROJECT_ID=... LOCATION=... RESERVATION_NAME=... \
#   TARGET_PROJECT_ID=... MAX_SLOTS=100 MAX_CONCURRENCY=5 \
#   ./project_limit_override.sh

set -euo pipefail

: "${ADMIN_PROJECT_ID:?ADMIN_PROJECT_ID 환경변수를 설정하세요 (예약 리소스를 소유한 관리 프로젝트)}"
: "${LOCATION:?LOCATION 환경변수를 설정하세요 (예: US, asia-northeast3)}"
: "${RESERVATION_NAME:?RESERVATION_NAME 환경변수를 설정하세요}"
: "${TARGET_PROJECT_ID:?TARGET_PROJECT_ID 환경변수를 설정하세요 (한도를 적용할 프로젝트)}"
: "${MAX_SLOTS:?MAX_SLOTS 환경변수를 설정하세요 (최소값: 100, 예: 100)}"
: "${MAX_CONCURRENCY:?MAX_CONCURRENCY 환경변수를 설정하세요 (예: 5)}"

echo ">>> 프로젝트 한도(Project Limit) 할당 규칙 생성 중..."
bq mk \
  --project_id="${ADMIN_PROJECT_ID}" \
  --location="${LOCATION}" \
  --reservation_assignment \
  --reservation_id="${RESERVATION_NAME}" \
  --assignee_id="${TARGET_PROJECT_ID}" \
  --assignee_type=PROJECT \
  --scheduling_policy_max_slots="${MAX_SLOTS}" \
  --scheduling_policy_concurrency="${MAX_CONCURRENCY}"

echo ">>> 완료. 활성 할당 및 일정 정책(DDL)은 아래 쿼리로 확인할 수 있습니다:"
cat <<SQL

SELECT
  assignment_id,
  reservation_name,
  job_type,
  assignee_id,
  assignee_type,
  ddl
FROM \`region-${LOCATION}\`.INFORMATION_SCHEMA.ASSIGNMENTS
WHERE assignee_id = '${TARGET_PROJECT_ID}';

SQL
