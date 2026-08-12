#!/usr/bin/env bash
#
# 모든 리전의 BigQuery 예약 할당(Principal Assignment) 개수를 조회하고 검증하는 스크립트.
# Terraform apply 이후 테스트 검증 시 사용하세요.
#
# 사용법:
#   PROJECT_ID="bg-wlm-test" ./scripts/verify_assignments.sh
#

set -euo pipefail

PROJECT_ID="${PROJECT_ID:-bg-wlm-test}"
RESERVATION_PREFIX="${RESERVATION_PREFIX:-test-res}"

# 검증할 주요 리전 목록
REGIONS=(
  "asia-northeast3"
)

echo "======================================================"
echo " BigQuery Multi-Region Principal Assignment 검증"
echo " Project: ${PROJECT_ID}"
echo "======================================================"
echo

TOTAL_ASSIGNMENTS=0
SUCCESS_REGIONS=0
FAIL_REGIONS=0

for region in "${REGIONS[@]}"; do
  normalized_region=$(echo "${region}" | tr '[:upper:]' '[:lower:]')
  res_name="${RESERVATION_PREFIX}-${normalized_region}"

  # bq ls 로 할당 목록 조회
  assignment_lines=$(bq ls --reservation_assignment \
    --project_id="${PROJECT_ID}" \
    --location="${region}" \
    "${res_name}" 2>/dev/null || true)

  # Header 제외한 데이터 라인 수 집계
  count=$(echo "${assignment_lines}" | grep -c "QUERY" || true)

  if [ "${count}" -ge 10 ]; then
    printf " [OK]   Region: %-25s | Reservation: %-30s | Assignments: %s개\n" "${region}" "${res_name}" "${count}"
    SUCCESS_REGIONS=$((SUCCESS_REGIONS + 1))
    TOTAL_ASSIGNMENTS=$((TOTAL_ASSIGNMENTS + count))
  elif [ "${count}" -gt 0 ]; then
    printf " [WARN] Region: %-25s | Reservation: %-30s | Assignments: %s개 (10개 미만)\n" "${region}" "${res_name}" "${count}"
    SUCCESS_REGIONS=$((SUCCESS_REGIONS + 1))
    TOTAL_ASSIGNMENTS=$((TOTAL_ASSIGNMENTS + count))
  else
    printf " [SKIP/FAIL] Region: %-25s | Reservation: %-30s | Not found or 0 assignments\n" "${region}" "${res_name}"
    FAIL_REGIONS=$((FAIL_REGIONS + 1))
  fi
done

echo
echo "======================================================"
echo " 검증 요약"
echo "  - 성공/조회 리전 수 : ${SUCCESS_REGIONS} / ${#REGIONS[@]}"
echo "  - 총 생성된 할당 수 : ${TOTAL_ASSIGNMENTS}"
echo "======================================================"
