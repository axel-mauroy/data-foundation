---
name: ZenML
description: Comprehensive guide for orchestrating MLOps workflows and unifying tools like Vertex AI and MLflow. Includes Dealinka-specific Gold-layer consumption rules.
---

# ZenML Best Practices — Dealinka

ZenML orchestrates the ML lifecycle from the Gold layer to production. It is the **only** tool that may trigger model training or deployments. It must never reach backwards into Bronze or Silver.

---

## 🧠 Chain-of-Thought: Designing a ZenML Step

Before writing **any** ZenML step, answer these questions in order:

1. **What layer does this step read from?**
   → Must be `gold.mart_*`. If the answer is anything else, stop and fix the data pipeline first.

2. **Does this step need fresh data every run?**
   → Ingestion steps: always `enable_cache=False`. Preprocessing/training: leave cache on.

3. **Is this step compute-intensive?**
   → Embedding generation or GPU training: add `step_operator="vertex_gpu_operator"`.

4. **What types does this step accept and return?**
   → Always use explicit types: `pl.DataFrame`, `bytes`, `float`. Never use untyped `dict` or `Any`.

5. **Is the pipeline linked to the Model Control Plane?**
   → Attach `model=Model(name=..., version=...)` to the `@pipeline` decorator so every run is auditable.

---

## ✅ / ❌ Few-Shot Examples

### Step: data ingestion

❌ **WRONG — reads Silver, untyped, no cache directive:**
```python
@step
def ingest():
    return bq.query("SELECT * FROM silver.stg_stock_declarations").to_dataframe()
```

✅ **CORRECT — Gold only, Polars, Arrow bridge, cache disabled:**
```python
@step(enable_cache=False)
def ingest_gold_features() -> pl.DataFrame:
    bq = bigquery.Client(project=os.environ["GCP_PROJECT"])
    return pl.from_arrow(
        bq.query(
            "SELECT * FROM `{project}.gold.mart_feature_matching` LIMIT 50000".format(
                project=os.environ["GCP_PROJECT"]
            )
        ).to_arrow()
    )
```

---

### Step: preprocessing

❌ **WRONG — mutates a pandas DataFrame in-place, no type hint:**
```python
@step
def preprocess(df):
    df["condition_encoded"] = df["condition"].map({"neuf": 2, "bon_etat": 1, "usage": 0})
    df.fillna(0, inplace=True)
    return df
```

✅ **CORRECT — immutable Polars expression chain, fully typed:**
```python
CONDITION_MAP = {"neuf": 2, "bon_etat": 1, "usage": 0}
FEATURES = ["quantity_kg", "expiry_days", "acceptance_rate", "condition_encoded"]

@step
def preprocess(df: pl.DataFrame) -> pl.DataFrame:
    return (
        df
        .drop_nulls(subset=["was_matched_label"])
        .with_columns(
            pl.col("condition").replace(CONDITION_MAP, default=0).alias("condition_encoded")
        )
        .with_columns(pl.col(FEATURES).fill_null(0.0))
    )
```

---

### Pipeline: Model Control Plane + full pipeline

❌ **WRONG — no model linkage, no type hints:**
```python
@pipeline
def train():
    data = ingest()
    model = train_model(data)
```

✅ **CORRECT — typed, versioned, tracked:**
```python
from zenml import pipeline, Model

@pipeline(model=Model(name="matching_model", version="1.0.0"))
def matching_pipeline():
    raw       = ingest_gold_features()       # pl.DataFrame
    processed = preprocess(raw)              # pl.DataFrame
    trained   = train_model(processed)       # bytes
    evaluate_and_log(trained, processed)     # None
```

---

## 🔧 Stack Registration (One-Time Setup)

```bash
# Development (local)
zenml stack register dev \
  -o local_orch \
  -a local_store \
  -e mlflow_local

# Production (Vertex AI)
zenml stack register production \
  -o vertex_orchestrator \
  -a gcs_store \
  -e mlflow_prod

# Switch with zero code change
zenml stack set production
```

**Rule:** Never hardcode the stack name in pipeline code. Always switch via `zenml stack set` or the `ZENML_STACK` env var.

---

## 🔧 Caching Rules

| Step type | Cache setting | Reason |
| :--- | :--- | :--- |
| Data ingestion (BigQuery) | `enable_cache=False` | Data changes daily — always fetch fresh |
| Preprocessing | Default (on) | Deterministic given same input |
| Training | Default (on) | Expensive — skip if inputs unchanged |
| Evaluation | Default (on) | Deterministic given same model + data |

---

## 🔧 GPU Step Operators

Use **only** for embedding generation or neural network training. All other steps run serverlessly.

```python
@step(step_operator="vertex_gpu_operator")
def generate_embeddings(df: pl.DataFrame) -> bytes:
    # Runs on T4 GPU on Vertex AI — all other steps run CPU-only
    ...
```

---

## 🔗 Ecosystem Integration Rules

| Integration | Rule |
| :--- | :--- |
| **BigQuery** | Use `bq.query().to_arrow()` → `pl.from_arrow()`. Never use `.to_dataframe()`. |
| **MLflow** | Every training step must call `infer_signature()` before logging the model. |
| **Vertex AI** | Use `vertex` orchestrator for production. Never run production pipelines on the `local` stack. |
| **Airflow** | Airflow triggers ZenML via `zenml pipeline run`. ZenML never triggers Airflow. |

---

**Senior MLOps Architect Summary:**
`zenml stack set production` is the single most important command in the MLOps workflow — it moves a fully-tested local pipeline to Vertex AI with zero code changes, which is the core of Dealinka's cost-efficient, rapid-iteration MLOps strategy.
