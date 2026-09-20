#!/usr/bin/env bash
# ==============================================================================
# Setup Environment for BigQuery Cross-Region Solution Comparison
# Sets up Source & Destination Datasets and populates Sendbird sample chat data
# ==============================================================================
set -euo pipefail

# Default Parameters
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
SOURCE_REGION="${SOURCE_REGION:-us-central1}"
DEST_REGION="${DEST_REGION:-asia-northeast3}"
SOURCE_DATASET="${SOURCE_DATASET:-sendbird_source_us}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set. Please export PROJECT_ID=<your-project-id> or set default gcloud project." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$(cd "${SCRIPT_DIR}/../sql" && pwd)"

echo "=================================================================="
echo " Sendbird BigQuery Cross-Region Solution Test Setup"
echo " Project:        ${PROJECT_ID}"
echo " Source Region:  ${SOURCE_REGION} (Dataset: ${SOURCE_DATASET})"
echo " Dest Region:    ${DEST_REGION} (Dataset: ${DEST_DATASET})"
echo "=================================================================="

# 1. Create Source Dataset
echo "[1/3] Creating Source Dataset '${SOURCE_DATASET}' in ${SOURCE_REGION}..."
bq --project_id="${PROJECT_ID}" --location="${SOURCE_REGION}" mk --dataset \
  --description="Sendbird Primary Source Dataset for Solution Comparison" \
  "${PROJECT_ID}:${SOURCE_DATASET}" || echo "Source dataset already exists."

# 2. Create Destination Datasets (DTS, Table Copy, CRR)
#    - sendbird_dest_dts_kr  -> populated by test_dts.sh
#    - sendbird_dest_copy_kr -> populated by test_table_copy.py
#    - sendbird_dest_crr_kr  -> not written to by test_crr.sh (CRR replicates the
#      source dataset under its own name); reserved for the optional ui/server.py
#      demo, which creates convenience views here pointing at the replica.
echo "[2/3] Creating Destination Datasets in ${DEST_REGION}..."
for ds in sendbird_dest_dts_kr sendbird_dest_copy_kr sendbird_dest_crr_kr; do
  bq --project_id="${PROJECT_ID}" --location="${DEST_REGION}" mk --dataset \
    --description="Sendbird Target Destination Dataset (${ds})" \
    "${PROJECT_ID}:${ds}" || true
done

# 3. Populate Sample Chat Events
echo "[3/3] Populating simulated Sendbird chat data..."
TEMP_SQL=$(mktemp)
sed -e "s/@PROJECT_ID@/${PROJECT_ID}/g" \
    -e "s/@SOURCE_DATASET@/${SOURCE_DATASET}/g" \
    "${SQL_DIR}/01_setup_sample_data.sql" > "${TEMP_SQL}"

bq --project_id="${PROJECT_ID}" query --use_legacy_sql=false --location="${SOURCE_REGION}" < "${TEMP_SQL}"
rm -f "${TEMP_SQL}"

echo ""
echo "=================================================================="
echo " Environment setup completed successfully!"
echo " Source table '${PROJECT_ID}.${SOURCE_DATASET}.chat_messages' is ready."
echo "=================================================================="
