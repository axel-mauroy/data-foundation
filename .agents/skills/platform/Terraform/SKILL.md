---
name: Terraform
description: Infrastructure as Code (IaC) best practices for reproducible, scalable, and versioned MLOps environments.
---

# Terraform Best Practices Guide

Terraform allows you to define and provision infrastructure using a high-level configuration language (HCL). In MLOps, it ensures that your training clusters, feature stores, and end-points are identical across environments.

## 1. State Management

The state file is the source of truth for your infrastructure.

- **Remote Backend:** Always use a remote backend (e.g., GCS bucket) with state locking to prevent concurrency issues and data loss.
- **Workspaces:** Use Terraform Workspaces to manage `dev`, `staging`, and `prod` with the same codebase.

## 2. Modular Architecture

Build reusable modules to standardize resource creation.

### Common MLOps Modules
- **`vertex_ai`:** Standardize the creation of Endpoints, Datasets, and Pipeline schedules.
- **`iam`:** Manage least-privileged access for service accounts used by ML pipelines.
- **`networking`:** Configure VPC peering for high-performance, private connectivity between BigQuery and Vertex AI.

## 3. Resource Management

- **Tags/Labels:** Apply consistent labels (e.g., `model_name`, `env`, `cost_center`) to all resources for cost tracking and auditing.
- **Variables & Locals:** Avoid hardcoding, it's a security risk. Use `.tfvars` files and environment-specific variables.

## 4. Lifecycle & Safety

- **`lifecycle { prevent_destroy = true }`:** Apply to critical production resources like the primary Feature Store or BigQuery datasets.
- **Plan Review:** Always run `terraform plan` and store the output for review before applying changes in production.

## 5. MLOps Integration

- **Provisioning Vertex AI:** Automate the creation of Model Registry entries and monitoring jobs.
- **Secret Management:** Integrate with Google Secret Manager to handle API keys and credentials securely (no hardcoded secrets).
- **CI/CD:** Use tools like GitHub Actions to automate the infrastructure rollout alongside your code changes.

---

**Senior MLOps Architect Summary:**
Terraform eliminates "it works on my machine" infrastructure. It is the foundation for Blue-Green Deployments and disaster recovery, ensuring the MLOps lifecycle is automated from the ground up.
