---
name: ZenML
description: Comprehensive guide for orchestrating MLOps workflows and unifying tools like Vertex AI and MLflow.
---

# ZenML Best Practices Guide

ZenML is an extensible, open-source MLOps framework to create production-ready machine learning pipelines. It acts as the "glue" that connects data, infrastructure, and models.

## 1. Pipeline Orchestration

ZenML allows you to define pipelines in a tool-agnostic way and run them on various orchestrators.

### Best Practices:
- **Modular Steps:** Decouple data ingestion, preprocessing, training, and evaluation into individual, reproducible steps.
- **Orchestrator Selection:** Use the `local` orchestrator for development and the `vertex` orchestrator for production scaling.
- **Caching:** Leverage ZenML's caching mechanism to skip unnecessary step executions.

```python
from zenml import pipeline, step

@step
def training_step(data: dict) -> dict:
    # Training logic
    return {"model": "churn_v1"}

@pipeline
def churn_pipeline():
    data = ingestion_step()
    model = training_step(data)
```

## 2. Infrastructure Stacks

A ZenML Stack defines where your data lives, where your code runs, and where your models are stored.

- **Orchestrator:** e.g., Vertex AI.
- **Artifact Store:** e.g., Google Cloud Storage (GCS).
- **Experiment Tracker:** e.g., MLflow.
- **Model Deployer:** e.g., MLflow or Vertex AI Endpoints.

### Register & Switch Stacks (Critical Pattern)

```bash
# Register a production stack on GCP
zenml artifact-store register gcs_store \
  --flavor=gcp --path=gs://dealinka-zenml-artifacts

zenml orchestrator register vertex_orchestrator \
  --flavor=vertex \
  --project=dealinka-prod \
  --location=europe-west1

zenml experiment-tracker register mlflow_tracker \
  --flavor=mlflow \
  --tracking_uri=https://mlflow.internal.dealinka.com

zenml stack register production \
  -o vertex_orchestrator \
  -a gcs_store \
  -e mlflow_tracker

# Switch from dev to prod with zero code changes
zenml stack set production
```

## 3. Step Caching

Caching is critical for cost control and iteration speed. ZenML caches steps based on input artifacts and source code hashes.

```python
from zenml import step

# Caching ON by default — recommended for preprocessing
@step
def preprocess_data(raw_data: pd.DataFrame) -> pd.DataFrame:
    return raw_data.dropna()

# Override: disable cache for data ingestion steps (always fetch fresh data)
@step(enable_cache=False)
def ingest_from_bigquery() -> pd.DataFrame:
    return bq_client.query("SELECT * FROM gold.feature_mart LIMIT 10000").to_dataframe()
```

> **Rule:** Set `enable_cache=False` only for data ingestion steps. All downstream steps (preprocessing, training, evaluation) should benefit from caching.

## 4. Step Operators (GPU Training)

For compute-intensive steps, use **Vertex AI Step Operators** to run specific steps on dedicated hardware without running the entire pipeline on GPU.

```python
from zenml import step

@step(step_operator="vertex_gpu_operator")
def train_embedding_model(data: pd.DataFrame) -> bytes:
    # This step runs on a T4 GPU on Vertex AI
    # All other steps run serverlessly
    pass
```

## 5. Model Control Plane

Use ZenML's Model Control Plane to link pipeline runs to a specific model version for full lineage.

```python
from zenml import step, pipeline, Model

model = Model(name="matching_model", version="1.2.0")

@pipeline(model=model)
def matching_pipeline():
    data = ingest_from_bigquery()
    trained = train_matching_model(data)
    evaluate_model(trained)
```

## 6. Ecosystem Integration

ZenML is designed to unify the MLOps landscape.

### Integration with Vertex AI
- Use the **Vertex AI Orchestrator** to run steps as serverless jobs.
- Use **Vertex AI Step Operators** for resource-intensive steps (e.g., GPU training).

### Integration with MLflow
- Configure an **MLflow Experiment Tracker** in your stack to automatically log parameters and metrics from ZenML steps.
- Use the **MLflow Model Deployer** to serve models directly from transition stages.

### Integration with BigQuery
- Use BigQuery as a **Feature Store** or source for data ingestion steps.
- Trigger BQML training as a modular ZenML step for warehouse-native modeling.
- **Always consume from the Gold layer** — never read from Bronze or Silver in a ZenML step.

---

**Senior MLOps Architect Summary:**
ZenML's `zenml stack set` pattern is the single most important tooling feature for Dealinka. It allows the same pipeline code to run locally for development and on Vertex AI for production with zero code changes, which is critical for rapid iteration while maintaining production-grade reliability.

