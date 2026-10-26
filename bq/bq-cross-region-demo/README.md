# BigQuery Cross-Region Data Replication & Copy Solution Comparison

이 저장소는 Google Cloud BigQuery의 3대 리전 간(Cross-Region) 데이터 이동 및 복제 솔루션(**1. BigQuery DTS**, **2. Cross-Region Table Copy**, **3. BigQuery CRR**)을 아키텍처·비용·운영(RPO/RTO) 관점에서 비교 분석하고, 실제 GCP 환경에서 즉시 검증 및 고객 시연을 수행할 수 있도록 구성된 통합 데모 패키지입니다.

---

## 1. 솔루션 요약 및 비교

| 솔루션 | 출시 상태 | 복제 단위 | 권장 Usecase | 비용 특성 |
| :--- | :--- | :--- | :--- | :--- |
| **BigQuery CRR**<br>*(Cross-Region Replication)* | **GA** | 데이터셋 | • **재해 복구(DR) 및 상시 BCP**<br>• 멀티 리전 현지 읽기 복제본(Read Replica)<br>• 무중단 리전 이전 | 변경된 압축 블록(Delta) Egress ($0.02~$0.08/GiB) + 대상 스토리지 요금 |
| **Cross-Region Table Copy** | **Preview** | 테이블 | • **배치 파이프라인 연계 특정 테이블 선별 전송**<br>• 일별 정산/집계 테이블 리전 복사<br>• 일회성 테이블/스냅샷 이전 | 선택 테이블 전체 Egress ($0.02~$0.08/GiB) + 대상 스토리지 요금 (Compute 무료) |
| **BigQuery DTS**<br>*(Dataset Copy)* | **Beta** | 데이터셋 | • **12시간 이상 주기의 비실시간 일괄 백업**<br>• 코드 없는 콘솔 UI 기반 동기화 | 변경 테이블 전체 Egress 요금 + 대상 스토리지 요금 (변경 시 테이블 전체 덮어쓰기) |

> 📄 **상세 분석 보고서:** [`BQ_CROSS_REGION_SOLUTION_COMPARISON.md`](./BQ_CROSS_REGION_SOLUTION_COMPARISON.md)를 참고하십시오.

---

## 2. 디렉토리 구조

```
bq-cross-region-demo/
├── README.md                              # 본 빠른 시작 가이드
├── BQ_CROSS_REGION_SOLUTION_COMPARISON.md # 3대 솔루션 심층 비교 분석 보고서
├── ui/
│   ├── index.html                         # 실시간 GCP 연동 웹 비교 대시보드 UI
│   └── server.py                          # BigQuery CLI/API 연동 로컬 데모 웹 서버
├── sql/
│   ├── 01_setup_sample_data.sql           # 실시간 이벤트 샘플 테이블 및 데이터 생성 (10,000건)
│   ├── 02_dts_verification.sql            # DTS 실행 상태 및 정합성 검증 SQL
│   ├── 03_table_copy_verification.sql     # Cross-Region Table Copy 검증 SQL
│   └── 04_crr_lifecycle.sql               # CRR 복제본 생성, 동기화 모니터링, 승격, Failover, 삭제 DDL
└── scripts/
    ├── run_all_tests.sh                   # 대화형 마스터 테스트 오케스트레이터
    ├── setup_environment.sh               # 소스/대상 데이터셋 생성 및 초기 데이터 주입
    ├── test_crr.sh                        # CRR 셋업, 동기화 모니터링, 읽기 검증 스크립트
    ├── test_table_copy.py                 # Python SDK 기반 크로스 리전 테이블 복사 및 성능 측정
    ├── test_dts.sh                        # bq CLI 기반 DTS 데이터셋 복사 설정 및 실행
    └── cleanup.sh                         # 테스트 완료 후 생성된 리소스 안전 삭제 스크립트
```

---

## 3. 빠른 시작 및 테스트 실행 방법

### 사전 요구사항
1. `gcloud` CLI 인증 (`gcloud auth login` 및 기본 프로젝트 설정 `gcloud config set project <YOUR_PROJECT_ID>`)
2. BigQuery 관련 IAM 권한:
   - `roles/bigquery.admin` 또는 `roles/bigquery.dataEditor` 및 `roles/bigquery.jobUser`
   - DTS 사용 시 `roles/bigquery.transfers.update`

### 방법 1: 인터랙티브 웹 데모 대시보드 실행 (권장)
```bash
export PROJECT_ID="your-gcp-project-id"
python3 ./ui/server.py
# 브라우저에서 http://localhost:8080 접속
```
- **1. 전체 초기 동기화 (Sync All)**: 미국 원본(`demo_source_us`) 생성 및 서울 3개 목적지(`demo_dest_dts_kr`, `demo_dest_copy_kr`, `demo_dest_crr_kr`) 초기 동기화 실행
- **2. 원본에 +500건 추가 (증분 테스트)**: 원본에만 `+500건` INSERT 후 CRR의 무작업 자동 반영과 DTS / Table Copy의 수동 명령어(`▶️ DTS 수동 실행`, `▶️ bq cp 수동 실행`) 비교 시연
- **🧹 리소스 초기화**: 데모 데이터 `10,000건` 초기화 또는 GCP 리소스 전체 삭제(Cleanup)

### 방법 2: 대화형 마스터 스크립트 실행
```bash
export PROJECT_ID="your-gcp-project-id"
export SOURCE_REGION="us-central1"
export DEST_REGION="asia-northeast3" # 서울 리전

./scripts/run_all_tests.sh
```

### 방법 3: 개별 단계 스크립트 실행

1. **환경 초기화 및 샘플 데이터 적재:**
   ```bash
   ./scripts/setup_environment.sh
   ```
   - Source 리전(`us-central1`)에 `demo_source_us` 데이터셋 생성
   - 파티셔닝/클러스터링 적용된 `chat_messages` (10,000건) 및 `daily_channel_summary` 생성
   - Target 리전(`asia-northeast3`)에 솔루션별 목적지 데이터셋 3종 생성: `demo_dest_dts_kr`(DTS용), `demo_dest_copy_kr`(Table Copy용), `demo_dest_crr_kr`(웹 UI 데모용 뷰 저장소)

2. **솔루션 1: BigQuery CRR (Cross-Region Dataset Replication) 테스트:**
   ```bash
   ./scripts/test_crr.sh
   ```

3. **솔루션 2: Cross-Region Table Copy 테스트:**
   ```bash
   python3 ./scripts/test_table_copy.py \
     --project_id="${PROJECT_ID}" \
     --source_dataset="demo_source_us" \
     --source_table="chat_messages" \
     --dest_dataset="demo_dest_copy_kr" \
     --dest_table="chat_messages" \
     --source_region="us-central1" \
     --dest_region="asia-northeast3"
   ```

4. **솔루션 3: BigQuery DTS (Dataset Copy) 테스트:**
   ```bash
   ./scripts/test_dts.sh
   ```

5. **테스트 리소스 정리 (Cleanup):**
   ```bash
   ./scripts/cleanup.sh
   ```
