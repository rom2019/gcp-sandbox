#!/usr/bin/env bash
# ==============================================================================
# Script Name: 04-run-demo-scenario.sh
# Description: Kueue MultiKueue 하이브리드 AI 클라우드 버스팅 데모 시나리오 전체 실행 스크립트
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

PROJECT_ID=$(gcloud config get-value project)
REGION="asia-northeast1"
ONPREM_CLUSTER="gke-onprem-manager"
CLOUD_CLUSTER="gke-cloud-worker"

CTX_ONPREM="gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER}"
CTX_CLOUD="gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER}"

echo "=== [4/4] Kueue MultiKueue Hybrid AI Simulation Demo 시나리오 구동 ==="

echo "0. 기존 실행 이력 Cleanup..."
kubectl --context "${CTX_ONPREM}" delete jobs --all --ignore-not-found
kubectl --context "${CTX_CLOUD}" delete jobs --all --ignore-not-found

echo "1. 온프레미스 및 클라우드 클러스터에 Kueue Queue 설정 적용..."
kubectl --context "${CTX_ONPREM}" apply -f "${MANIFESTS_DIR}/kueue-config/"
kubectl --context "${CTX_CLOUD}" apply -f "${MANIFESTS_DIR}/kueue-config-worker/"

sleep 3

echo ""
echo "온프레미스 매니저 클러스터의 현재 ClusterQueue 상태 확인:"
kubectl --context "${CTX_ONPREM}" get clusterqueue -o wide

sleep 3
echo ""
echo "2. 온프레미스 AI 배치 작업 1번 제출 (온프레미스 쿼터 범위 내: 4 Mock GPUs)..."
kubectl --context "${CTX_ONPREM}" apply -f "${MANIFESTS_DIR}/jobs/01-onprem-batch-job.yaml"

sleep 5
echo "--> 온프레미스 매니저 클러스터 Job 생성 상태:"
kubectl --context "${CTX_ONPREM}" get jobs

echo ""
echo "3. 클라우드 버스팅 AI 배치 작업 2번 제출 (온프레미스 쿼터 초과 시나리오)..."
kubectl --context "${CTX_ONPREM}" apply -f "${MANIFESTS_DIR}/jobs/02-cloud-burst-job.yaml"

echo "Kueue MultiKueue 원격 디스패치(Remote Dispatching)를 위한 15초 대기..."
sleep 15

echo ""
echo "--> 온프레미스 매니저 Workload 큐 처리 상태:"
kubectl --context "${CTX_ONPREM}" get workloads

echo ""
echo "4. GKE Cloud Worker 클러스터로 원격 디스패치(Remote Dispatched)된 실재 작업 확인:"
echo "--- Remote Jobs in Cloud Worker ---"
kubectl --context "${CTX_CLOUD}" get jobs
echo "--- Remote Pods in Cloud Worker ---"
kubectl --context "${CTX_CLOUD}" get pods

echo ""
echo "=== [성공] Kueue MultiKueue 하이브리드 버스팅 데모가 성공적으로 완료되었습니다! ==="
