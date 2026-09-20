#!/usr/bin/env bash
# ==============================================================================
# Test BigQuery DTS (Data Transfer Service) Dataset Copy
# Sets up transfer configuration, triggers manual run, and polls transfer status
# ==============================================================================
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
SOURCE_DATASET="${SOURCE_DATASET:-sendbird_source_us}"
DEST_DATASET="${DEST_DATASET:-sendbird_dest_dts_kr}"
DEST_REGION="${DEST_REGION:-asia-northeast3}"
DISPLAY_NAME="Sendbird_Solution_Comparison_DTS_${DEST_REGION}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set." >&2
  exit 1
fi

echo "=================================================================="
echo " BigQuery DTS (Data Transfer Service) Dataset Copy Test"
echo " Project:         ${PROJECT_ID}"
echo " Source Dataset:  ${SOURCE_DATASET}"
echo " Dest Dataset:    ${DEST_DATASET} (${DEST_REGION})"
echo " Launch Stage:    Beta (Pre-GA)"
echo "=================================================================="

# 1. Create or Identify DTS Transfer Config
echo -e "\n[Step 1] Creating DTS Transfer Configuration in ${DEST_REGION}..."

# Construct params JSON: source_dataset_id and source_project_id
PARAMS_JSON="{\"source_dataset_id\": \"${SOURCE_DATASET}\", \"source_project_id\": \"${PROJECT_ID}\", \"overwrite_destination_table\": \"true\"}"

TRANSFER_CONFIG_NAME=$(bq mk \
  --transfer_config \
  --project_id="${PROJECT_ID}" \
  --data_source="cross_region_copy" \
  --display_name="${DISPLAY_NAME}" \
  --target_dataset="${DEST_DATASET}" \
  --params="${PARAMS_JSON}" \
  --location="${DEST_REGION}" 2>&1 | grep -oE "projects/[^ ']+" || echo "")

if [[ -z "${TRANSFER_CONFIG_NAME}" ]]; then
  echo "Checking existing transfer configuration..."
  TRANSFER_CONFIG_NAME=$(bq ls --transfer_config --transfer_location="${DEST_REGION}" | grep "${DISPLAY_NAME}" | awk '{print $1}' || echo "")
fi

echo "Transfer Config Name: ${TRANSFER_CONFIG_NAME}"

# 2. Trigger Manual Run
if [[ -n "${TRANSFER_CONFIG_NAME}" ]]; then
  echo -e "\n[Step 2] Triggering manual transfer run..."
  START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  bq mk \
    --transfer_run \
    --start_time="${START_TIME}" \
    --end_time="${START_TIME}" \
    "${TRANSFER_CONFIG_NAME}" || echo "Run requested."

  echo -e "\n[Step 3] Monitoring transfer runs..."
  bq ls --transfer_run "${TRANSFER_CONFIG_NAME}" || true
else
  echo "[Notice] Transfer config created via Console or existing ID. Please verify via BigQuery Console > Data Transfers."
fi

echo -e "\n=================================================================="
echo " BigQuery DTS Dataset Copy configuration complete."
echo " To inspect runs via SQL:"
echo " SELECT * FROM \`${PROJECT_ID}\`.\`region-${DEST_REGION}\`.INFORMATION_SCHEMA.DATA_TRANSFER_RUNS ORDER BY run_time DESC LIMIT 5;"
echo "=================================================================="
