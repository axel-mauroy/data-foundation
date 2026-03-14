---
name: dbt (Data Build Tool)
description: Best practices for SQL-centric data modeling, testing, and documentation within the MLOps pipeline.
---

# dbt Best Practices Guide

dbt (data build tool) enables data analysts and engineers to transform data in their warehouse using simple select statements. In an MLOps context, dbt is critical for building the "Data Foundation" upon which models are trained.

## 1. Modular Data Modeling

Follow a layered architecture to ensure maintainability and clarity.

### Layered Architecture
- **Staging (`stg_`):** Clean, rename, and type-cast raw data. One staging model per raw source.
- **Intermediate (`int_`):** Complex logic, joins, and aggregations that are shared across multiple models.
- **Mart/Core (`fct_`, `dim_`):** Business-ready entities. For MLOps, this includes the **Feature Store** source tables.

## 2. Testing & Data Quality

dbt tests provide the first line of defense against data quality issues.

### Generic Tests
- **`unique`:** Every feature table must have a unique primary key.
- **`not_null`:** Critical features must not contain nulls unless explicitly handled in preprocessing.
- **`relationships`:** Ensure referential integrity between training data and lookup tables.

### Singular Tests
- Use custom SQL for domain-specific validation (e.g., age must be positive, prices must be within range).

## 3. Documentation & Lineage

Transparency is key for reproducible machine learning.

- **`schema.yml`:** Document every column's meaning and source.
- **Lineage Graphs:** Use dbt's lineage functionality to understand how a specific model metric is derived from raw data.
- **Exposure Management:** Define "Exposures" in dbt to track which ML models depend on specific dbt models.

## 4. Performance Optimization

- **Incremental Models:** Use `incremental` materialization for large event logs to reduce compute costs and latency.
- **Clustering & Partitioning:** Align dbt materializations with BigQuery partitioning strategies to optimize query performance for downstream ML training.

## 5. Data Contracts (dbt 1.5+)

For client ERP feeds arriving in inconsistent formats, enforce **Data Contracts** at the Silver layer to prevent schema drift from propagating downstream.

```yaml
# models/silver/schema.yml
models:
  - name: stg_company_inventory
    config:
      contract:
        enforced: true  # Fails if upstream schema changes break expectations
    columns:
      - name: sku_id
        data_type: string
        constraints:
          - type: not_null
          - type: unique
      - name: stock_quantity
        data_type: int64
        constraints:
          - type: not_null
```

## 6. PII & RGPD Compliance

Dealinka handles company contacts and association profiles that may contain personal data under RGPD (French GDPR).

- **Tag Sensitive Columns:** Use `meta` tags in `schema.yml` to mark PII fields.
- **BigQuery Column-Level Security:** Use dbt to create authorized views that mask PII for downstream non-privileged consumers.
- **Never expose PII in Gold Feature Marts** — strip or hash identifiers before writing to ZenML-consumable tables.

```yaml
# schema.yml — PII tagging example
columns:
  - name: contact_email
    description: Primary contact for the company account.
    meta:
      pii: true
      rgpd_category: contact_data
      masking_policy: email_mask
```

## 7. MLOps Integration

- **Feature Store Source:** dbt should produce the flattened tables or views that Vertex AI or BQML consume.
- **CI/CD:** Run `dbt build` (which includes `run` + `test`) in your CI pipeline before allowing any code to be merged.
- **Gold Layer Gate:** ZenML and BQML pipelines must **only** consume from `mart/` (Gold) models — never from `staging/` or `intermediate/`.
- **Automation:** Trigger dbt jobs via Airflow or Cloud Composer upon fresh data arrival from client ERP feeds.

---

**Senior MLOps Architect Summary:**
dbt is the backbone of the "Data First" rule. By enforcing modularity, testing, and lineage, dbt ensures that the training data is reliable, documented, and reproducible.
