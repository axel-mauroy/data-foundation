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
