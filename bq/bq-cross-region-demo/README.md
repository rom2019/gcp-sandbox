# Sendbird BigQuery Cross-Region Solution Comparison & Test Suite

이 디렉토리는 **Sendbird (센드버드)** 고객사에게 Google Cloud BigQuery의 3대 크로스 리전 데이터 이동 및 복제 솔루션을 비교 분석하고, 실제 환경에서 직접 검증 및 시연할 수 있도록 구축된 통합 테스트 패키지입니다.

---

## 1. 솔루션 요약 및 비교

| 솔루션 | 출시 상태 | 복제 단위 | 권장 Usecase | 비용 특성 |
| :--- | :--- | :--- | :--- | :--- |
| **BigQuery CRR**<br>*(Cross-Region Replication)* | **GA** | 데이터셋 | • **재해 복구(DR) 및 상시 BCP**<br>• 멀티 리전 현지 읽기 복제본(Read Replica)<br>• 무중단 리전 이전 | 복제 Egress ($0.02~$0.08/GiB, 압축 기준) + 대상 스토리지 요금 |
| **Cross-Region Table Copy** | **Preview** | 테이블 | • **배치 파이프라인 연계 특정 테이블 선별 전송**<br>• 일별 정산/집계 테이블 리전 복사<br>• 일회성 테이블/스냅샷 이전 | 전송 Egress ($0.02~$0.08/GiB) + 대상 스토리지 요금 (Compute 무료) |
| **BigQuery DTS**<br>*(Dataset Copy)* | **Beta** | 데이터셋 | • **12시간 이상 주기의 비실시간 일괄 백업**<br>• 코드 없는 콘솔 UI 기반 동기화 | 일반 Egress 요금 + 대상 스토리지 요금 (변경 시 테이블 전체 Truncate) |

> 📄 **상세 분석 보고서:** [`SENDBIRD_BQ_SOLUTION_COMPARISON.md`](./SENDBIRD_BQ_SOLUTION_COMPARISON.md)를 참고하십시오.

---

## 2. 디렉토리 구조

```
sendbird_solutions/
├── README.md                           # 본 빠른 시작 가이드
├── SENDBIRD_BQ_SOLUTION_COMPARISON.md  # 3대 솔루션 심층 비교 분석 보고서
├── sql/
│   ├── 01_setup_sample_data.sql        # Sendbird 모사 채팅 이벤트 샘플 테이블 및 데이터 생성
│   ├── 02_dts_verification.sql         # DTS 실행 상태 및 정합성 검증 SQL
│   ├── 03_table_copy_verification.sql  # Cross-Region Table Copy 검증 SQL
│   └── 04_crr_lifecycle.sql            # CRR 복제본 생성, 동기화 모니터링, 승격, Failover, 삭제 DDL
└── scripts/
    ├── run_all_tests.sh                # 대화형 마스터 테스트 오케스트레이터
    ├── setup_environment.sh            # 소스/대상 데이터셋 생성 및 초기 데이터 주입
    ├── test_crr.sh                     # CRR 셋업, 동기화 모니터링, 읽기 검증 스크립트
    ├── test_table_copy.py              # Python SDK 기반 크로스 리전 테이블 복사 및 성능 측정
    ├── test_dts.sh                     # bq CLI 기반 DTS 데이터셋 복사 설정 및 실행
    └── cleanup.sh                      # 테스트 완료 후 생성된 리소스 안전 삭제 스크립트
```

---

## 3. 빠른 시작 및 테스트 실행 방법

### 사전 요구사항
1. `gcloud` CLI 인증 (`gcloud auth login` 또는 서비스 계정 키)
2. BigQuery 관련 IAM 권한:
   - `roles/bigquery.admin` 또는 `roles/bigquery.dataEditor` 및 `roles/bigquery.jobUser`
   - DTS 사용 시 `roles/bigquery.transfers.update`

### 단계별 실행

#### 방법 1: 대화형 마스터 스크립트 실행 (권장)
```bash
export PROJECT_ID="your-gcp-project-id"
export SOURCE_REGION="us-central1"
export DEST_REGION="asia-northeast3" # 서울 리전

./scripts/run_all_tests.sh
```

#### 방법 2: 개별 단계 실행

1. **환경 초기화 및 샘플 데이터 적재:**
   ```bash
   ./scripts/setup_environment.sh
   ```
   - Source 리전(`us-central1`)에 `sendbird_source_us` 데이터셋 생성
   - 파티셔닝/클러스터링 적용된 `chat_messages` (10,000건) 및 `daily_channel_summary` 생성
   - Target 리전(`asia-northeast3`)에 솔루션별 목적지 데이터셋 3종 생성: `sendbird_dest_dts_kr`(DTS용), `sendbird_dest_copy_kr`(Table Copy용), `sendbird_dest_crr_kr`(웹 UI 데모용 뷰 저장소)

2. **솔루션 1: BigQuery CRR (Cross-Region Dataset Replication) 테스트:**
   ```bash
   ./scripts/test_crr.sh
   ```
   - DDL을 통해 서울 리전에 Replica 생성
   - `INFORMATION_SCHEMA.SCHEMATA_REPLICAS` 조회하여 동기화 상태 및 복제 지연 확인
   - 서울 리전에서 Read-only 분석 쿼리 수행
   - Failover(승격) 및 Revert 명령 가이드 제공

3. **솔루션 2: Cross-Region Table Copy 테스트:**
   ```bash
   python3 ./scripts/test_table_copy.py \
     --project_id="${PROJECT_ID}" \
     --source_dataset="sendbird_source_us" \
     --source_table="chat_messages" \
     --dest_dataset="sendbird_dest_copy_kr" \
     --dest_table="chat_messages_copied" \
     --source_region="us-central1" \
     --dest_region="asia-northeast3"
   ```
   - Python BigQuery SDK의 `copy_table` 비동기 작업 실행
   - 전송 소요 시간 및 초당 전송 처리량(MB/s) 출력
   - 원본과 복사본 테이블의 Row 수 일치 여부 정합성 검증

4. **솔루션 3: BigQuery DTS (Dataset Copy) 테스트:**
   ```bash
   ./scripts/test_dts.sh
   ```
   - Data Transfer Service를 통한 크로스 리전 데이터셋 복사 구성
   - 수동 전송(Transfer Run) 트리거 및 상태 모니터링

5. **테스트 리소스 정리 (Cleanup):**
   ```bash
   ./scripts/cleanup.sh
   ```
   - CRR Replica 제거, DTS 전송 설정 삭제, 생성된 테스트 데이터셋 삭제를 일괄 수행하여 불필요한 과금 방지.
