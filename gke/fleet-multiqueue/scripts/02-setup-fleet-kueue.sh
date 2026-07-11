#!/usr/bin/env bash
# ==============================================================================
# Script Name: 02-setup-fleet-kueue.sh
# Description: GKE Fleet 연동, Kueue v0.10.1 설치 및 MultiKueue 크로스 클러스터 인증 설정
# ==============================================================================
set -euo pipefail

echo "=== [2/4] GKE Fleet 등록 및 Kueue MultiKueue 크로스 클러스터 인증 설정 ==="

# 1. GCP 환경변수 및 클러스터 정보 설정
PROJECT_ID=$(gcloud config get-value project)
REGION="asia-northeast1"

ONPREM_CLUSTER="gke-onprem-manager"
CLOUD_CLUSTER="gke-cloud-worker"

echo "[1/4] 두 클러스터의 kubectl Kubeconfig 자격 증명 가져오기..."
gcloud container clusters get-credentials ${ONPREM_CLUSTER} --region ${REGION} --project ${PROJECT_ID}
gcloud container clusters get-credentials ${CLOUD_CLUSTER} --region ${REGION} --project ${PROJECT_ID}

echo "[2/4] GKE Fleet Hub에 온프레미스 매니저 및 클라우드 워커 클러스터 등록..."
gcloud container fleet memberships register ${ONPREM_CLUSTER} \
  --gke-cluster=${REGION}/${ONPREM_CLUSTER} \
  --enable-workload-identity || true

gcloud container fleet memberships register ${CLOUD_CLUSTER} \
  --gke-cluster=${REGION}/${CLOUD_CLUSTER} \
  --enable-workload-identity || true

echo "[3/4] 온프레미스 및 클라우드 클러스터 모두에 Kueue (v0.10.1) 설치..."
KUEUE_VERSION="v0.10.1"
kubectl --context gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER} apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml
kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_VERSION}/manifests.yaml

echo "[4/4] 온프레미스 매니저가 클라우드 워커 제어를 위한 MultiKueue Kubeconfig Secret 생성..."

# 4-1. Cloud Worker 클러스터 내 MultiKueue 전용 ServiceAccount 생성
kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} create serviceaccount kueue-multi-kueue-adapter -n kueue-system || true

# 4-2. ServiceAccount에 Cluster-Admin 권한 바인딩
kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} create clusterrolebinding kueue-multi-kueue-adapter-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kueue-system:kueue-multi-kueue-adapter || true

# 4-3. Kubernetes v1.24+ 호환 서비스 계정 토큰 Secret 생성
kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kueue-multi-kueue-adapter-token
  namespace: kueue-system
  annotations:
    kubernetes.io/service-account.name: kueue-multi-kueue-adapter
type: kubernetes.io/service-account-token
EOF

sleep 2

# 4-4. Cloud Worker 접속용 Token, APIServer 주소, CA certificate 추출
TOKEN=$(kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} get secret kueue-multi-kueue-adapter-token -n kueue-system -o jsonpath='{.data.token}' | base64 --decode)
SERVER=$(kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} config view --raw -o jsonpath='{.clusters[?(@.name=="gke_'${PROJECT_ID}'_'${REGION}'_'${CLOUD_CLUSTER}'")].cluster.server}')
CA=$(kubectl --context gke_${PROJECT_ID}_${REGION}_${CLOUD_CLUSTER} get secret kueue-multi-kueue-adapter-token -n kueue-system -o jsonpath='{.data.ca\.crt}')

# 4-5. 온프레미스가 읽을 Remote Kubeconfig 파일 임시 구성
cat <<EOF > /tmp/cloud-worker-kubeconfig.yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA}
    server: ${SERVER}
  name: cloud-worker-cluster
contexts:
- context:
    cluster: cloud-worker-cluster
    user: kueue-multi-kueue-adapter
  name: cloud-worker-context
current-context: cloud-worker-context
users:
- name: kueue-multi-kueue-adapter
  user:
    token: ${TOKEN}
EOF

# 4-6. 온프레미스 매니저 클러스터의 default 및 kueue-system 네임스페이스에 Kubeconfig Secret 주입
kubectl --context gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER} create secret generic cloud-worker-kubeconfig --from-file=kubeconfig=/tmp/cloud-worker-kubeconfig.yaml -n default --dry-run=client -o yaml | kubectl --context gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER} apply -f -
kubectl --context gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER} create secret generic cloud-worker-kubeconfig --from-file=kubeconfig=/tmp/cloud-worker-kubeconfig.yaml -n kueue-system --dry-run=client -o yaml | kubectl --context gke_${PROJECT_ID}_${REGION}_${ONPREM_CLUSTER} apply -f -

echo "=== [성공] Kueue MultiKueue 크로스 클러스터 인증망 설정이 성공적으로 완료되었습니다! ==="
