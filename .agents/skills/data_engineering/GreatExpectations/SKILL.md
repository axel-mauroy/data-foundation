---
name: Great Expectations
description: Best practices for data validation, profiling, and documentation to prevent drift and ensure model reliability.
---

# Great Expectations Best Practices Guide

Great Expectations (GX) is the leading open-source library for helping data teams eliminate pipeline debt through data testing, documentation, and profiling. **GX Core** provides a programmatic Python interface to build and run these validation workflows.

## 1. The GX Core Workflow Pattern

Every GX Core validation pipeline follows a strict 4-step pattern:
1. **Set up a GX environment** (Create a Data Context).
2. **Connect to data** (Data Source → Data Asset → Batch Definition).
3. **Define Expectations** (Declare assertions and combine into an Expectation Suite).
4. **Run Validations** (Combine Batch Definition and Suite using a Validation Definition or Checkpoint).

## 2. Expectations & Suites

An **Expectation** is a verifiable assertion about data. An **Expectation Suite** is a collection of these expectations.

### Core Expectations for ML
- **`expect_column_values_to_be_between`:** Ensure features (like normalization ranges) stay within expected bounds.
- **`expect_column_values_to_not_be_null`:** Critical for avoiding training failures or biased predictions.
- **`expect_column_values_to_be_in_set`:** Validate categorical features (e.g., matching known item categories).
- **`expect_column_kl_divergence_to_be_less_than`:** A powerful tool for detecting **Model Drift** by comparing serving distributions to training baselines.

## 3. Validation & Checkpoints

Integrate validation into every step of the lifecycle using Validation Definitions and Checkpoints. A **Validation Definition** explicitly links a returning Batch of data to an Expectation Suite. A **Checkpoint** runs one or more Validation Definitions and triggers post-validation **Actions** (e.g., sending Slack alerts, updating Data Docs).

### Checkpoints
- **Data Ingestion:** Validate raw data as it lands in the lake.
- **Preprocessing:** Run expectations after feature engineering (dbt) but before model training.
- **Inference:** Test the distribution of incoming requests to detect **Training-Serving Skew**.

## 4. Data Docs

Great Expectations automatically generates "Data Docs" — clean, human-readable documentation of your data's health rendering your Expectation Suites and Validation Results.

- **Stakeholder Transparency:** Shared docs build trust with IT Managers and Data Scientists.
- **Audit Trails:** Use Data Docs as a record of "Data Version Control" (DVC) validation status.

## 5. Deployment Strategies

- **Fail-Fast:** Configure pipelines to fail immediately if "Critical" expectations are not met.
- **Warning-Only:** Use Checkpoint Actions to send Slack/Email notifications for non-breaking drift detection where a human should review but the pipeline stays up.

## 6. BigQuery Native Datasource (GCP-Preferred Pattern)

For a GCP-native stack, avoid extracting data to Pandas before validating. Use the **BigQuery SQLAlchemy Datasource** to run expectations directly in the warehouse — no egress cost, no memory limits. This example uses the modern GX Core 1.0+ workflow:

```python
import great_expectations as gx

context = gx.get_context()

# 1. Connect to data
datasource = context.data_sources.add_or_update_sql(
    name="bigquery_gold",
    connection_string="bigquery://dealinka-prod/gold",
)
asset = datasource.add_table_asset(
    name="feature_mart_matching",
    table_name="feature_mart_matching",
)
batch_definition = asset.add_batch_definition_whole_table("full_table")

# 2. Define Expectations
suite = context.suites.add(gx.ExpectationSuite(name="matching_suite"))
suite.add_expectation(gx.expectations.ExpectColumnValuesToNotBeNull(column="sku_id"))
suite.add_expectation(gx.expectations.ExpectColumnValuesToBeBetween(
    column="stock_quantity", min_value=0
))

# 3. Create Validation Definition
validation_definition = context.validation_definitions.add(
    gx.ValidationDefinition(
        name="validate_matching_features",
        data=batch_definition,
        suite=suite,
    )
)

# 4. Run Validations
validation_results = validation_definition.run()

if not validation_results.success:
    raise ValueError("Gold layer validation failed — blocking pipeline.")
```

> **Rule:** Always use SQL-based validation on BigQuery Gold tables. Reserve Pandas-based GX for local dev/testing only.

## 7. MLOps Integration

- **dbt Integration:** Use the `dbt_expectations` package to run GX-style tests directly within dbt.
- **Vertex AI Monitoring:** Complement Vertex AI Model Monitoring with GX for granular, feature-level unit testing that cloud-native tools might miss.
- **Airflow/ZenML:** Use dedicated operators to trigger validation as a step in the orchestration pipeline.

---

**Senior MLOps Architect Summary:**
Great Expectations provides the rigorous testing framework needed to differentiate between code bugs and data degradation. It is essential for managing "Model Drift" and "Concept Drift" in production environments.
