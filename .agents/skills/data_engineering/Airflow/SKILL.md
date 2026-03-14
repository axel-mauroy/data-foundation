---
name: Apache Airflow (Cloud Composer)
description: Best practices for orchestrating complex data engineering pipelines (Bronze ingestion layer) on GCP using Cloud Composer.
---

# Apache Airflow (Cloud Composer) Best Practices Guide

Apache Airflow is the industry-standard orchestrator for **data engineering** tasks: multi-source ingestion, ERP feed processing, and complex dependency management. On GCP, it is deployed as **Cloud Composer** (a managed Airflow service).

> [!IMPORTANT]
> **Airflow is the orchestrator for Data Engineering (Bronze/Silver layers). ZenML is the orchestrator for MLOps (Gold layer → Model).**
> Never use ZenML for raw ERP feed ingestion. Never use Airflow for model training pipelines. Use each tool for its designed purpose, and connect them via a trigger at the end of the Airflow DAG.

## 1. DAG Design Principles

### Best Practices:
- **Idempotency:** Every task must be safe to re-run. Use `WRITE_TRUNCATE` or upsert patterns in BigQuery operations.
- **Atomic Tasks:** Each task does one thing. Avoid mega-tasks that load, transform, and validate in a single step.
- **Parameterize with `logical_date`:** Use Airflow's execution date for partitioned, backfill-safe pipelines.

```python
from airflow.decorators import dag, task
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from pendulum import datetime

@dag(
    schedule="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=True,   # Enables backfill
    tags=["bronze", "ingestion"],
)
def ingest_company_inventory():

    load_to_bronze = BigQueryInsertJobOperator(
        task_id="load_raw_inventory",
        configuration={
            "load": {
                "sourceUris": ["gs://dealinka-raw/inventory/{{ ds }}/*.json"],
                "destinationTable": {
                    "projectId": "dealinka-prod",
                    "datasetId": "bronze",
                    "tableId": "company_inventory${{ ds_nodash }}",
                },
                "writeDisposition": "WRITE_TRUNCATE",
                "sourceFormat": "NEWLINE_DELIMITED_JSON",
            }
        },
    )

    return load_to_bronze

dag = ingest_company_inventory()
```

## 2. Sensor Patterns (Triggering on Data Arrival)

Use sensors to make DAGs event-driven rather than schedule-driven.

```python
from airflow.providers.google.cloud.sensors.gcs import GCSObjectExistenceSensor

wait_for_feed = GCSObjectExistenceSensor(
    task_id="wait_for_erp_feed",
    bucket="dealinka-raw",
    object="inventory/{{ ds }}/feed.json",
    timeout=3600,      # Max 1 hour wait
    poke_interval=300, # Check every 5 minutes
    mode="reschedule", # Frees up a worker slot while waiting
)
```

## 3. Medallion Architecture in Airflow

Structure DAGs to mirror the Bronze → Silver → Gold flow.

```
DAG: daily_data_platform
├── Task 1: [Sensor] Wait for ERP feed (GCS)
├── Task 2: [BigQuery] Load raw JSON → bronze.company_inventory
├── Task 3: [dbt] Run staging models (stg_company_inventory)
├── Task 4: [Great Expectations] Validate Silver layer
├── Task 5: [dbt] Run mart models (mart_feature_matching)
└── Task 6: [HTTP] Trigger ZenML matching pipeline (via Cloud Run API)
```

## 4. Triggering ZenML Pipelines

The most important handoff: when Airflow finishes building the Gold layer, it triggers the ZenML ML pipeline.

```python
from airflow.providers.http.operators.http import SimpleHttpOperator
import json

trigger_zenml = SimpleHttpOperator(
    task_id="trigger_zenml_matching_pipeline",
    http_conn_id="zenml_server",
    endpoint="/api/v1/runs",
    method="POST",
    data=json.dumps({
        "pipeline_name": "matching_pipeline",
        "stack_name": "production",
    }),
    headers={"Content-Type": "application/json"},
)
```

## 5. Cloud Composer Best Practices

- **PyPI Packages:** Manage dependencies via `requirements.txt` in Composer environment settings — not inside DAG files.
- **Environments:** Use separate Composer environments for `dev` and `prod`.
- **Secret Manager:** Never hardcode credentials. Use `google-cloud-secret-manager` or Airflow Connections stored in Cloud Composer's Secret Backend.
- **Alerting:** Configure email/Slack alerts on task failures using `on_failure_callback`.

---

**Data Reliability Summary (CTO):**
Cloud Composer (Airflow) is the reliable workhorse that digests raw client data feeds and delivers clean, validated feature tables by a defined daily SLA. It is the gatekeeper that ensures the ML system never trains on incomplete or malformed data.
