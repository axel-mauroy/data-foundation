variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment (dev, uat, prod). Used for resource labels."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "Environment must be one of: dev, uat, prod."
  }
}

variable "verity_dataset_expiration_days" {
  description = "Default table expiration in days for the Verity dev dataset. Set to 0 for no expiration."
  type        = number
  default     = 90

  validation {
    condition     = var.verity_dataset_expiration_days >= 0
    error_message = "Expiration days must be non-negative."
  }
}
