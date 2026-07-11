#!/usr/bin/env bash
# ==============================================================================
# Script Name: 04-patch-mock-gpu.sh
# Description: 실제 expensive GPU 없이 시뮬레이션하기 위한 extended resource (example.com/mock-gpu) 노드 패치
# ==============================================================================
set -euo pipefail

echo "=== [3/4] Kubernetes 노드 대상 example.com/mock-gpu 커스텀 자원 용량 주입 시작 ==="

PROJECT_ID=$(gcloud config get-value project)
REGION="asia-northeast1"
ONPREM_CLUSTER="gke-onprem-manager"
CLOUD_CLUSTER="gke-cloud-worker"

# 노드의 status/capacity 및 status/allocatable 영역에 example.com/mock-gpu 수치 동적 주입함수
patch_nodes() {
  local context=$1
  local count=$2
  echo "[진행] Context: ${context} 내 노드들에 mock-gpu=${count} 개 패치 중..."
  
  NODES=$(kubectl --context "${context}" get nodes -o jsonpath='{.items[*].metadata.name}')
  for node in ${NODES}; do
    echo "  -> 노드 패치 적용: ${node}"
    kubectl --context "${context}" patch node "${node}" --subresource=status --type='json' \
      -p="[{\"op\": \"add\", \"path\": \"/status/capacity/example.com~1mock-gpu\", \"value\": \"${count}\"}, {\"op\": \"add\", \"path\": \"/status/allocatable/example.com~1mock-gpu\", \"value\": \"${count}\"}]" || true
  done
}

# 온프레미스 매니저 노드들에는 총 4개 mock-gpu 주입
patch_nodes "gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER}" "4"

# 클라우드 워커 노드들에는 대용량 16개 mock-gpu 주입
patch_nodes "gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER}" "16"

echo "=== [성공] example.com/mock-gpu 커스텀 GPU 패치가 성공적으로 완료되었습니다! ==="
