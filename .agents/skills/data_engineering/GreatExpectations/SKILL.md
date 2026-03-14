---
name: Great Expectations
description: Best practices for data validation, profiling, and documentation to prevent drift and ensure model reliability.
---

# Great Expectations Best Practices Guide

Great Expectations is the leading open-source library for helping data teams eliminate pipeline debt through data testing, documentation, and profiling.

## 1. Expectation Suites

Expectations are essentially "unit tests for data."

### Core Expectations for ML
- **`expect_column_values_to_be_between`:** Ensure features (like normalization ranges) stay within expected bounds.
- **`expect_column_values_to_not_be_null`:** Critical for avoiding training failures or biased predictions.
- **`expect_column_values_to_be_in_set`:** Validate categorical features (e.g., matching known item categories).
- **`expect_column_kl_divergence_to_be_less_than`:** A powerful tool for detecting **Model Drift** by comparing serving distributions to training baselines.

## 2. Validation & Checkpoints

Integrate validation into every step of the lifecycle.

### Checkpoints
- **Data Ingestion:** Validate raw data as it lands in the lake.
- **Preprocessing:** Run expectations after feature engineering (dbt) but before model training.
- **Inference:** Test the distribution of incoming requests to detect **Training-Serving Skew**.

## 3. Data Docs

Great Expectations automatically generates "Data Docs" — clean, human-readable documentation of your data's health.

- **Stakeholder Transparency:** Shared docs build trust with IT Managers and Data Scientists.
- **Audit Trails:** Use Data Docs as a record of "Data Version Control" (DVC) validation status.

## 4. Deployment Strategies

- **Fail-Fast:** Configure pipelines to fail immediately if "Critical" expectations are not met.
- **Warning-Only:** Use for non-breaking drift detection where a human should review but the pipeline stays up.

## 5. BigQuery Native Datasource (GCP-Preferred Pattern)

For a GCP-native stack, avoid extracting data to Pandas before validating. Use the **BigQuery SQLAlchemy Datasource** to run expectations directly in the warehouse — no egress cost, no memory limits.

```python
import great_expectations as gx

context = gx.get_context()

datasource = context.sources.add_or_update_sql(
    name="bigquery_gold",
    connection_string="bigquery://dealinka-prod/gold",
)

asset = datasource.add_table_asset(
    name="feature_mart_matching",
    table_name="feature_mart_matching",
)

batch = asset.add_batch_definition_whole_table("full_table")

suite = context.suites.add(gx.ExpectationSuite(name="matching_suite"))
suite.add_expectation(gx.expectations.ExpectColumnValuesToNotBeNull(column="sku_id"))
suite.add_expectation(gx.expectations.ExpectColumnValuesToBeBetween(
    column="stock_quantity", min_value=0
))

result = batch.validate(suite)
if not result.success:
    raise ValueError("Gold layer validation failed — blocking pipeline.")
```

> **Rule:** Always use SQL-based validation on BigQuery Gold tables. Reserve Pandas-based GX for local dev/testing only.

## 6. MLOps Integration

- **dbt Integration:** Use the `dbt_expectations` package to run GX-style tests directly within dbt.
- **Vertex AI Monitoring:** Complement Vertex AI Model Monitoring with GX for granular, feature-level unit testing that cloud-native tools might miss.
- **Airflow/ZenML:** Use dedicated operators to trigger validation as a step in the orchestration pipeline.

---

**Senior MLOps Architect Summary:**
Great Expectations provides the rigorous testing framework needed to differentiate between code bugs and data degradation. It is essential for managing "Model Drift" and "Concept Drift" in production environments.
