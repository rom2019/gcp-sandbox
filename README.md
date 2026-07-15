# gcp-sandbox

Google Cloud Platform(GCP) 인프라, 네트워크, GKE 멀티클러스터, AI 서비스 연동 및 CI/CD 실습 프로젝트 모음입니다.

## 📂 프로젝트 목록

| 카테고리 | 프로젝트 경로 | 설명 | 주요 기술 및 구성요소 |
| :--- | :--- | :--- | :--- |
| **Gemini Enterprise App** | [`gemini-enterprise-app/custom-domain`](./gemini-enterprise-app/custom-domain) | Gemini Enterprise App에 커스텀 도메인을 연결하고 HTTP→HTTPS 리디렉션 및 URL Map 경로 라우팅 구성 | Global External Load Balancer, Managed SSL, Internet NEG, Terraform |
| **GKE** | [`gke/fleet-multiqueue`](./gke/fleet-multiqueue) | GKE Fleet Hub & Kueue MultiKueue 기반 온프레미스 AI 배치 작업의 GCP GKE GPU 워커 클러스터 자동 버스팅 (Hybrid Cloud Bursting) | GKE Fleet, Kueue MultiKueue, HA VPN, Cloud NAT, Terraform |
| **Networking** | [`networking/gcs-custom-domain-hosting`](./networking/gcs-custom-domain-hosting) | GCS 정적 웹사이트를 Cloud CDN 및 Global External Load Balancer와 연동하여 커스텀 도메인 정적 호스팅 구축 | GCS, Cloud CDN, External Load Balancer, Managed SSL, Terraform |
| **Networking** | [`networking/github-to-gcs-cdn-deployer`](./networking/github-to-gcs-cdn-deployer) | Workload Identity Federation(WIF) 기반 Keyless 인증을 활용하여 GitHub Actions에서 GCS 업로드 및 Cloud CDN 캐시 자동 무효화 CI/CD 구축 | GitHub Actions, WIF (Keyless Auth), GCS, Cloud CDN, Terraform |
