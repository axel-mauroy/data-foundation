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
  name     = "${var.project_id}-erp-feed"
  location = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "zenml_artifacts" {
  name     = "${var.project_id}-zenml-artifacts"
  location = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

# --- BIGQUERY DATASETS ---

resource "google_bigquery_dataset" "bronze" {
  dataset_id = "bronze"
  location   = var.region
  description = "Bronze layer: raw staging data"
}

resource "google_bigquery_dataset" "silver" {
  dataset_id = "silver"
  location   = var.region
  description = "Silver layer: cleaned and joined data"
}

resource "google_bigquery_dataset" "gold" {
  dataset_id = "gold"
  location   = var.region
  description = "Gold layer: feature marts and ML-ready data"
}

# --- ARTIFACT REGISTRY ---

resource "google_artifact_registry_repository" "data_platform" {
  location      = var.region
  repository_id = "data-platform"
  description   = "Docker repository for data platform jobs"
  format        = "DOCKER"
}

# --- COMPUTE (CLOUD RUN JOBS) ---

resource "google_service_account" "data_platform_sa" {
  account_id   = "data-platform-job-sa"
  display_name = "Service Account for Cloud Run Data Jobs"
}

resource "google_project_iam_member" "bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_project_iam_member" "bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_storage_bucket_iam_member" "storage_admin" {
  bucket = google_storage_bucket.erp_feed.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.data_platform_sa.email}"
}

resource "google_cloud_run_v2_job" "data_job" {
  name     = "data-platform-orchestrator"
  location = var.region

  template {
    template {
      service_account = google_service_account.data_platform_sa.email
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.data_platform.repository_id}/orchestrator:latest"
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "GCP_REGION"
          value = var.region
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}
