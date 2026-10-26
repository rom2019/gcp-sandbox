# 📊 BigQuery 크로스 리전 아키텍처 가이드 & 3대 솔루션 비교 (Fact-Checked Slides)

> [!TIP]
> **전달해주신 캡처 이미지(의사결정 트리 & 3단 비교 카드)와 동일한 시각적 디자인의 16:9 슬라이드 덱**은 아래 두 곳에서 즉시 확인 및 PDF 출력이 가능합니다:
> - **인터랙티브 슬라이드 아티팩트**: [BigQuery_CrossRegion_Architecture_Slides.html](file:///usr/local/google/home/romij/.gemini/jetski/brain/393edae4-a545-4123-a6e0-fdaf86fcce39/BigQuery_CrossRegion_Architecture_Slides.html)
> - **라이브 웹 슬라이드 뷰어 (16:9 PDF 인쇄 지원)**: `http://romij.c.googlers.com:8080/slides.html`

---

## Slide 1. BigQuery 크로스 리전 아키텍처 선택 가이드 (Decision Tree)
**5개 질문으로 끝내는 기술 선정 · Decision Tree for Cross-Region Data Movement**

| 단계 | 핵심 질문 (Decision Question) | 분기 | 선택 아키텍처 및 핵심 사양 (팩트체크 반영본) | 출시 단계 |
| :---: | :--- | :---: | :--- | :---: |
| **Q1** | **대상 리전에 데이터를 영구 저장해야 하는가?** | **NO →** | **🔴 Global Queries (Cross-Region SQL)**<br>• 사전 복제 없이 즉시 조인 *(실행 시 원격 서브쿼리 결과를 Primary 임시 테이블로 전송·24h 보관, 복제 네트워크+스토리지 과금)*<br>• `ALTER PROJECT SET OPTIONS`로 실행(`enable_global_queries_execution`) 및 데이터 접근(`enable_global_queries_data_access`) 사전 활성화 필수<br>• 단일 Copy Job당 최대 **100 GB** 전송 상한 (리전당 원격 테이블 최대 10개) | **`PREVIEW`** |
| **Q2** | **타겟 리전에서 쓰기·가공 없이 읽기 전용 소비로 충분한가?**<br>*(DR 목적이 아니어도 무방)* | **YES →** | **⚪ Dataset Replication (CRR) 계열로 진입**<br>• DR뿐 아니라 **읽기 전용 리전 집결(Co-location)** 용도로도 유효 (모든 에디션/On-demand에서 읽기 가능)<br>• Secondary는 승격(Failover) 전까지 엄격한 Read-Only **→ Q3에서 티어 결정** | **`GA`** |
| **Q3** | **Primary 전면 장애(Outage) 시 즉각 Failover(Hard Failover) 및 15분 RPO·5분 RTO가 필수인가?**<br>*(금융 · 미션 크리티컬 기준)* | **YES →** | **🟢 Managed Disaster Recovery — Turbo Replication 기반**<br>• **15분 RPO · 5분 RTO 목표** (조직/리전당 5 GiBps 대역폭 쿼터 내) · Primary 장애 시 **Hard Failover** 지원<br>• **Enterprise Plus 에디션 예약 필수** & **동일 권역(`US` 내, `EU` 내 등) 리전 페어 한정 (`US↔KR` 불가)** | **`GA`** |
| **Q3** | *(상동)* | **NO →** | **🟢 Cross-Region Dataset Replication — Standard CRR**<br>• 연속 비동기 블록 델타 복제 · **에디션/대륙 무관 (`US↔KR` 가능)**<br>• **※주의: Primary 리전이 정상 가동 중일 때만 승격(Soft Promotion) 가능** (Primary 완전 다운 시 승격 불가) | **`GA`** |
| **Q4** | **데이터셋 전체 단위 정기 스케줄 배치 복사인가?** | **YES →** | **🔵 BigQuery Data Transfer Service (DTS — Copy Datasets)**<br>• 데이터셋 단위 스케줄 배치 (**최소 주기 12시간**, 크로스 리전 1회 Run당 **최대 1,000개 테이블**, 미변경 테이블 스킵)<br>• Pub/Sub · Email 알림 연동 · **타겟 내 별도 가공 테이블 Write 가능** *(※복제된 원본 테이블 직접 수정 시 다음 배치에 데이터·스키마 덮어써짐)* | **`BETA`** |
| **Q5** | **단일 테이블 물리 크기가 1 TiB 미만(상한 20 TiB)인가?**<br>*(단일 테이블 1:1 스냅샷 이관)* | **YES →** | **🟡 Native Table Copy (CRTC) · `bq cp`**<br>• 단일 테이블 1회성 애드혹 이관 (CLI/API 전용, 콘솔 UI/SQL 미지원)<br>• 퍼블릭 문서상 물리 20 TiB 상한(1 TiB+ 다중 재시도 필요) · *※내부 백엔드는 CRR 기반 최대 30 TB·1 Gbps 엔진으로 롤아웃 완료* | **`PREVIEW`** |
| **Q5** | *(상동)* | **NO →** | **⚫ CRR 일시 적용 후 Replica 분리 (또는 GCS Export → STS → BQ Load)**<br>• 초대형 테이블을 스키마/시간 정밀도 손실 없이 이관할 때는 **CRR 무중단 백필 완료 후 Replica 분리**가 가장 안전 | **`1 TiB+`** |

> **💡 DECISION RULE**: 갈림길은 **타겟에서 쓰기가 필요한가** — 불필요하면 **CRR**(`대륙 무관 Standard CRR` / `Enterprise+ Managed DR`), 필요하면 **DTS**(`데이터셋 정기 배치, Beta`) 또는 **CRTC**(`단일 테이블 1회성, Preview`) · 초대형 이관은 **CRR 일시 백필 후 분리**

---

## Slide 2. 3대 솔루션 상세 비교 (Continuous vs Scheduled vs Ad-hoc)

| 구분 | 🟢 1. Dataset Replication (`CRR & Managed DR`) | 🔵 2. Data Transfer Service (`cross_region_copy`) | 🟡 3. Native Table Copy (`bq cp`, `CRTC`) |
| :--- | :--- | :--- | :--- |
| **복제 방식** | **연속 복제 (Continuous)** — 스토리지 레벨 Active-Passive | **배치 복제 (Scheduled)** — 데이터셋 단위 스케줄 배치 | **단발 복사 (Ad-hoc)** — 단일 테이블 1:1 스냅샷 복사 |
| **핵심 배지** | `GA` · `Managed DR: 15분 RPO·5분 RTO` · `Secondary Read-Only` | `BETA` · `최소 주기 12h (수동 실행 가능)` · `별도 테이블 Write 가능` | `PREVIEW` · `공식 20 TiB 상한 (1 TiB+ 재시도)` · `타겟 Write 가능` |
| **장점 (+)** | • **복제 작업(Job) 계층 자체가 없음** — PENDING 고착·취소 문제 구조적 제거<br>• **블록 단위 델타 복제** — 대형 파티션 테이블일수록 Egress 대폭 절감 *(※날짜 샤딩 구조는 DTS도 변경 샤드만 복사해 DTS 대비 절감 격차 축소)*<br>• 복제에 **쿼리 슬롯 0 소모** (Colossus 스토리지 전담)<br>• **Managed DR(Enterprise+)** 구성 시 RTO 5분 내 승격 · 멀티리전 10 PB / 단일 리전 500 TB+ 확장<br>• `dataset_staleness` 지표로 복제 지연 실시간 관측 | • 데이터셋 내 테이블 **일괄 스케줄 동기화** (크로스 리전 1회 Run 최대 1,000개 테이블, 미변경 테이블 자동 스킵)<br>• 타겟이 **독립 일반 데이터셋** — 타겟 내 별도 파생 테이블 생성 및 DML·DDL·변환 자유<br>• Email · Pub/Sub 알림 연동 기본 내장, 서버리스 스케줄 관리 | • 명령어 **1줄(`bq cp`)로 단일 테이블 즉시 실행**, 학습·구축 비용 최소<br>• 타겟은 **완전 독립 테이블** — 복제 직후 즉시 쓰기(DML/DDL)·스키마 변경·가공 가능<br>• 필요한 테이블만 골라 일회성 Egress 발생 (일 최대 2,000 Copy Jobs / 테이블당 100회) |
| **단점 (−)** | • Secondary는 승격 전까지 **엄격한 Read-Only** *(Standard CRR은 Primary 생존 시에만 승격 가능, Primary 장애 시 Hard Failover는 Managed DR 전용)*<br>• **Policy Tag 및 연결된 Data Policy**는 복제 제외<br>• **스트리밍(Write API/insertAll) · CDC 적재**는 복제가 Best-Effort<br>• 대상 리전 **KMS(CMEK) 듀얼 프로비저닝(`replica_kms_key`)** 필수 및 BigLake/Fine-grained DML 미지원 | • **Copy datasets 기능은 현재 Beta** (`26Q4~27Q1` GA 목표) 및 개별 테이블 선택 필터 미지원<br>• 변경된 테이블은 **전체 재전송(Truncate & Replace)** — 행 단위 증분 아님 *(※복제본 직접 수정 시 다음 배치에 데이터·스키마 덮어써짐)*<br>• **하위 Copy Job 일괄 취소 미흡** — Pending 고착 시 개별 `bq cancel` 대응 필요<br>• **뷰(View) · 루틴(UDF) · 외부(External) 테이블** 및 **CDC · Policy Tag 테이블** 복사 불가 | • **퍼블릭 문서상 Preview 상태** — 공식 SLA 미보장 *(※내부 백엔드는 26년 7월 CRR 엔진 기반 최대 30 TB·1 Gbps로 전환 완료)*<br>• **작업 완료 전 취소(`bq cancel`) 시에도 과금 부과** — 이미 전송된 데이터에 대한 복제 요금 청구됨<br>• 공식 문서상 **물리 20 TiB 초과 복사 불가** (1 TiB 초과 시 다중 재시도 필요)<br>• **Cloud Console UI 및 SQL(`CREATE TABLE COPY`) 미지원** (CLI/API 전용), Append 및 Policy Tag 복사 불가 |
| **BEST FIT** | **미션 크리티컬 DR + 읽기 전용 리전 집결(Co-location)** | **데이터 메시 일일 배치 공유 · 가공형 스테이징** | **개발·PoC 환경의 소규모/단일 테이블 선별 이관** |

---

## Slide 3. 항목별 팩트체크 교정 내역 및 공식 근거 링크

| 구분 | 기존 초안의 부정확/오해 소지 표현 | 교정된 정확한 팩트 | 공식 문서 및 사내 근거 링크 |
| :--- | :--- | :--- | :--- |
| **Q1. Global Queries** | • `복제 없이 즉시 조인`<br>• `SET @@location 지정`만 언급 | • 실행 시 원격 서브쿼리 결과를 **Primary 리전 임시 테이블로 전송·24시간 보관**하며 **복제 전송비 + 24h 스토리지 과금** 발생<br>• `ALTER PROJECT SET OPTIONS` 사전 활성화 필수, 단일 Copy Job당 **100 GB** 상한 | • [Global queries 공식 문서](https://cloud.google.com/bigquery/docs/global-queries)<br>• [Query jobs Quotas (100 GB)](https://cloud.google.com/bigquery/quotas#query_jobs) |
| **Q2 & Q3. CRR vs Managed DR** | • Q2 배지 `[CRR]` 표기<br>• `Dataset Replication — Turbo Mode`<br>• `Standard Mode = 비용 최적화 DR` | • Q2 배지를 출시 단계인 **`[GA]`**로 통일<br>• 15분 RPO·5분 RTO 및 Primary 장애 시 **Hard Failover는 `Managed DR (Enterprise Plus 필수, 동일 권역 페어 한정)` 전용**<br>• **Standard CRR은 Primary 생존 시에만 승격(Soft Promotion) 가능**하며 Primary 전면 장애 시 승격 불가 | • [Managed disaster recovery](https://cloud.google.com/bigquery/docs/managed-disaster-recovery)<br>• [CRR vs DR 기능 차이 비교표](https://cloud.google.com/bigquery/docs/disaster-recovery-migration)<br>• [Cross-region dataset replication](https://cloud.google.com/bigquery/docs/data-replication) |
| **Q4 & Card 2. DTS Dataset Copy** | • 배지 `[GA]` 표기<br>• `데이터셋·테이블 단위`<br>• `타겟이 독립 테이블 — DML·DDL 자유` | • 크로스 리전 `Copy datasets`는 공식 문서상 **`[BETA]`** (사내 `b/440110440`, 26Q4~27Q1 GA 목표)<br>• **데이터셋 단위만 가능**(개별 테이블 선택 불가), **최소 주기 12시간**, 1회 Run 최대 1,000 테이블<br>• 복제본 직접 수정 시 다음 배치에 **Truncate & Replace로 유실**되므로 별도 테이블 가공 필수 | • [Copy datasets (Beta 명시)](https://cloud.google.com/bigquery/docs/managing-datasets#copy-datasets)<br>• [Dataset copy 1,000 테이블 쿼터](https://cloud.google.com/bigquery/quotas#copy_jobs)<br>• 사내: `b/440110440`, `b/486235839` |
| **Q5 & Card 3. Native Table Copy** | • `일회성 Egress만 발생, bq cancel로 중단 용이`<br>• `물리 1 TiB 초과 시 ~10% 실패율 — GA 보류` | • **작업 완료 전 `bq cancel`로 취소하더라도 기전송된 데이터에 대한 크로스 리전 복제 요금 부과됨**<br>• 퍼블릭 문서는 **물리 20 TiB 상한(1 TiB 초과 시 다중 재시도 필요)**으로 명시<br>• 내부적으로는 **신형 CRR 기반 CRTC 엔진(최대 30 TB, 1 Gbps 보장)**이 26년 7월 Wave 5 롤아웃 완료 | • [Copy tables across regions (취소 시 과금 경고)](https://cloud.google.com/bigquery/docs/managing-tables#copy_tables_across_regions)<br>• [Table copy Limitations (20 TiB)](https://cloud.google.com/bigquery/docs/managing-tables#limitations)<br>• 사내: `launch/4364631`, `b/214591611` |
