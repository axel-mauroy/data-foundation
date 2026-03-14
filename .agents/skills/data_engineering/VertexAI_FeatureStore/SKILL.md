---
name: Vertex AI Feature Store
description: Best practices for centralized, point-in-time correct feature management to prevent training-serving skew and data leakage.
---

# Vertex AI Feature Store Best Practices Guide

Vertex AI Feature Store is a managed service for storing, serving, and sharing ML features. It is the critical bridge between the data platform (dbt Gold marts) and model serving, ensuring **point-in-time correctness** and eliminating training-serving skew.

> [!IMPORTANT]
> **The Feature Store is the single source of truth for all ML features.**
> Neither model training nor the serving API should compute features independently. All features are computed once (by dbt/Dataflow) and served from the Feature Store.

## 1. Core Concepts

- **Feature Group:** A logical grouping of features, backed by a BigQuery table.
- **Feature:** An individual column within a Feature Group (e.g., `association_acceptance_rate_30d`).
- **Online Store:** A low-latency (sub-10ms) key-value store for real-time serving.
- **Offline Store:** BigQuery-backed historical feature retrieval for batch training.

## 2. Point-in-Time Correctness (Critical for ML)

Point-in-time retrieval prevents **data leakage** by ensuring that training examples only use feature values that were available at the time the label was generated.

```python
from google.cloud import aiplatform

aiplatform.init(project="dealinka-prod", location="europe-west1")

feature_store = aiplatform.FeatureStore("matching_feature_store")
entity_type = feature_store.get_entity_type("association")

# Training data retrieval: what did we know about each association
# at the exact moment each stock declaration was made?
training_df = entity_type.read_feature_values(
    entity_ids=stock_events["association_id"].tolist(),
    feature_selector=feature_selector,
    read_options={"start_time": stock_events["declared_at"]},  # point-in-time
)
```

## 3. Feature Group from BigQuery (dbt Integration)

The cleanest pattern: dbt writes to BigQuery Gold tables, Feature Store reads from them.

```python
from google.cloud.aiplatform import FeatureGroup

# Create Feature Group backed by a dbt Gold mart
feature_group = FeatureGroup.create(
    name="association_profile",
    source=FeatureGroup.BigQuerySource(
        uri="bq://dealinka-prod.gold.dim_association_profile",
        entity_id_columns=["association_id"],
    ),
    project="dealinka-prod",
    location="europe-west1",
)
```

## 4. Online Serving (Real-Time Inference)

For the Matching model (UC1), the Robyn API calls the Feature Store Online Store to fetch freshly computed features at inference time.

```python
from google.cloud.aiplatform_v1beta1 import FeaturestoreOnlineServingServiceClient

client = FeaturestoreOnlineServingServiceClient()

response = client.read_feature_values(
    entity_type=entity_type_path,
    entity_id="assoc_001",
    feature_selector={"id_matcher": {"ids": ["acceptance_rate_30d", "capacity_kg"]}},
)
```

## 5. Feature Registry & Governance

- **Versioning:** Tag feature groups with `version` and `owner` labels for lineage tracking.
- **Discoverability:** Use the Feature Store UI in the GCP console as a catalog for data scientists to discover available features without duplicating computation.
- **PII:** Never store raw PII (names, emails, contact info) in the Feature Store. Only store derived, anonymized features (e.g., `region_code`, `category_count`).

## 6. Ecosystem Integration

- **dbt:** dbt Gold mart tables are the source of truth. Feature groups point directly to BigQuery Gold tables.
- **ZenML:** ZenML training steps call the Feature Store **Offline** API to fetch point-in-time correct training data.
- **Robyn API:** The Robyn serving API calls the Feature Store **Online** API to retrieve features during real-time inference.
- **Great Expectations:** Validate feature distributions in the Feature Store against training baselines to detect serving skew.

---

**Data Reliability Summary (CTO):**
The Feature Store eliminates the most expensive and subtle bug in production ML: the mismatch between the data used during training and the data available at inference time. By centralizing feature computation in one place, we guarantee that every model—whether trained today or 6 months from now—uses the same, consistent feature logic.
