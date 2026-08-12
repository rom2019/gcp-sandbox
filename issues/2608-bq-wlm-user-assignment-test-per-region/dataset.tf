########################################
# 리전별 데모용 BigQuery Dataset 및 Table
########################################
# var.regions 에 정의된 각 리전에 테스트용 데이터셋과 테이블을 프로비저닝합니다.
# BigQuery의 데이터셋 ID는 프로젝트 내에서 고유해야 하므로 리전명을 접미사로 붙입니다.

resource "google_bigquery_dataset" "demo" {
  for_each = var.create_demo_dataset ? toset(var.regions) : toset([])

  project     = var.project_id
  dataset_id  = "${var.dataset_prefix}_${replace(lower(each.key), "-", "_")}"
  location    = each.key
  description = "BigQuery Workload Management Demo Dataset in ${each.key}"

  # terraform destroy 시 포함된 테이블을 일괄 삭제
  delete_contents_on_destroy = true
}

# 1) 리전별 데모용 주문(Orders) 테이블
resource "google_bigquery_table" "sample_orders" {
  for_each = google_bigquery_dataset.demo

  project    = var.project_id
  dataset_id = each.value.dataset_id
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

# 2) 리전별 VIP ETL 결과 적재용 요약 테이블
resource "google_bigquery_table" "daily_summary" {
  for_each = google_bigquery_dataset.demo

  project    = var.project_id
  dataset_id = each.value.dataset_id
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
