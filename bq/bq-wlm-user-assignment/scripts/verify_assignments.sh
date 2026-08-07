#!/usr/bin/env bash
#
# 생성된 예약 할당(일반 + principal 기반)을 조회하고 검증하는 스크립트.
# Terraform apply 이후 데모 시연 시 사용하세요.
#
# 사용법:
#   ADMIN_PROJECT_ID=... LOCATION=... RESERVATION_NAME=... TARGET_PROJECT_ID=... \
#   ./verify_assignments.sh

set -euo pipefail

: "${ADMIN_PROJECT_ID:?ADMIN_PROJECT_ID 환경변수를 설정하세요}"
: "${LOCATION:?LOCATION 환경변수를 설정하세요}"
: "${RESERVATION_NAME:?RESERVATION_NAME 환경변수를 설정하세요}"
: "${TARGET_PROJECT_ID:?TARGET_PROJECT_ID 환경변수를 설정하세요}"

echo "======================================================"
echo "1) 해당 프로젝트의 일반(default) 할당 조회"
echo "======================================================"
bq show \
  --project_id="${ADMIN_PROJECT_ID}" \
  --location="${LOCATION}" \
  --reservation_assignment \
  --job_type=QUERY \
  --assignee_id="${TARGET_PROJECT_ID}" \
  --assignee_type=PROJECT

echo
echo "======================================================"
echo "2) 예약(reservation)에 걸린 전체 할당 목록"
echo "   (principal 컬럼으로 principal 기반 할당 여부 확인)"
echo "======================================================"
bq ls --reservation_assignment \
  --project_id="${ADMIN_PROJECT_ID}" \
  --location="${LOCATION}" \
  "${RESERVATION_NAME}"

echo
echo "======================================================"
echo "3) INFORMATION_SCHEMA.ASSIGNMENTS 로 할당 및 principal 확인"
echo "   (bq query 로 실행)"
echo "======================================================"
cat <<SQL
SELECT
  assignment_id,
  reservation_name,
  job_type,
  assignee_id,
  assignee_type,
  -- DDL에서 principal 속성 추출
  REGEXP_EXTRACT(ddl, r"""principal\s*=\s*['"]([^'"]+)['"]""") AS principal,
  ddl
FROM \`region-${LOCATION}\`.INFORMATION_SCHEMA.ASSIGNMENTS
WHERE reservation_name = '${RESERVATION_NAME}';
SQL
