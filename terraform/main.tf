terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- STORAGE BUCKETS ---

resource "google_storage_bucket" "erp_feed" {
  name                        = "${var.project_id}-erp-feed"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "zenml_artifacts" {
  name                        = "${var.project_id}-zenml-artifacts"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
}

# --- BIGQUERY DATASETS (dbt — Medallion Architecture) ---

resource "google_bigquery_dataset" "bronze" {
  dataset_id  = "bronze"
  location    = var.region
  description = "Bronze layer: raw staging data (stg_ models). Managed by dbt."

  default_table_expiration_ms = 7776000000 # 90 days

  labels = {
    pipeline = "dbt"
    layer    = "bronze"
    env      = var.environment
  }

  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset" "silver" {
  dataset_id  = "silver"
  location    = var.region
  description = "Silver layer: cleaned and joined data (int_ models). Managed by dbt."

  default_table_expiration_ms = 15552000000 # 180 days

  labels = {
    pipeline = "dbt"
    layer    = "silver"
    env      = var.environment
  }

  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset" "gold" {
  dataset_id  = "gold"
  location    = var.region
  description = "Gold layer: feature marts and ML-ready data (mart_/fct_/dim_). Consumed by ZenML and BQML."

  # No expiration — Gold data is long-lived

  labels = {
    pipeline = "dbt"
    layer    = "gold"
    env      = var.environment
  }

  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# --- BIGQUERY DATASETS (Verity — Governance-as-Code) ---
# Verity BigQuery connector uses a single VERITY_DATASET env var.
# All layers (stg, int, mart) materialize into one dataset per environment.

resource "google_bigquery_dataset" "verity_dev" {
  dataset_id  = "verity_dev"
  location    = var.region
  description = "Verity dev: all transformation layers in one dataset (governance-as-code engine)."

  default_table_expiration_ms = var.verity_dataset_expiration_days * 86400000

  labels = {
    pipeline = "verity"
    layer    = "all"
    env      = "dev"
  }

  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset" "verity_prod" {
  dataset_id  = "verity_prod"
  location    = var.region
  description = "Verity prod: all transformation layers in one dataset (governance-as-code engine). Strict mode enforced."

  # No expiration — production data is long-lived

  labels = {
    pipeline = "verity"
    layer    = "all"
    env      = "prod"
  }

  delete_contents_on_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# --- ARTIFACT REGISTRY ---

resource "google_artifact_registry_repository" "data_platform" {
  location      = var.region
  repository_id = "data-platform"
  description   = "Docker repository for data platform jobs"
  format        = "DOCKER"
}

# --- SERVICE ACCOUNTS ---

# dbt / Cloud Run orchestrator
resource "google_service_account" "data_platform_sa" {
  account_id   = "data-platform-job-sa"
  display_name = "Service Account for Cloud Run Data Jobs (dbt)"
}

# Verity pipeline
resource "google_service_account" "verity_sa" {
  account_id   = "verity-pipeline-sa"
  display_name = "Service Account for Verity Governance Pipeline"
}

# Scheduler Service Account
resource "google_service_account" "scheduler_sa" {
  account_id   = "scheduler-sa"
  display_name = "Service Account for Cloud Scheduler triggers"
}

# --- IAM: Scheduler Service Account ---

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  location = google_cloud_run_v2_job.data_job.location
  name     = google_cloud_run_v2_job.data_job.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
}


# --- IAM: dbt Service Account ---

resource "google_bigquery_dataset_iam_member" "dbt_bronze_editor" {
  dataset_id = google_bigquery_dataset.bronze.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_silver_editor" {
  dataset_id = google_bigquery_dataset.silver.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_gold_editor" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_service_account_iam_member" "user_impersonation" {
  for_each           = toset(var.developer_emails)
  service_account_id = google_service_account.data_platform_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_project_iam_member" "dbt_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_storage_bucket_iam_member" "storage_admin" {
  bucket = google_storage_bucket.erp_feed.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

# --- IAM: Verity Service Account ---

# Write access to Verity datasets only
resource "google_bigquery_dataset_iam_member" "verity_dev_editor" {
  dataset_id = google_bigquery_dataset.verity_dev.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.verity_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "verity_prod_editor" {
  dataset_id = google_bigquery_dataset.verity_prod.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.verity_sa.email}"
}

# Read-only access to dbt Gold (cross-pipeline reference)
resource "google_bigquery_dataset_iam_member" "verity_gold_viewer" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.verity_sa.email}"
}

resource "google_project_iam_member" "verity_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.verity_sa.email}"
}

# --- SECRET MANAGER ---

resource "google_secret_manager_secret" "mlflow_uri" {
  secret_id = "mlflow-tracking-uri"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "mlflow_uri_data" {
  secret      = google_secret_manager_secret.mlflow_uri.id
  secret_data = "placeholder" # Managed out-of-band via 'just secret-set'

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "cloudrun_secret_accessor" {
  secret_id = google_secret_manager_secret.mlflow_uri.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

# --- CLOUD RUN ---
# Uses Google's public hello image for initial creation.
# Real image deployed via `just cr-prepare`. lifecycle.ignore_changes prevents revert.

resource "google_cloud_run_v2_job" "data_job" {
  name     = "data-platform-orchestrator"
  location = var.region

  template {
    template {
      service_account = google_service_account.data_platform_sa.email
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/data-platform/orchestrator:${var.container_image_tag}"
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "GCP_REGION"
          value = var.region
        }
        env {
          name = "MLFLOW_TRACKING_URI"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.mlflow_uri.secret_id
              version = var.mlflow_tracking_uri_version
            }
          }
        }
      }
    }
  }
}

# --- CLOUD SCHEDULER ---

resource "google_cloud_scheduler_job" "verity_schedule" {
  name             = "verity-daily-check"
  description      = "Triggers the Verity data quality pipeline daily"
  schedule         = "0 7 * * * "
  time_zone        = "Europe/Paris"
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.data_job.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
}

