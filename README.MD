# data-foundation

> **Dealinka's data platform foundation** — the infrastructure and MLOps scaffolding required before any machine learning use case can be developed.

Dealinka is a French impact startup that redirects unsold, non-food stock (textiles, appliances, hygiene products…) from companies to charities and reuse organisations. See [`dealinka.md`](./dealinka.md) for the full business context.

---

## Architecture overview

```
                         ┌─────────────────────────────────────────┐
                         │   Airflow / Cloud Composer (DE layer)   │
                         │                                         │
  ERP Feed (GCS) ──────► │  Bronze ──► Silver (dbt) ──► Gold (dbt) │
                         │                  │ Great Expectations   │
                         └──────────────────┼──────────────────────┘
                                            │ trigger
                         ┌──────────────────▼──────────────────────┐
                         │          ZenML (ML layer)               │
                         │                                         │
                         │  Ingest ──► Preprocess ──► Train ──►    │
                         │  Evaluate ──► Deploy (Vertex AI)        │
                         └──────────────────────────────────────────┘
                                            │
                         ┌──────────────────▼──────────────────────┐
                         │   Robyn API  ◄──  Feature Store (online)│
                         │   /predict/matching                     │
                         └─────────────────────────────────────────┘
```

**Dual-orchestrator model:**
- **Airflow** owns the Bronze → Gold data pipeline (ingestion, transformation, validation).
- **ZenML** takes over from the Gold layer for all ML tasks (training, evaluation, deployment).
- Airflow triggers ZenML via API at the end of each daily pipeline run.

---

## Quick start

### 1. Prerequisites

| Tool | Purpose | Install |
| :--- | :--- | :--- |
| `just` | Command runner | [docs](https://github.com/casey/just#installation) |
| `uv` | Python package manager | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `gcloud` CLI | GCP authentication | [docs](https://cloud.google.com/sdk/docs/install) |
| `terraform` | Infrastructure provisioning | [docs](https://developer.hashicorp.com/terraform/install) |
| `dbt-bigquery` | SQL transformation | `pip install dbt-bigquery` |

### 2. Configure your environment

```bash
cp .env.example .env
# Fill in GCP_PROJECT, GCP_REGION, ARTIFACT_REGISTRY, MLFLOW_TRACKING_URI, etc.
```

### 3. List all available commands

```bash
just
```

### 4. Run phase by phase

```bash
just phase-0    # Bootstrap: Python env + Terraform infra
just phase-1    # Fake data: generate and upload to GCS
just phase-2    # Airflow: validate and trigger DAGs
just phase-3    # dbt: build Silver + Gold layers
just phase-4    # Great Expectations: validate Gold layer
just phase-5    # BQML: train baseline model + log to MLflow
just phase-6    # ZenML: run ML pipeline locally
just phase-7 <endpoint_id>   # Docker: build, push, deploy Robyn API
just phase-8 <endpoint_id>   # Monitoring: enable Vertex AI model monitoring
```

---

## AI Agents

This repo ships with pre-configured AI agent rules and skills.

**Rules** (always active):
- `DataEngineering.md` — enforces Medallion architecture, schema-first, idempotency, and BigQuery best practices.
- `MLOps.md` — enforces the Data-First handoff (ZenML only reads Gold layer), serverless-first DevOps, and the 6-tier testing framework.

**Skills** (loaded on-demand):

| Layer | Skill |
| :--- | :--- |
| Data Engineering | `dbt`, `GreatExpectations`, `Airflow`, `PubSub`, `VertexAI_FeatureStore`, `BigQuery_ML` |
| MLOps | `ZenML`, `VertexAI`, `MLFlow`, `Robyn`, `DevOps` |
| Platform | `Terraform` |

---

## Key documents

| File | Description |
| :--- | :--- |
| [`dealinka.md`](./dealinka.md) | Business context |
| [`ml_business_case.md`](./ml_business_case.md) | 4 ML use cases, KPIs, full stack overview, phased roadmap |
| [`justfile`](./justfile) | All runnable commands for the project |
| [`.env.example`](./.env.example) | Required environment variables |

---

## Data Governance

- All secrets are stored in **Google Secret Manager**. No credentials in `.env` files beyond local dev.
- Each service account (`airflow-sa`, `zenml-sa`, `dbt-sa`) follows the **principle of least privilege**.
- PII columns in Silver/Gold layers are tagged and governed via **BigQuery Column-Level Security**.
- Bronze tables have a **90-day expiration** policy enforced via Terraform.
