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

## 3. Ecosystem Integration

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
