#!/usr/bin/env bash
# ==============================================================================
# Script Name: 01-setup-infra.sh
# Description: GCP Terraform 기반 온프레미스 시뮬레이션 VPC 및 Cloud VPC 인프라 생성
# ==============================================================================
set -euo pipefail

echo "=== [1/4] Terraform을 이용한 하이브리드 인프라 생성 시작 ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

cd "${TERRAFORM_DIR}"

# 인자값으로 GCP Project ID가 전달된 경우 main.tf 내 프로젝트 ID 자동 변경
if [ "${1:-}" != "" ]; then
  PROJECT_ID="$1"
  echo "[안내] GCP Project ID를 '${PROJECT_ID}'로 설정합니다."
  sed -i.bak "s/YOUR_PROJECT_ID/${PROJECT_ID}/g" main.tf || true
fi

# Terraform 초기화 및 GCP 인프라(VPC, GKE Private Clusters, HA VPN, Cloud NAT) 생성
echo "[실행] Terraform 초기화 진행 중..."
terraform init

echo "[실행] Terraform 리소스 프로비저닝 자동 승인 진행..."
terraform apply -auto-approve

echo "=== [성공] Terraform 하이브리드 인프라 설정이 완료되었습니다! ==="
