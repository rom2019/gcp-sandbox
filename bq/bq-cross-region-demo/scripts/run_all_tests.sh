#!/usr/bin/env bash
# ==============================================================================
# Master Test Orchestrator for Sendbird BigQuery Cross-Region Solutions
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
export SOURCE_REGION="${SOURCE_REGION:-us-central1}"
export DEST_REGION="${DEST_REGION:-asia-northeast3}"
export SOURCE_DATASET="${SOURCE_DATASET:-sendbird_source_us}"
export DEST_DATASET="${DEST_DATASET:-sendbird_dest_kr}"
export REPLICA_NAME="${REPLICA_NAME:-replica_kr}"

echo "=================================================================="
echo " Sendbird BigQuery Cross-Region Solutions Demo & Test Orchestrator"
echo "=================================================================="
echo " 1. Setup Environment (Create Datasets & Populate Sample Data)"
echo " 2. Test Solution 1: BigQuery CRR (Cross-Region Dataset Replication) [GA]"
echo " 3. Test Solution 2: Cross-Region Table Copy (Python SDK) [Preview]"
echo " 4. Test Solution 3: BigQuery DTS (Dataset Copy) [Beta]"
echo " 5. Cleanup All Test Resources"
echo " 0. Exit"
echo "=================================================================="

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: PROJECT_ID is required. Export PROJECT_ID=<your-project-id> and rerun." >&2
  exit 1
fi

ACTION="${1:-}"

if [[ -z "${ACTION}" ]]; then
  read -rp "Select an option [1-5]: " ACTION
fi

case "${ACTION}" in
  1)
    echo -e "\n>>> Running Environment Setup..."
    "${SCRIPT_DIR}/setup_environment.sh"
    ;;
  2)
    echo -e "\n>>> Running BigQuery CRR Test..."
    "${SCRIPT_DIR}/test_crr.sh"
    ;;
  3)
    echo -e "\n>>> Running Cross-Region Table Copy Test..."
    python3 "${SCRIPT_DIR}/test_table_copy.py" \
      --project_id="${PROJECT_ID}" \
      --source_dataset="${SOURCE_DATASET}" \
      --source_table="chat_messages" \
      --dest_dataset="${DEST_DATASET}" \
      --dest_table="chat_messages_copied" \
      --source_region="${SOURCE_REGION}" \
      --dest_region="${DEST_REGION}"
    ;;
  4)
    echo -e "\n>>> Running BigQuery DTS Dataset Copy Test..."
    "${SCRIPT_DIR}/test_dts.sh"
    ;;
  5)
    echo -e "\n>>> Running Cleanup..."
    "${SCRIPT_DIR}/cleanup.sh"
    ;;
  0)
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "Invalid option: ${ACTION}" >&2
    exit 1
    ;;
esac
