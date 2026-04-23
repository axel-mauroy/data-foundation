# --- Storage ---

output "erp_bucket_name" {
  description = "GCS bucket for ERP feed data"
  value       = google_storage_bucket.erp_feed.name
}

output "zenml_bucket_name" {
  description = "GCS bucket for ZenML pipeline artifacts"
  value       = google_storage_bucket.zenml_artifacts.name
}

# --- BigQuery (dbt) ---

output "bronze_dataset_id" {
  description = "BigQuery dataset for Bronze layer (dbt staging models)"
  value       = google_bigquery_dataset.bronze.dataset_id
}

output "silver_dataset_id" {
  description = "BigQuery dataset for Silver layer (dbt intermediate models)"
  value       = google_bigquery_dataset.silver.dataset_id
}

output "gold_dataset_id" {
  description = "BigQuery dataset for Gold layer (dbt marts, consumed by ZenML/BQML)"
  value       = google_bigquery_dataset.gold.dataset_id
}

# --- BigQuery (Verity) ---

output "verity_dev_dataset_id" {
  description = "BigQuery dataset for Verity dev (all layers in one dataset)"
  value       = google_bigquery_dataset.verity_dev.dataset_id
}

output "verity_prod_dataset_id" {
  description = "BigQuery dataset for Verity prod (all layers, strict governance)"
  value       = google_bigquery_dataset.verity_prod.dataset_id
}

# --- Service Accounts ---

output "data_platform_sa_email" {
  description = "Email of the dbt / Cloud Run service account"
  value       = google_service_account.data_platform_sa.email
}

output "verity_sa_email" {
  description = "Email of the Verity pipeline service account"
  value       = google_service_account.verity_sa.email
}
