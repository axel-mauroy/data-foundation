---
name: dbt (Data Build Tool)
description: Best practices for SQL-centric data modeling, testing, documentation, and the Semantic Layer within the MLOps pipeline at Dealinka.
---

# dbt Best Practices — Dealinka

dbt transforms raw BigQuery data into Gold-layer Feature Marts and business-consistent metrics. It covers two distinct responsibilities: **data transformation** (Medallion layers) and **metric governance** (Semantic Layer).

---

## 🧠 Chain-of-Thought: Before Marking Any dbt Model Production-Ready

Run through this checklist **in order** before merging a new or modified dbt model:

1. **Is the model in the right layer?** `stg_` (Bronze) → `int_` (Silver) → `mart_` (Gold).
2. **Is the schema contract enforced?** Add `contract: enforced: true` to every Bronze model.
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
    lower(trim(category))        as category,
    cast(quantity_kg as float64) as quantity_kg,
    lower(trim(condition))       as condition,
    timestamp(declared_at)       as declared_at,
    cast(expiry_days as int64)   as expiry_days
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

## 📐 Semantic Layer & MetricFlow (dbt-core)

> **Philosophy:** The Semantic Layer sits **on top of the Gold layer**. It centralizes metric definitions so that every tool queries the same numbers — eliminating "metric soup".

### 8.1 The "Normalized Marts" Philosophy
- **Frozen Rollups (Old way):** Creating specific tables for every metric combination (e.g., `fct_monthly_revenue_by_region`).
- **Semantic Layer (New way):** Keep marts **normalized** (e.g., `mart_orders`). Let MetricFlow handle the "denormalization on-the-fly". Since Dealinka uses the Semantic Layer, `mart_feature_matching` should be normalized — one row per declaration, all raw features present, no pre-aggregated metrics.

---

### 8.2 Components: Defining the Graph Nodes
A **semantic model** is a YAML wrapper on a dbt model. It declares entities, dimensions, and measures.

**Entity types (Keys for Joins):**
| Type | Meaning |
| :--- | :--- |
| `primary` | One record per row, all records present |
| `unique` | One record per row, may be a subset |
| `foreign` | Zero to many occurrences per key |
| `natural` | Real-world composite identifier |

```yaml
# models/marts/matching/semantic/sem_declarations.yml
semantic_models:
  - name: stock_declarations
    description: One row per stock declaration event.
    model: ref('mart_feature_matching')

    entities:
      - name: declaration
        type: primary
        expr: declaration_id
      - name: company
        type: foreign
        expr: company_id

    dimensions:
      - name: category
        type: categorical
      - name: declared_at
        type: time
        type_params:
          time_granularity: day
      - name: region
        type: categorical

    measures:
      - name: total_quantity_kg
        agg: sum
        expr: quantity_kg
        description: Total declared stock weight.
      - name: declaration_count
        agg: count_distinct
        expr: declaration_id
```

---

### 8.3 Metric Types — 5 Types to Know

❌ **WRONG — writing metrics as raw SQL in a dbt model:**
```sql
-- models/marts/mart_matching_rate.sql
select
    category,
    countif(was_matched_label = 1) / count(*) as matching_rate
from mart_feature_matching
group by category
```
*This duplicates logic across models — if the definition changes, every copy breaks.*

✅ **CORRECT — centrally defined metrics:**

```yaml
# models/marts/matching/semantic/metrics.yml
metrics:
  # 1. SIMPLE — direct aggregation of a measure
  - name: total_declared_stock_kg
    type: simple
    label: "Total Declared Stock (kg)"
    type_params:
      measure: total_quantity_kg

  # 2. RATIO — numerator / denominator
  - name: matching_rate
    type: ratio
    label: "Matching Rate"
    type_params:
      numerator: matched_declarations
      denominator: declaration_count

  # 3. DERIVED — arithmetic on other metrics
  - name: internal_matching_gap
    type: derived
    label: "Internal Matching Gap"
    type_params:
      expr: total_potential_matches - matched_declarations
      metrics:
        - name: total_potential_matches
        - name: matched_declarations

  # 4. CUMULATIVE — running total within a window
  - name: cumulative_declarations_30d
    type: cumulative
    label: "Declarations (rolling 30d)"
    type_params:
      measure: declaration_count
      window: 30 days

  # 5. CONVERSION — path from base event to success
  - name: declaration_to_match_conversion
    type: conversion
    label: "Declaration → Match Conv"
    type_params:
      base_measure: {name: declaration_count}
      conversion_measure: {name: matched_declarations}
      entity: declaration
      window: 48 hours
```

---

### 8.4 Semantic Organization & Naming
**Dealinka Preference:** Use **Parallel** structure under `models/marts/<domain>/semantic/` to separate logical modeling from semantic declaration.

- **Prefix:** `sem_` (e.g., `sem_orders.yml`).
- **Measures:** Use descriptive names like `total_revenue`, `count_orders`.
- **Dimensions:** Use singular nouns for categorical dimensions (e.g., `category`).
- **Time Dimensions:** Use `metric_time` as the standard alias in queries.

---

### 8.5 Validation & Local Development (dbt-core)
In `dbt-core`, the `mf` CLI is being replaced by `dbt sl`. Use these commands:

```bash
# 1. Generate the semantic manifest
dbt parse

# 2. Query a metric locally (verifies entire join graph + SQL generation)
dbt sl query --metrics matching_rate \
             --group-by category,declared_at__day \
             --where "category = 'textile'"

# 3. List available dimensions for a metric
dbt sl list dimensions --metrics matching_rate
```

---

### 8.6 Refactoring Flow: From Rollup to Metric
Follow this CoT when replacing a "frozen" SQL rollup:
1. **Identify the mart:** Find the table supplying the current dashboard.
2. **Examine Entities:** List all join keys involved.
3. **Build Semantic Models:** Model the underlying normalized component marts.
4. **Define Metrics:** Create the specific aggregations required.
5. **Verify (Audit):** Compare `dbt sl query` output against the old SQL rollup output.
6. **Deprecate:** Point tools to the Semantic Layer and delete the old SQL model.

---

### 8.7 Advanced: Saved Queries & Exports
Groups metrics, dimensions, and filters into "ready-to-consume" nodes.

```yaml
# models/marts/matching/semantic/saved_queries.yml
saved_queries:
  - name: daily_matching_kpis
    query_params:
      metrics: [matching_rate, total_declared_stock_kg]
      group_by: [TimeDimension('declared_at', 'day'), Dimension('stock_declarations__category')]
    exports:
      - name: daily_matching_kpis_export
        config:
          export_as: table
          schema: gold_metrics
          alias: fct_daily_matching_kpis
```

> **Important:** ZenML training steps always read raw feature columns from `mart_*` Gold tables — not from the Semantic Layer API. The Semantic Layer is for **business metrics**, not ML feature vectors.

---

## 🔗 MLOps Integration Rules

- **Run `dbt build`** (not `dbt run`) in CI — it includes tests, so broken data blocks the merge.
- **Trigger via Airflow:** The nightly `daily_data_platform` DAG runs `dbt build --target prod` as the bridge between Bronze load and ZenML trigger.
- **Gold-only gate:** ZenML and BQML must **only** consume from `mart_` models. Reject any pipeline that reads from `stg_` or `raw_`.
- **Semantic Layer CI:** Add `mf validate-configs` to the CI pipeline to catch broken semantic model YAML before it reaches production.

---

**Senior MLOps Architect Summary:**
dbt is both the backbone of the "Data First" rule (Medallion layers) and the single source of truth for business metrics (Semantic Layer). A passing `dbt build` in `prod` — including semantic validations — is the gating condition for any ZenML training run or dashboard refresh.

---

## 📁 Project Structure Best Practices

> Source: [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)

The mental model: **atoms → molecules → proteins.**
- Staging (`stg_`) = **Bronze** atoms (clean, individual concepts)
- Intermediate (`int_`) = **Silver** molecules (joined, re-grained components)
- Marts (`mart_`) = **Gold** proteins (wide, business-conformed entities)

### 9.1 Canonical File Tree

```
dealinka/
├── dbt_project.yml
├── packages.yml
├── macros/
│   └── cents_to_dollars.sql
├── seeds/
│   └── category_mapping.csv
├── snapshots/
├── tests/
│   └── assert_positive_quantity_kg.sql
├── analyses/
└── models/
    ├── staging/
    │   ├── erp/
    │   │   ├── _erp__sources.yml       # source definitions
    │   │   ├── _erp__models.yml        # tests + docs
    │   │   ├── base/
    │   │   │   └── base_erp__deleted_declarations.sql
    │   │   ├── stg_erp__stock_declarations.sql
    │   │   └── stg_erp__companies.sql
    │   └── associations/
    │       ├── _associations__sources.yml
    │       ├── _associations__models.yml
    │       └── stg_associations__donation_requests.sql
    ├── intermediate/
    │   └── matching/
    │       ├── _int_matching__models.yml
    │       └── int_declarations_enriched.sql
    └── marts/
        ├── matching/
        │   ├── _matching__models.yml
        │   └── mart_feature_matching.sql
        └── monitoring/
            ├── _monitoring__models.yml
            └── fct_daily_matching_kpis.sql
```

**Naming convention: `<layer>_<source>__<entity>.sql`**
- `stg_erp__stock_declarations` — staging, ERP source, declarations entity
- `int_declarations_enriched` — intermediate, matching domain
- `mart_feature_matching` — Gold mart, ML consumption

---

### 9.2 Staging Layer (Bronze) — Rules

**Purpose:** Create the cleanest, most faithful representation of a source table. One staging model per source table. This is the **Bronze** layer where schema is enforced.

**✅ Do in staging:**
```sql
-- stg_erp__stock_declarations.sql
with source as (
    select * from {{ source('erp', 'stock_declarations') }}
),
renamed as (
    select
        -- ids
        id                           as declaration_id,
        company_id,
        -- strings
        lower(trim(category))        as category,
        lower(trim(condition))       as condition,
        -- numerics
        cast(quantity_kg as float64) as quantity_kg,
        cast(expiry_days as int64)   as expiry_days,
        -- timestamps
        timestamp(declared_at)       as declared_at
    from source
    where id is not null
)
select * from renamed
```

**❌ Never in staging:**
| Anti-pattern | Why |
| :--- | :--- |
| Joins between sources | Creates duplicated computation and confusing grain — use intermediate for this |
| Aggregations / `group by` | Staging must preserve source grain for all downstream users |
| Business logic / metric calculation | Belongs in intermediate or marts |

**Materialization:** Always `view`. Set globally in `dbt_project.yml`:
```yaml
models:
  dealinka:
    staging:
      +materialized: view
```

**Base models** — the only justified joins at staging level:
```sql
-- base/base_erp__deleted_declarations.sql  (handles soft-delete pattern)
with source as (
    select * from {{ source('erp', 'declaration_deletes') }}
)
select id as declaration_id, deleted_at from source

-- stg_erp__stock_declarations.sql then joins the base model to mark deletes
left join {{ ref('base_erp__deleted_declarations') }} using (declaration_id)
```
Use base models only for: **joining delete tables** and **unioning identical schemas from multiple regions**.

---

### 9.3 Intermediate Layer (Silver) — Rules

**Purpose:** Purpose-built transformation steps — re-graining, structural simplification, isolating complex logic. Not exposed to end users. This is the **Silver** layer.

**✅ Good intermediate patterns:**
- **Re-graining:** Fan out or collapse to correct composite grain before a mart join
- **Structural simplification:** Pre-join 4–6 staging models so a mart only needs 2–3 joins
- **Isolating complex logic:** Move hard-to-read pivots or Jinja loops to their own named CTE model

```sql
-- int_declarations_enriched.sql
-- purpose: pivot acceptance stats to declaration grain before the feature mart
with declarations as (
    select * from {{ ref('stg_erp__stock_declarations') }}
),
association_stats as (
    select
        category,
        safe_divide(countif(outcome = 'accepted'), count(*)) as acceptance_rate,
        avg(transport_cost_eur) as avg_transport_cost_eur
    from {{ ref('stg_associations__donation_requests') }}
    group by category
)
select
    d.*,
    a.acceptance_rate,
    a.avg_transport_cost_eur
from declarations d
left join association_stats a using (category)
```

**DAG shape rule: arrowhead pointing right.**
- ✅ Multiple inputs into a model = expected
- ❌ Multiple outputs from one model = red flag — split into separate models

**Materialization:**
| Option | When to use |
| :--- | :--- |
| `ephemeral` (default) | Start here — keeps warehouse clean, simplest setup |
| `view` in a custom schema | When you need to inspect intermediate outputs during dev |
| Never `table` | Intermediates are not user-facing — no need to persist |

```yaml
# dbt_project.yml
models:
  dealinka:
    intermediate:
      +materialized: ephemeral
      +schema: intermediate    # or omit for ephemeral
```

---

### 9.4 Marts Layer (Gold) — Rules

**Purpose:** Wide, business-conformed entities that end users, BQML, and ZenML consume. This is the **Gold** layer.

**Materialization progression (start simple, add complexity only when needed):**
1. Start with `view` — no storage cost, always fresh
2. Promote to `table` — when the view takes too long to query
3. Promote to `incremental` — when the table takes too long to build

```yaml
# dbt_project.yml
models:
  dealinka:
    marts:
      +materialized: table
      +partition_by:
        field: declared_at
        data_type: timestamp
      +cluster_by: [category, region]
```

**Semantic Layer impact on mart design:**

| Using Semantic Layer? | Mart design |
| :--- | :--- |
| **Yes** (Dealinka) | **Normalized** — keep entities separate, let MetricFlow handle joins and aggregations |
| **No** | **Denormalized** — heavy pre-joins and rollups expected in the mart |

Since Dealinka uses the Semantic Layer, `mart_feature_matching` should be **normalized** — one row per declaration, all raw features present, no pre-aggregated metrics. Metrics live in the Semantic Layer, not the mart SQL.

```yaml
models:
  dealinka:
    marts:
      +meta:
        ml_consumable: true     # custom tag — signals ZenML/BQML can read this
        pii_cleared: true       # signals PII was stripped at staging
```

---

### 9.5 YAML Configuration — Placement Rules

| File | Location | Purpose |
| :--- | :--- | :--- |
| `_<source>__sources.yml` | `staging/<source>/` | Declares raw source tables |
| `_<source>__models.yml` | `staging/<source>/` | Tests + docs for staging models |
| `_int_<domain>__models.yml` | `intermediate/<domain>/` | Tests + docs for intermediates |
| `_<domain>__models.yml` | `marts/<domain>/` | Tests + docs for marts |

**Convention:** Prefix YAML config files with `_` so they sort to the top in every directory and are immediately distinguishable from `.sql` model files.

---

**Senior MLOps Architect Summary:**
By moving from pre-computed rollups to dynamic metrics, we eliminate "logic drift" across teams. In an MLOps context, this ensures that the "Performance Metrics" tracked in MLflow (e.g., matching rate) are calculated using the exact same code as the Business Dashboards.


