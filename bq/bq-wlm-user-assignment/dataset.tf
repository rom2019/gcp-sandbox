########################################
# 데모용 BigQuery Dataset 및 Table
########################################
# Principal 기반 예약 라우팅 및 VIP ETL 서비스 계정 시연에 사용할
# 전용 데이터셋과 테이블을 프로비저닝합니다.

resource "google_bigquery_dataset" "demo" {
  project     = var.demo_project_id
  dataset_id  = "bq_wlm_demo"
  location    = var.reservation_location
  description = "BigQuery Workload Management / Reservation Principal Demo Dataset"

  # terraform destroy 시 포함된 테이블을 일괄 삭제
  delete_contents_on_destroy = true
}

# 1) 데모용 주문(Orders) 테이블
resource "google_bigquery_table" "sample_orders" {
  project    = var.demo_project_id
  dataset_id = google_bigquery_dataset.demo.dataset_id
  table_id   = "sample_orders"

  deletion_protection = false

  schema = jsonencode([
    {
      name        = "order_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "주문 고유 ID"
    },
    {
      name        = "customer_id"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "고객 ID"
    },
    {
      name        = "category"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "상품 카테고리"
    },
    {
      name        = "amount"
      type        = "NUMERIC"
      mode        = "NULLABLE"
      description = "주문 금액"
    },
    {
      name        = "order_timestamp"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "주문 일시"
    }
  ])
}

# 2) VIP ETL 결과 적재용 요약 테이블
resource "google_bigquery_table" "daily_summary" {
  project    = var.demo_project_id
  dataset_id = google_bigquery_dataset.demo.dataset_id
  table_id   = "daily_summary"

  deletion_protection = false

  schema = jsonencode([
    {
      name = "summary_date"
      type = "DATE"
      mode = "REQUIRED"
    },
    {
      name = "category"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "total_orders"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "total_revenue"
      type = "NUMERIC"
      mode = "NULLABLE"
    }
  ])
}
