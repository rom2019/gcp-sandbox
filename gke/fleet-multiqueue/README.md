# GKE Fleet Hub & Kueue MultiKueue 기반 하이브리드 AI GPU 클라우드 버스팅 (Hybrid Cloud Bursting)

이 프로젝트는 **GKE Fleet Hub**와 **Kubernetes Kueue MultiKueue**를 사용하여 온프레미스 AI 시뮬레이션 VPC 환경에서 발생한 대규모 AI 배치 작업(Batch Jobs)을 **Cloud VPC의 GKE 워커 클러스터로 자동 원격 디스패치(Remote Dispatching/Cloud Bursting)**하는 하이브리드 멀티클러스터 아키텍처 실습입니다.

---

## 📐 아키텍처 개요 (Architecture)

```
                       ┌─────────────────────────────────────────────────────────┐
                       │                   GKE Fleet Hub                         │
                       └────────────────────────────┬────────────────────────────┘
                                                    │
             ┌──────────────────────────────────────┴──────────────────────────────────────┐
             ▼                                                                             ▼
 ┌───────────────────────┐                                                     ┌───────────────────────┐
 │  On-prem Manager VPC  │                                                     │    Cloud Worker VPC   │
 │ ┌───────────────────┐ │  HA VPN Tunnel / Secret Kubeconfig Cross-Cluster    │ ┌───────────────────┐ │
 │ │ gke-onprem-manager│ │ ══════════════════════════════════════════════════> │ │  gke-cloud-worker │ │
 │ │ (Manager Cluster) │ │                                                     │ │  (Worker Cluster) │ │
 │ └─────────┬─────────┘ │                                                     │ └─────────┬─────────┘ │
 │           │           │                                                     │           │           │
 │ ┌─────────┴─────────┐ │                                                     │ ┌─────────┴─────────┐ │
 │ │ Kueue MultiKueue  │ │                                                     │ │   Kueue Worker    │ │
 │ │ 쿼터: 4 Mock GPUs  │ │                                                     │ │  쿼터: 64 Mock GPUs │ │
 │ └───────────────────┘ │                                                     │ └───────────────────┘ │
 └───────────────────────┘                                                     └───────────────────────┘
```

1. **Manager Cluster (`gke-onprem-manager`)**:
   * 온프레미스 사설 VPC 환경 시뮬레이션.
   * 로컬 GPU 쿼터(`onprem-mock-gpu-flavor`) **4개** 보유.
   * 온프레미스 쿼터 초과 시 MultiKueue 기능으로 원격 클러스터로 자동 디스패치.
2. **Worker Cluster (`gke-cloud-worker`)**:
   * Google Cloud VPC 내에 위치한 버스팅 전용 GKE 워커 클러스터.
   * 대용량 클라우드 GPU 쿼터(`cloud-mock-gpu-flavor`) **64개** 보유.
3. **네트워크 & 통신**:
   * Cloud HA VPN으로 두 VPC 암호화 연결.
   * Cloud NAT를 통해 Private GKE 노드가 Container Registry에 정상 접근.

---

## 🛠️ 사전 준비 사항 (Prerequisites)

* **Google Cloud SDK (`gcloud`)**
* **Terraform (`>= 1.3.0`)**
* **`kubectl`**
* GCP Project IAM 권한: `Owner` 또는 `Kubernetes Engine Admin`, `Compute Admin`, `Service Account Admin`

---

## 🚀 단계별 실행 방법 (Step-by-Step Guide)

모든 자동화 스크립트는 `scripts/` 디렉터리에 위치해 있습니다.

### Step 1: 인프라 프로비저닝 (`01-setup-infra.sh`)
온프레미스/클라우드 VPC, GKE Private 클러스터 2개, HA VPN 및 Cloud NAT를 자동으로 프로비저닝합니다.

```bash
cd scripts/
./01-setup-infra.sh <YOUR_GCP_PROJECT_ID>
```

### Step 2: GKE Fleet 연동 및 Kueue MultiKueue 설정을 완료합니다 (`02-setup-fleet-kueue.sh`)
두 클러스터를 GKE Fleet에 등록하고, Kueue v0.10.1을 설치한 후 매니저가 워커를 원격 제어하기 위한 크로스 클러스터 Kubeconfig Secret을 생성합니다.

```bash
./02-setup-fleet-kueue.sh
```

### Step 3: Mock GPU extended resource 패치 (`04-patch-mock-gpu.sh`)
실제 비싼 GPU 물리 노드 없이 시뮬레이션하기 위해 노드의 status 영역에 `example.com/mock-gpu` 확장 자원 용량을 할당합니다.

```bash
./04-patch-mock-gpu.sh
```

### Step 4: 하이브리드 AI 버스팅 데모 시나리오 구동 (`04-run-demo-scenario.sh`)
시나리오를 제출하여 하이브리드 클라우드 버스팅 동작을 확인합니다.

```bash
./04-run-demo-scenario.sh
```

---

## 🧪 데모 시나리오 동작 원리

1. **Job 1 (`onprem-ai-simulation-01`) 제출**:
   * 요청: 4 Mock GPUs (Pod 2개 × 2 GPU)
   * 결과: 온프레미스 쿼터(4개) 범위 내이므로 온프레미스 매니저 클러스터에서 즉시 **Admitted & Running**
2. **Job 2 (`cloud-burst-ai-simulation-02`) 제출**:
   * 요청: 추가 4 Mock GPUs (Pod 2개 × 2 GPU)
   * 결과: 온프레미스 GPU 쿼터가 소진되었으므로 Kueue MultiKueue에 의해 **`gke-cloud-worker` 클러스터로 원격 디스패치(Remote Dispatched)**되어 클라우드 워커 클러스터에서 **Running**

---

## 🖥️ Kueue 모니터링 툴 추천

Kueue의 Job 및 Workload 대기열 상태를 편하게 감시할 수 있는 도구들입니다:

1. **`k9s` (터미널 대시보드 - 강추)**
   * 설치: `brew install k9s`
   * 사용: `:workloads`, `:clusterqueues`, `:multikueueclusters` 입력 후 실시간 대시보드 관찰
2. **`kubectl-kueue` (공식 CLI 플러그인)**
   * 설치: `kubectl krew install kueue`
   * 사용: `kubectl kueue get clusterqueue`, `kubectl kueue list workloads`
3. **Prometheus + Grafana Dashboard**
   * Kueue의 Metrics (`:8443`)를 수집하여 큐별 GPU 사용률 및 버스팅 현황 그래프 시각화

---

## 📂 파일 구조 설명 (Repository Structure)

```text
fleet-multiqueue/
├── README.md                          # 프로젝트 설명 문서
├── manifests/                         # Kubernetes & Kueue 매니페스트
│   ├── jobs/                          # AI 시뮬레이션 배치 Job 정의
│   │   ├── 01-onprem-batch-job.yaml
│   │   └── 02-cloud-burst-job.yaml
│   ├── kueue-config/                  # On-premise Manager 큐 및 MultiKueue 설정
│   │   ├── 00-kueue-manager-config.yaml
│   │   ├── 01-multikueue-cluster.yaml
│   │   ├── 02-cluster-queue-onprem.yaml
│   │   └── 99-kueue-deployment-override.yaml
│   └── kueue-config-worker/           # Cloud Worker 전용 Queue 설정
│       ├── 00-kueue-manager-config.yaml
│       ├── 01-worker-queue.yaml
│       └── 99-kueue-deployment-override.yaml
├── scripts/                           # 실행 자동화 쉘 스크립트
│   ├── 01-setup-infra.sh
│   ├── 02-setup-fleet-kueue.sh
│   ├── 04-patch-mock-gpu.sh
│   └── 04-run-demo-scenario.sh
└── terraform/                         # GCP 인프라 프로비저닝 코드
    ├── main.tf
    ├── vpc_onprem.tf
    ├── vpc_cloud.tf
    └── vpn_havpn.tf
```
