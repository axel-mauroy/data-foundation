---
name: dbt (Data Build Tool)
description: Best practices for SQL-centric data modeling, testing, and documentation within the MLOps pipeline at Dealinka.
---

# dbt Best Practices — Dealinka

dbt transforms raw BigQuery data into Gold-layer Feature Marts. It is the **primary tool for the Silver and Gold layers** of the Medallion architecture.

---

## 🧠 Chain-of-Thought: Before Marking Any dbt Model Production-Ready

Run through this checklist **in order** before merging a new or modified dbt model:

1. **Is the model in the right layer?** `stg_` → Silver, `mart_` / `fct_` / `dim_` → Gold. Never skip straight to Gold from raw sources.
2. **Is the schema contract enforced?** Add `contract: enforced: true` to every Silver model.
3. **Are all critical columns tested?** At least `unique` + `not_null` on the primary key; `not_null` on all feature columns.
4. **Is the lineage documented?** Every column must have a `description` in `schema.yml`.
5. **Is the Gold model ZenML-safe?** Strip PII columns before the mart layer. Never expose `contact_email`, `company_vat`, or personal identifiers.

---

## ✅ / ❌ Few-Shot Examples

### Model naming and layering

❌ **WRONG — skips staging, no layer prefix:**
```sql
-- models/declarations.sql
select * from {{ source('bronze', 'stock_declarations') }}
```

✅ **CORRECT — staging layer with prefix and type casting:**
```sql
-- models/staging/stg_stock_declarations.sql
with source as (
    select * from {{ source('bronze', 'stock_declarations') }}
)
select
    declaration_id,
    company_id,
    lower(trim(category))       as category,
    cast(quantity_kg as float64) as quantity_kg,
    lower(trim(condition))      as condition,
    timestamp(declared_at)      as declared_at,
    cast(expiry_days as int64)  as expiry_days
from source
where declaration_id is not null
  and quantity_kg > 0
```

---

### Schema contract (Silver layer)

❌ **WRONG — no contract, no tests:**
```yaml
models:
  - name: stg_stock_declarations
    columns:
      - name: declaration_id
```

✅ **CORRECT — contract enforced, tests defined:**
```yaml
# models/staging/schema.yml
models:
  - name: stg_stock_declarations
    config:
      contract:
        enforced: true
    columns:
      - name: declaration_id
        data_type: string
        description: Unique identifier for the stock declaration event.
        constraints:
          - type: not_null
          - type: unique
      - name: quantity_kg
        data_type: float64
        description: Declared weight of the stock in kilograms.
        constraints:
          - type: not_null
```

---

### Gold feature mart (ML-ready)

❌ **WRONG — exposes PII, no label column:**
```sql
-- models/marts/mart_matching.sql
select d.*, c.contact_email
from stg_stock_declarations d
join stg_companies c using (company_id)
```

✅ **CORRECT — PII stripped, label present, partitioned:**
```sql
-- models/marts/mart_feature_matching.sql
{{
  config(
    materialized = 'table',
    partition_by = {'field': 'declared_at', 'data_type': 'timestamp'},
    cluster_by   = ['category', 'region']
  )
}}
with declarations as (
    select * from {{ ref('stg_stock_declarations') }}
),
association_stats as (
    select
        association_id,
        safe_divide(countif(outcome = 'accepted'), count(*)) as acceptance_rate,
        avg(transport_cost_eur)                               as avg_transport_cost_eur
    from {{ ref('stg_donations') }}
    where matched_at >= timestamp_sub(current_timestamp(), interval 90 day)
    group by association_id
)
select
    d.declaration_id,
    d.category,
    d.quantity_kg,
    d.condition,
    d.expiry_days,
    a.acceptance_rate,
    a.avg_transport_cost_eur,
    case when don.outcome = 'accepted' then 1 else 0 end as was_matched_label
from declarations d
left join {{ ref('stg_donations') }} don using (declaration_id)
left join association_stats a using (association_id)
```

---

## 🔧 Decision Guide: Materialization Strategy

| Model size | Update frequency | Materialization |
| :--- | :--- | :--- |
| Any Silver model | Any | `view` (no storage cost, always fresh) |
| Gold mart < 10M rows | Daily | `table` (fast reads for BQML) |
| Gold mart > 10M rows | Daily | `incremental` + partition overwrite |
| Feature lookup (static) | Weekly | `table` with 7-day expiry |

---

## 🔒 PII / RGPD Compliance

**Tag sensitive columns in `schema.yml`, never let them reach Gold.**

```yaml
columns:
  - name: contact_email
    description: Primary contact — RGPD controlled.
    meta:
      pii: true
      rgpd_category: contact_data
      masking_policy: email_mask
```

**Rule:** Any column tagged `pii: true` must be excluded from `mart_` models via an explicit `EXCEPT` or by never selecting it.

---

## 🔗 MLOps Integration Rules

- **Run `dbt build`** (not `dbt run`) in CI — it includes tests, so broken data blocks the merge.
- **Trigger via Airflow:** The nightly `daily_data_platform` DAG runs `dbt build --target prod` as the bridge between Bronze load and ZenML trigger.
- **Gold-only gate:** ZenML and BQML must **only** consume from `mart_` models. Reject any pipeline that reads from `stg_` or `raw_`.

---

**Senior MLOps Architect Summary:**
dbt is the backbone of the "Data First" rule. A passing `dbt build` in `prod` is the gating condition for any ZenML training run.
