#!/usr/bin/env bash
# ==============================================================================
# Setup Environment for BigQuery Cross-Region Solution Comparison
# Sets up Source & Destination Datasets and populates sample event data
# ==============================================================================
set -euo pipefail

# Default Parameters
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
SOURCE_REGION="${SOURCE_REGION:-us-central1}"
DEST_REGION="${DEST_REGION:-asia-northeast3}"
SOURCE_DATASET="${SOURCE_DATASET:-demo_source_us}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set. Please export PROJECT_ID=<your-project-id> or set default gcloud project." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$(cd "${SCRIPT_DIR}/../sql" && pwd)"

echo "=================================================================="
echo " BigQuery Cross-Region Solution Test Setup"
echo " Project:        ${PROJECT_ID}"
echo " Source Region:  ${SOURCE_REGION} (Dataset: ${SOURCE_DATASET})"
echo " Dest Region:    ${DEST_REGION} (Datasets: demo_dest_dts_kr, demo_dest_copy_kr, demo_dest_crr_kr)"
echo "=================================================================="

# 0. Ensure BigQuery & BigQuery Data Transfer APIs are enabled (for new projects)
echo "[0/3] Ensuring BigQuery & Data Transfer APIs are enabled on '${PROJECT_ID}'..."
gcloud services enable bigquery.googleapis.com bigquerydatatransfer.googleapis.com --project="${PROJECT_ID}" 2>/dev/null || true

# 1. Create Source Dataset
echo "[1/3] Creating Source Dataset '${SOURCE_DATASET}' in ${SOURCE_REGION}..."
bq --project_id="${PROJECT_ID}" --location="${SOURCE_REGION}" mk --dataset \
  --description="Primary Source Dataset for Cross-Region Solution Comparison" \
  "${PROJECT_ID}:${SOURCE_DATASET}" || echo "Source dataset already exists."

# 2. Create Destination Datasets (DTS, Table Copy, CRR)
echo "[2/3] Creating Destination Datasets in ${DEST_REGION}..."
for ds in demo_dest_dts_kr demo_dest_copy_kr demo_dest_crr_kr; do
  bq --project_id="${PROJECT_ID}" --location="${DEST_REGION}" mk --dataset \
    --description="Target Destination Dataset (${ds})" \
    "${PROJECT_ID}:${ds}" || true
done

# 3. Populate Sample Events
echo "[3/3] Populating simulated event data..."
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
