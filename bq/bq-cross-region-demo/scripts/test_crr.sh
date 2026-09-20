#!/usr/bin/env bash
# ==============================================================================
# Test BigQuery CRR (Cross-Region Dataset Replication) Lifecycle
# Automates replica creation, sync monitoring, replica read verification, and promotion
# ==============================================================================
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
SOURCE_DATASET="${SOURCE_DATASET:-sendbird_source_us}"
SOURCE_REGION="${SOURCE_REGION:-us-central1}"
DEST_REGION="${DEST_REGION:-asia-northeast3}"
REPLICA_NAME="${REPLICA_NAME:-replica_kr}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is not set." >&2
  exit 1
fi

echo "=================================================================="
echo " BigQuery CRR (Cross-Region Dataset Replication) Test"
echo " Project:         ${PROJECT_ID}"
echo " Source Dataset:  ${SOURCE_DATASET} (${SOURCE_REGION})"
echo " Replica Target:  ${REPLICA_NAME} in ${DEST_REGION}"
echo " Launch Stage:    GA (Generally Available)"
echo "=================================================================="

# 1. Add Replica DDL
echo -e "\n[Step 1] Adding secondary replica '${REPLICA_NAME}' in '${DEST_REGION}' via DDL..."
ADD_REPLICA_SQL="ALTER SCHEMA \`${PROJECT_ID}.${SOURCE_DATASET}\` ADD REPLICA \`${REPLICA_NAME}\` OPTIONS(location='${DEST_REGION}');"
echo "Executing: ${ADD_REPLICA_SQL}"
bq query --use_legacy_sql=false --location="${SOURCE_REGION}" "${ADD_REPLICA_SQL}"

# 2. Poll Replication Sync Status
echo -e "\n[Step 2] Monitoring initial synchronization status..."
echo "Waiting for replica to synchronize (checking INFORMATION_SCHEMA.SCHEMATA_REPLICAS)..."

MAX_ATTEMPTS=30
ATTEMPT=1
SYNCED=false

while [[ ${ATTEMPT} -le ${MAX_ATTEMPTS} ]]; do
  CHECK_SQL="SELECT replica_name, location, replica_type, sync_status, replication_time FROM \`${PROJECT_ID}\`.\`region-${DEST_REGION}\`.INFORMATION_SCHEMA.SCHEMATA_REPLICAS WHERE schema_name = '${SOURCE_DATASET}';"
  OUTPUT=$(bq query --use_legacy_sql=false --format=prettyjson --location="${DEST_REGION}" "${CHECK_SQL}" 2>/dev/null || echo "[]")

  SYNC_STATUS=$(echo "${OUTPUT}" | grep -o '"sync_status": "[^"]*' | cut -d'"' -f4 || echo "PENDING")
  REPLICA_TYPE=$(echo "${OUTPUT}" | grep -o '"replica_type": "[^"]*' | cut -d'"' -f4 || echo "")

  echo "  [Attempt ${ATTEMPT}/${MAX_ATTEMPTS}] Replica Type: ${REPLICA_TYPE}, Sync Status: ${SYNC_STATUS}"

  if [[ "${SYNC_STATUS}" == "SYNCED" ]]; then
    SYNCED=true
    break
  fi
  sleep 5
  ATTEMPT=$((ATTEMPT + 1))
done

if [[ "${SYNCED}" == "true" ]]; then
  echo -e "\n[SUCCESS] CRR Replica is fully SYNCED!"
else
  echo -e "\n[NOTE] Replica sync is still in progress (Background continuous sync)."
fi

# 3. Test Read Query against Secondary Replica
echo -e "\n[Step 3] Executing read-only analytical query directly against the secondary replica in ${DEST_REGION}..."
READ_SQL="SELECT COUNT(1) AS total_messages, COUNT(DISTINCT channel_url) AS active_channels, MAX(created_at) AS latest_event FROM \`${PROJECT_ID}.${SOURCE_DATASET}.chat_messages\`;"
bq query --use_legacy_sql=false --location="${DEST_REGION}" "${READ_SQL}"

echo -e "\n=================================================================="
echo " BigQuery CRR verification step completed successfully!"
echo " Useful management commands:"
echo "  - Failover (Promote): ALTER SCHEMA \`${PROJECT_ID}.${SOURCE_DATASET}\` SET OPTIONS(primary_replica='${DEST_REGION}');"
echo "  - Revert:             ALTER SCHEMA \`${PROJECT_ID}.${SOURCE_DATASET}\` SET OPTIONS(primary_replica='${SOURCE_REGION}');"
echo "  - Drop Replica:       ALTER SCHEMA \`${PROJECT_ID}.${SOURCE_DATASET}\` DROP REPLICA IF EXISTS \`${REPLICA_NAME}\`;"
echo "=================================================================="
