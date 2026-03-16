output "erp_bucket_name" {
  value = google_storage_bucket.erp_feed.name
}

output "zenml_bucket_name" {
  value = google_storage_bucket.zenml_artifacts.name
}

output "bronze_dataset_id" {
  value = google_bigquery_dataset.bronze.dataset_id
}

output "silver_dataset_id" {
  value = google_bigquery_dataset.silver.dataset_id
}

output "gold_dataset_id" {
  value = google_bigquery_dataset.gold.dataset_id
}
