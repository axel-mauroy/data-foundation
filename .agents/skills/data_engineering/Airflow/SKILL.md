---
name: Apache Airflow (Cloud Composer)
description: Best practices for orchestrating complex data engineering pipelines (Bronze ingestion layer) on GCP using Cloud Composer.
---

# Apache Airflow (Cloud Composer) Best Practices Guide

Apache Airflow is the industry-standard orchestrator for **data engineering** tasks: multi-source ingestion, ERP feed processing, and complex dependency management. On GCP, it is deployed as **Cloud Composer** (a managed Airflow service).

> [!IMPORTANT]
> **Airflow is the orchestrator for Data Engineering (Bronze/Silver layers). ZenML is the orchestrator for MLOps (Gold layer → Model).**
> Never use ZenML for raw ERP feed ingestion. Never use Airflow for model training pipelines. Use each tool for its designed purpose, and connect them via a trigger at the end of the Airflow DAG.

## Table of Contents
1. [DAG Design & Performance](#1-dag-design--performance)
2. [failure Handling & Sensor Patterns](#2-failure-handling--sensor-patterns)
3. [Medallion Architecture in Airflow](#3-medallion-architecture-in-airflow)
4. [Triggering ZenML Pipelines](#4-triggering-zenml-pipelines)
5. [Cloud Composer Best Practices](#5-cloud-composer-best-practices)
6. [Testing & Validation](#6-testing--validation)
7. [Dependency Isolation](#7-dependency-isolation)
8. [Advanced Decorators (TaskFlow)](#8-advanced-decorators-taskflow)
9. [Accessing Context & Jinja](#9-accessing-context--jinja)
10. [Input Validation with Params](#10-input-validation-with-params)
11. [Robust Notifications & Callbacks](#11-robust-notifications--callbacks)
12. [Conditional Logic & Branching](#12-conditional-logic--branching)
13. [Cross-DAG Dependencies](#13-cross-dag-dependencies)
14. [Custom Components & Imports](#14-custom-components--imports)
15. [General DAG Best Practices (The "Dealinka" Standard)](#15-general-dag-best-practices-the-dealinka-standard)
16. [Scaling & Performance Parameters](#16-scaling--performance-parameters)
17. [Airflow 3.0 Concepts](#17-airflow-30-concepts)
18. [Advanced Templating & Macros](#18-advanced-templating--macros)

---

## 1. DAG Design & Performance

The Airflow scheduler parses DAG files frequently. Every line of code outside an `@task` or `Operator` is "top-level" and runs on every heart-beat.

### ⚡ Performance Directives:
- **No Top-Level Database/Network Calls:** Never call `Variable.get()`, `HttpHook`, or database queries at the top level. It degrades scheduler performance and can cause timeouts.
- **Lazy Imports:** Import heavy libraries (pandas, tensorflow) inside the task function, not at the top of the file.
- **Jinja over Python API:** Access Variables and Connections via Jinja templates (e.g., `{{ var.value.get('foo') }}`) to delay execution until task runtime. Using `Variable.get()` at the top level creates database hits on every scheduler heartbeat.
- **Custom Timetables:** Avoid `Variable.get()` or connection retrieval inside the `__init__` method of custom timetables.

### 🔍 How to check for top-level code:
A simple trick is to add `print("executing")` statements to your functions and run `python your_dag_file.py` in the terminal. If the print executes, your code is running at the top level and will slow down DAG parsing.

### 📉 Reducing DAG Complexity:
- **Linear over Deep Trees:** A simple linear structure (`A -> B -> C`) experiences fewer scheduling delays than a deeply nested tree structure with exponentially growing depending tasks.
- **File Distribution:** If parsing is slow, consider splitting multiple DAGs into individual files.

```python
from airflow.decorators import dag, task
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from pendulum import datetime

@dag(
    schedule="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=True,
    tags=["bronze", "ingestion"],
    default_args={"retries": 2},
)
def ingest_company_inventory():

    @task
    def prepare_config():
        # Local import to keep scheduler heart-beat fast
        import json
        return {"batch_id": "DEALINKA_001"}

    load_to_bronze = BigQueryInsertJobOperator(
        task_id="load_raw_inventory",
        configuration={
            "load": {
                "sourceUris": ["gs://dealinka-raw/inventory/{{ ds }}/*.json"],
                "destinationTable": {
                    "projectId": "dealinka-prod",
                    "datasetId": "bronze",
                    "tableId": "stg_inventory${{ ds_nodash }}",
                },
                # Use Jinja for Variables to avoid top-level database hits
                "labels": {"env": "{{ var.value.environment }}"},
                "writeDisposition": "WRITE_TRUNCATE",
            }
        },
    )

    prepare_config() >> load_to_bronze

dag = ingest_company_inventory()
```

## 2. failure Handling & Sensor Patterns

### The Watcher Pattern (Ensuring Failure)
When using teardown/cleanup tasks with `TriggerRule.ALL_DONE`, the DAG may appear "Successful" even if upstream tasks failed. Use a **Watcher** task to force failure.

```python
from airflow.exceptions import AirflowException
from airflow.utils.trigger_rule import TriggerRule

@task(trigger_rule=TriggerRule.ONE_FAILED)
def watcher():
    raise AirflowException("Failing DAG because one or more upstream tasks failed.")

# Ensure watcher is downstream of all tasks
[load_to_bronze, cleanup_task] >> watcher()
```

### Sensor Strategy
- **`mode="reschedule"`:** Always use this for sensors with intervals > 1 min. It frees up the worker slot between pokes.
```python
from airflow.providers.google.cloud.sensors.gcs import GCSObjectExistenceSensor

wait_for_feed = GCSObjectExistenceSensor(
    task_id="wait_for_erp_feed",
    bucket="dealinka-raw",
    object="inventory/{{ ds }}/feed.json",
    timeout=3600,
    poke_interval=300,
    mode="reschedule", 
)
```

---

## 3. Medallion Architecture in Airflow

Structure DAGs to mirror the **Bronze (Staging) → Silver (Intermediate) → Gold (Marts)** flow.

```
DAG: daily_data_platform
├── Task 1: [Sensor] Wait for GCS feed
├── Task 2: [BigQuery] Load Raw → bronze.stg_inventory
├── Task 3: [dbt] Run intermediate logic (Silver)
├── Task 4: [Great Expectations] Final Quality Gate
├── Task 5: [dbt] Run mart models (Gold)
└── Task 6: [HTTP] Trigger ZenML (via Cloud Run)
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

## 6. Testing & Validation

Treat DAGs as production code. Implement two-tier testing:

### 6.1 DAG Loader Test (CI/CD Gate)
Prevents broken DAGs from reaching the environment.
```python
import pytest
from airflow.models import DagBag

def test_dag_loading():
    dagbag = DagBag(dag_folder="dags/", include_examples=False)
    assert len(dagbag.import_errors) == 0, f"DAG import errors: {dagbag.import_errors}"
```

### 6.2 Unit Testing Tasks
Use `dag.test()` to run a DAG locally without a full Airflow database.
```python
def test_ingestion_logic():
    from dags.ingest_dag import dag
    dagrun = dag.test(execution_date=datetime(2025,1,1))
    assert dagrun.state == "success"

# Note: dag.test() is available in Airflow 2.5+
```

### 6.3 Mocking Variables & Connections
When unit testing tasks that rely on Airflow Variables or Connections, do not write them to a test database. Instead, simulate them using environment variables and `unittest.mock.patch.dict` to speed up tests:
```python
from unittest import mock

def test_my_task():
    with mock.patch.dict("os.environ", AIRFLOW_VAR_MY_KEY="mocked_value"):
        assert Variable.get("my_key") == "mocked_value"
```

### 6.4 DAG Self-Checks
Implement checks inside the DAG to verify tasks produced expected results. For example, use sensors (`S3KeySensor`, `HttpSensor`, BigQuery check operators) immediately following an execution task to validate the output state before proceeding.

### 6.5 Staging Parameterization
Test complete DAG runs in a staging environment. Ensure the DAG is parameterized via environment variables (e.g., `os.environ.get("TARGET_GS_PATH")`) rather than hardcoding production values.

---

## 7. Dependency Isolation

If a task requires conflicting Python packages, use **`PythonVirtualenvOperator`** or **`ExternalPythonOperator`** rather than modifying the core Cloud Composer environment.

```python
@task.virtualenv(
    requirements=["pandas==1.3.0", "numpy==1.21.0"],
    system_site_packages=False
)
def process_with_specific_version():
    import pandas as pd
    # logic here...
```

---

## 8. Advanced Decorators (TaskFlow)

TaskFlow decorators simplify DAG authoring by handling XComs and dependencies implicitly.

- `@task.bash`: Run bash commands within a TaskFlow flow.
- `@task.sensor`: Turn any Python function into an Airflow sensor.
- `@task_group`: Organize related tasks visually without affecting logic.

```python
from airflow.decorators import task, task_group

@task_group(group_id="transform_layer")
def transform_data(raw_data):
    
    @task
    def clean(data):
        return data.strip()
    
    @task
    def validate(data):
        if not data: raise ValueError("Empty data")
        return data

    return validate(clean(raw_data))
```

---

## 9. Accessing Context & Jinja

Use the `**context` keyword in Python tasks to access metadata about the DAG run.

Common Keys:
- `ds`: The logical date (partition date) string (`YYYY-MM-DD`).
- `ti`: The Task Instance object (use for explicit `xcom_pull/push`).
- `dag_run`: The DAG Run object (use `dag_run.run_type` to check if manual or scheduled).
- `params`: Access user-provided parameters.

```python
@task
def process_metadata(**context):
    logical_date = context["ds"]
    run_type = context["dag_run"].run_type
    ti = context["ti"]
    
    print(f"Processing partition {logical_date} for {run_type} run.")
```

---

## 10. Input Validation with Params

Use the `Param` class to define typed, validated inputs for manual DAG triggers.

```python
from airflow.models.param import Param

@dag(
    params={
        "environment": Param("production", enum=["production", "staging", "dev"]),
        "batch_id": Param(1, type="integer", minimum=1),
        "source_filter": Param("ERP_", type="string", minLength=4),
    }
)
def parameterized_ingestion():
    @task
    def run_logic(params):
        print(f"Running in {params['environment']} for batch {params['batch_id']}")
```

---

## 11. Robust Notifications & Callbacks

Use `SlackNotifier` for standardizing alerts across the platform.

```python
from airflow.providers.slack.notifications.slack_notifier import SlackNotifier

SLACK_NOTIFIER = SlackNotifier(
    slack_conn_id="slack_default",
    text="❌ Task {{ ti.task_id }} failed in DAG {{ dag.dag_id }} on {{ ds }}",
    channel="#alerts-data-eng"
)

@dag(
    on_failure_callback=SLACK_NOTIFIER,
    default_args={"on_success_callback": None}
)
def monitored_pipeline():
    # Tasks here...
    pass
```


---

## 12. Conditional Logic & Branching

Branching allows DAGs to adapt to data states (e.g., "only run if accuracy is high").

- **`@task.branch`**: Returns the ID (or list of IDs) of the next task(s) to run.
- **`@task.short_circuit`**: Returns a boolean. If `False`, all downstream tasks are skipped.

```python
from airflow.decorators import task

@task.branch
def check_quality(metrics):
    if metrics["accuracy"] > 0.95:
        return "deploy_to_prod"
    return "retrain_model"

@task.short_circuit
def is_sunday():
    from pendulum import now
    return now().day_of_week == 0 # Only continue if Sunday
```

> [!TIP]
> Use `trigger_rule="none_failed_min_one_success"` on the task where branches rejoin to avoid the entire downstream failing due to skipped branches.

---

## 13. Cross-DAG Dependencies

Manage dependencies between different DAG files (e.g., Gold Marts triggering ZenML).

### 13.1 Assets (Data-Aware Scheduling) - *Preferred*
The most modern way to link DAGs. A downstream DAG triggers automatically when an upstream task updates an `Asset`.

```python
from airflow.sdk import Asset

GOLD_MART = Asset("bigquery://gold.mart_feature_matching")

@dag(schedule=[GOLD_MART]) # Triggers when GOLD_MART is updated
def downstream_ml_dag():
    pass
```

### 13.2 TriggerDagRunOperator (Push)
Explicitly trigger a downstream DAG from an upstream one.
```python
from airflow.operators.trigger_dagrun import TriggerDagRunOperator

trigger_ml = TriggerDagRunOperator(
    task_id="trigger_ml_pipeline",
    trigger_dag_id="ml_training_dag",
    wait_for_completion=True,
    deferrable=True # Frees up worker while waiting
)
```

### 13.3 ExternalTaskSensor (Pull)
Wait for a specific task in another DAG to complete.
```python
from airflow.sensors.external_task import ExternalTaskSensor

wait_for_ingestion = ExternalTaskSensor(
    task_id="wait_for_bronze_load",
    external_dag_id="ingestion_dag",
    external_task_id="load_raw_data",
    mode="reschedule",
    deferrable=True
)
```

---

## 14. Custom Components & Imports

Organize reusable logic in the `include/` directory (automatically added to `PYTHONPATH` in most project structures).

### Project Structure:
```
.
├── dags/
│   └── main_dag.py
└── include/
    └── operators/
        └── dealinka_operator.py
```

### Custom Operator Boilerplate:
```python
from airflow.models.baseoperator import BaseOperator

class BigQueryToSlackOperator(BaseOperator):
    template_fields = ("sql", "channel")

    def __init__(self, sql: str, channel: str, **kwargs):
        super().__init__(**kwargs)
        self.sql = sql
        self.channel = channel

    def execute(self, context):
        # Logic here...
        self.log.info(f"Executing query: {self.sql}")
```


---

## 15. General DAG Best Practices (The "Dealinka" Standard)

Follow these rules for production-grade pipelines:

### 15.1 Idempotency & Atomicity (Treat Tasks like DB Transactions)
- **Rule**: A DAG run for a specific date must produce the same result regardless of how many times it is rerun.
- **Rule**: Each task must do **one thing**. Avoid "Extract-Transform-Load" in a single Python function. Split them so you can restart from the failure point.
- **No INSERTs on Re-runs**: Never use `INSERT` statements as they lead to duplicates on retry. Always replace with `UPSERT` (e.g., `MERGE` in BigQuery) or `WRITE_TRUNCATE`.
- **Partition-Bound Reads/Writes**: Never read the "latest available" data. Read and write in specific partitions using `data_interval_start` (or `{{ ds }}`) to ensure consistency across retries.
- **Avoid `datetime.now()`**: Using current time inside a task for critical logic results in different outcomes on each run. Use Airflow's logical execution date context instead.

### 15.2 Retries
- **Rule**: Set `retries: 2` at the DAG level (`default_args`). This handles transient network issues or preemptible worker nodes in Cloud Composer.

### 15.3 Incremental Filtering
- Avoid processing full tables every day. Use `data_interval_start` and `data_interval_end` to filter source data.

### 15.4 Communication & Storage
- **No Local Files**: Never store files or configuration on the local filesystem. Cloud Composer/Kubernetes executors distribute tasks across servers; the next task won't find the file.
- **XCom for Meta, Storage for Data**: Use XCom *only* for small messages (e.g., passing a GCS URI). Use GCS/BigQuery to pass large data payloads between tasks.
- **Connections for Secrets**: Never store authentication parameters or tokens in XComs. Instead, securely pass them via Airflow Connections/Secret Backend.

```python
# Use the logical interval for precise daily filtering
query = f"""
    SELECT * FROM raw_data 
    WHERE created_at >= '{ {{ data_interval_start }} }'
      AND created_at <  '{ {{ data_interval_end }} }'
"""
```

---

## 16. Scaling & Performance Parameters

Control resource usage and pipeline speed with these DAG-level parameters:

- **`max_active_runs=1`**: Prevents multiple runs of the same DAG from overlapping (essential for non-concurrent data loads).
- **`max_active_tasks=10`**: Prevents a single massive DAG from hogging all worker slots in a shared Airflow environment.
- **`fail_fast=True`**: Immediately fails the entire DAG run if any task fails, without waiting for other parallel branches to finish.

---

## 17. Airflow 3.0 Readiness, Maintenance & Linting

The platform is moving towards Airflow 3.0. Be familiar with these concepts and practices:

### 17.1 Airflow 3.0 Concepts
- **DAG Versioning**: Airflow automatically tracks structural changes. Every structural change creates a new version visible in the UI.
- **DAG Bundles**: Code is no longer just "files in the dags folder." Bundles allow mounting DAG files from different backends.

### 17.2 Code Quality & Linting (`ruff`)
To proactively prepare for Airflow 3.0 and maintain high code quality, use the `ruff` linter with Airflow-specific rules (`AIR` rules) to detect deprecations:
```bash
# Check DAGs for Airflow 3.0 compatibility
ruff check dags/ --select AIR3
```

### 17.3 Maintenance & Upgrades
- **Metadata DB Cleaning**: The metadata DB grows over time, degrading performance. Use `airflow db clean` to purge old task runs and logs.
- **Pause & Backup**: Before any major upgrade or maintenance, backup the DB and pause all DAGs (`airflow dags pause <DAG_ID>`) or disable the scheduler (`[scheduler] use_job_schedule = False`).
- **Integration Test DAGs**: Create dedicated "canary" DAGs that hit common infrastructure with test credentials. After an upgrade, unpause these test DAGs first to verify cluster functionality before releasing production workloads.


---

## 18. Advanced Templating & Macros

Templates allow you to pass dynamic information to tasks at runtime without executing code at the scheduler level.

### 18.1 Custom Macros & Filters
Standardize logic across DAGs using `user_defined_macros` (for functions/variables) or `user_defined_filters` (for pipe-syntax).

```python
# Custom filter for currency conversion
def to_eur(amount, rate):
    return amount * rate

@dag(
    user_defined_filters={"to_eur": to_eur},
    user_defined_macros={"MARKET_RATE": 0.92}
)
def financial_dag():
    convert = BashOperator(
        task_id="convert_revenue",
        bash_command="echo Total revenue is {{ 1000 | to_eur(MARKET_RATE) }} EUR"
    )
```

### 18.2 Native Object Rendering
By default, Jinja renders everything as a string. Set `render_template_as_native_obj=True` to pass Python lists or dicts directly to operators.

```python
@dag(render_template_as_native_obj=True)
def native_dag():
    # {{ params.list }} will be a real Python list, not a string "[1, 2]"
    process = PythonOperator(
        task_id="process_list",
        python_callable=lambda x: print(type(x)),
        op_args=["{{ params.my_list }}"]
    )
```

### 18.3 External Scripts & Search Paths
Keep SQL and Bash logic out of the Python files to enable IDE syntax highlighting.

- **`template_searchpath`**: Bases files in a specific directory.
- **`template_ext`**: Defines which extensions Airflow should template.

```python
@dag(template_searchpath="/opt/airflow/include/sql")
def sql_dag():
    # Airflow looks for 'include/sql/transform.sql' and templates it
    run_query = BigQueryInsertJobOperator(
        task_id="transform_data",
        configuration={"query": {"query": "transform.sql", "useLegacySql": False}}
    )
```

### 18.4 Callables as Template Fields (Airflow 2.10+)
For complex logic that Jinja can't handle, pass a Python function directly to a templateable field.

```python
def build_bigquery_conf(context, jinja_env):
    # Mandatory kwargs: context, jinja_env
    return {"labels": {"run_id": context["run_id"]}}

run_query = BigQueryInsertJobOperator(
    task_id="load_data",
    configuration=build_bigquery_conf # Callable is executed at runtime
)
```

---

**Data Reliability Summary (CTO):**
Cloud Composer (Airflow) is the reliable workhorse that digests raw client data feeds and delivers clean, validated feature tables by a defined daily SLA. It is the gatekeeper that ensures the ML system never trains on incomplete or malformed data.
