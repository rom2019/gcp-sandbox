#!/usr/bin/env bash
# ==============================================================================
# Cleanup Script for BigQuery Cross-Region Solution Comparison
# Removes replicas, transfer configs, and test datasets to avoid ongoing charges
# ==============================================================================
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
SOURCE_DATASET="${SOURCE_DATASET:-demo_source_us}"
SOURCE_REGION="${SOURCE_REGION:-us-central1}"
DEST_REGION="${DEST_REGION:-asia-northeast3}"
REPLICA_NAME="${REPLICA_NAME:-replica_kr}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set." >&2
  exit 1
fi

echo "=================================================================="
echo " BigQuery Test Resource Cleanup"
echo " Project:        ${PROJECT_ID}"
echo " Source Dataset: ${SOURCE_DATASET} in ${SOURCE_REGION}"
echo " Dest Datasets:  demo_dest_{dts,copy,crr}_kr in ${DEST_REGION}"
echo "=================================================================="

# 1. Drop CRR Replica
echo "[1/4] Dropping CRR Replica '${REPLICA_NAME}' if exists..."
DROP_REPLICA_SQL="ALTER SCHEMA \`${PROJECT_ID}.${SOURCE_DATASET}\` DROP REPLICA IF EXISTS \`${REPLICA_NAME}\`;"
bq --project_id="${PROJECT_ID}" query --use_legacy_sql=false --location="${SOURCE_REGION}" "${DROP_REPLICA_SQL}" 2>/dev/null || echo "No replica to drop."

# 2. Remove DTS Transfer Configs
echo "[2/4] Removing DTS transfer configurations in ${DEST_REGION}..."
CONFIG_IDS=$(bq ls --transfer_config --project_id="${PROJECT_ID}" --transfer_location="${DEST_REGION}" 2>/dev/null | grep -E "BQ_Demo_Solution|BQ_Solution_Comparison" | awk '{print $1}' || echo "")
for cid in ${CONFIG_IDS}; do
  echo "Deleting transfer config: ${cid}"
  bq --project_id="${PROJECT_ID}" rm -f --transfer_config "${cid}" 2>/dev/null || true
done

# 3. Delete Destination Datasets (dts_kr, copy_kr, crr_kr)
echo "[3/4] Removing Destination Datasets..."
for ds in demo_dest_dts_kr demo_dest_copy_kr demo_dest_crr_kr; do
  bq --project_id="${PROJECT_ID}" rm -r -f -d "${PROJECT_ID}:${ds}" 2>/dev/null || true
done

# 4. Delete Source Dataset
echo "[4/4] Removing Source Dataset '${SOURCE_DATASET}'..."
bq --project_id="${PROJECT_ID}" rm -r -f -d "${PROJECT_ID}:${SOURCE_DATASET}" 2>/dev/null || echo "Source dataset already removed."

echo "=================================================================="
echo " Cleanup completed! All test resources removed successfully."
echo "=================================================================="
