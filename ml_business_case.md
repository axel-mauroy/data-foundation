# Dealinka — Machine Learning Business Case

## Executive Summary

Dealinka's core competitive advantage is **speed and accuracy in matching surplus stock with the right associations**. Machine learning can transform the platform from a rule-based matching system into an intelligent, predictive engine that:

1. **Matches faster and more accurately** by learning from historical donation patterns.
2. **Anticipates dormant stock** before companies even declare it.
3. **Forecasts association demand** to proactively source the right products.
4. **Optimizes logistics costs** to maximize the value of each transfer.

> [!IMPORTANT]
> **A mature data platform is a non-negotiable prerequisite for any ML user story.**
> No ML model can outperform the quality of the data feeding it. Before issuing a single ML ticket, Dealinka must establish a centralized, validated, and versioned data platform in BigQuery — including the **Medallion Architecture** (Bronze → Silver → Gold), **dbt** transformation pipelines, and automated quality gates with **Great Expectations**. Without this foundation, model training will be unreliable, experiments will be non-reproducible, and production deployments will be fragile.

This document defines four ML use cases, each tied to Dealinka's value proposition and powered by the team's MLOps stack: **BigQuery ML**, **Vertex AI**, **Robyn**, **MLflow**, and **ZenML**. All use cases are gated on the completion of the data platform.

---

## Use Case 1: Intelligent Matching (Supply ↔ Demand)

### Business Problem
Today, matching surplus stock to associations relies on a rules-based algorithm. As the network grows (more companies, more associations, more product categories), this approach will not scale. Poor matches lead to rejected donations, wasted logistics, and slower cycle times.

### ML Approach

| Aspect             | Detail                                                                    |
| :----------------- | :------------------------------------------------------------------------ |
| **Type**           | Recommendation / Classification                                           |
| **Model**          | Boosted Tree Classifier (BQML) → AutoML Tables (Vertex AI) for iteration  |
| **Input Features** | Product category, volume, condition, company location, association profile (needs, capacity, past acceptance rate), seasonality |
| **Output**         | Ranked list of top-N associations for a given stock declaration           |

### Data Requirements
- Historical donation records (company, association, product type, outcome).
- Association profiles (needs, geographic coverage, capacity).
- Product metadata (category, weight, condition, regulatory constraints).

### Recommended Stack
- **Training:** **BigQuery ML** (`LOGISTIC_REG`) for a 2-minute baseline, ثم **BigQuery ML** (`AUTOML_CLASSIFIER`) if higher accuracy is needed for tabular data.
- **Serving:** **Robyn** API deployed on a **Vertex AI Endpoint** (high-performance online prediction, <50ms latency).
- **Tracking:** **MLflow** to compare matching accuracy across model iterations.
- **Orchestration:** **ZenML** pipeline triggered when new donation data is ingested.

### Expected Impact
- **Matching accuracy:** +15–25% improvement in first-match acceptance rate.
- **Cycle time:** Reduce average matching time from 48h to <12h.
- **Operational cost:** Fewer rejected donations = less wasted logistics.

---

## Use Case 2: Dormant Stock Prediction

### Business Problem
Companies often wait until inventory is already dormant before declaring it on the platform. By that point, products may have deteriorated, or the window for useful donation has narrowed. Proactive outreach to companies with predicted dormant stock creates a significant competitive advantage.

### ML Approach

| Aspect | Detail |
| :--- | :--- |
| **Type** | Time-Series Forecasting |
| **Model** | `ARIMA_PLUS` (BQML) for per-SKU forecasting |
| **Input Features** | Historical sales velocity, stock levels over time, product category, seasonality, promotional calendar |
| **Output** | Probability that a given SKU/lot will become dormant within 30/60/90 days |

### Data Requirements
- Client ERP/inventory feeds (stock levels, sales history).
- Product lifecycle metadata (launch date, promotional periods).
- Historical dormancy events (when stock was eventually declared as surplus).

### Recommended Stack
- **Training:** BigQuery ML (`ARIMA_PLUS`) for time-series forecasting directly on warehouse data.
- **Serving:** Batch prediction via `ML.PREDICT` in BigQuery (daily scheduled query).
- **Monitoring:** Vertex AI Model Monitoring for prediction drift detection (seasonal shifts).
- **Orchestration:** ZenML pipeline triggered via Cloud Scheduler on a daily cadence.

### Expected Impact
- **Proactive outreach:** Identify 30–40% of dormant stock before formal declaration.
- **Revenue:** Earlier engagement = more subscription value for the client.
- **Waste reduction:** Shorter dormancy window = better product condition for associations.

---

## Use Case 3: Demand Forecasting for Associations

### Business Problem
Associations have fluctuating needs based on seasons, events, and the populations they serve. Understanding demand patterns allows Dealinka to proactively source the right products and improve service quality for the receiving side of the marketplace.

### ML Approach

| Aspect             | Detail                                                                    |
| :----------------- | :------------------------------------------------------------------------ |
| **Type**           | Regression / Time-Series                                                  |
| **Model**          | Boosted Tree Regressor (BQML) or custom model (Vertex AI Custom Training) |
| **Input Features** | Association type, historical request patterns, geographic region, seasonality, event calendar |
| **Output**         | Predicted demand volume by product category for the next 30/60 days       |

### Data Requirements
- Historical association requests and acceptances.
- Association metadata (type, size, geographic coverage, population served).
- External signals (weather, holiday calendar, local events).

### Recommended Stack
- **Training:** BigQuery ML for baseline, Vertex AI Custom Training (PyTorch/sklearn) for complex multi-variate models.
- **Serving:** Batch prediction (weekly) stored in BigQuery for the operations team.
- **Tracking:** MLflow for experiment comparison (BQML baseline vs. custom model).
- **Orchestration:** ZenML pipeline with Vertex AI orchestrator for scalable weekly retraining.

### Expected Impact
- **Service quality:** Pre-position the right products for associations before they ask.
- **Platform stickiness:** Associations that receive well-matched goods stay active longer.
- **CSR reporting:** Richer data for client ESG dashboards.

---

## Use Case 4: Logistics Optimization

### Business Problem
Each donation transfer has a cost (transport, handling). Minimizing this cost while maximizing impact (volume donated, number of associations served) is critical to Dealinka's unit economics, especially as the platform scales across France and Europe.

### ML Approach

| Aspect             | Detail                                                                    |
| :----------------- | :------------------------------------------------------------------------ |
| **Type**           | Optimization / Regression                                                 |
| **Model**          | Linear Regression (BQML) for cost estimation, custom optimization model (Vertex AI) for route planning |
| **Input Features** | Origin/destination locations, product weight/volume, transport mode, distance, carrier rates |
| **Output**         | Optimal assignment of transfers to minimize total logistics cost          |

### Data Requirements
- Historical transfer records (origin, destination, cost, carrier, weight).
- Geographic data (warehouse/association locations).
- Carrier rate cards and SLAs.

### Recommended Stack
- **Training:** **BigQuery ML** for cost estimation baseline, **Vertex AI** for custom optimization models.
- **Serving:** **Robyn** API via **Vertex AI Endpoint** for real-time, low-latency assignment scoring.
- **Tracking:** **MLflow** to log cost-reduction metrics across model versions.
- **Orchestration:** **ZenML** to integrate logistics scoring as a step in the main matching pipeline.

### Expected Impact
- **Cost reduction:** 10–20% reduction in average transfer cost.
- **Scalability:** Automated assignment replaces manual logistics coordination.

---

## Technical Architecture

The four use cases are unified by a single MLOps stack.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ZenML (Orchestrator)                               │
│  Defines portable, reproducible pipelines across all use cases.              │
│  Manages dbt transformations, GX validation, and step dependencies.         │
├──────────┬──────────────────┬───────────────┬───────────────┬───────────────┤
│  Step 1  │     Step 2       │    Step 3     │    Step 4     │    Step 5     │
│  Ingest  │   Train (BQML    │   Evaluate    │    Deploy     │    Observe    │
│  (dbt)   │   or Vertex AI)  │   (MLflow)    │   (Robyn)     │   (Grafana)   │
└──────────┴──────────────────┴───────────────┴───────────────┴───────────────┘
                               │
                ┌──────────────┼──────────────┬──────────────┐
                ▼              ▼              ▼              ▼
         ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
         │ BigQuery   │ │ Vertex AI  │ │  Robyn     │ │  MLflow    │
         │ ML         │ │ Registry   │ │  API       │ │  Tracking  │
         │ (Baseline) │ │ (Custom)   │ │  (Serving) │ │  (Metrics) │
         └────────────┘ └────────────┘ └────────────┘ └────────────┘
```

### Stack Mapping

| Component               | Tool                        | Role                                             |
| :---------------------- | :-------------------------- | :----------------------------------------------- |
| **Data Warehouse**      | BigQuery                    | Source of truth for all features and labels      |
| **Tabular Modeling**    | BigQuery ML                 | **Baseline-first** SQL-native model creation     |
| **Complex/Unstructured**| Vertex AI                   | Custom Training and computer vision/NLP          |
| **Model Registry**      | Vertex AI Model Registry    | Centralized versioning, aliases, and deployment  |
| **High-Perf serving**   | **Robyn**                   | Rust-backed API for sub-50ms inference           |
| **Experiment Tracking** | MLflow                      | Cross-model comparison and reproducibility       |
| **Orchestration**       | ZenML                       | End-to-end pipeline definition and execution     |
| **Serving Platform**    | Vertex AI Endpoints         | Managed auto-scaling for Robyn containers        |
| **Monitoring**          | Vertex AI Model Monitoring  | Skew and drift detection in production           |

---

## KPIs & Business Impact

Each use case maps directly to Dealinka's value proposition.

| KPI                        | Use Case                       | Target              | Business Impact                                |
| :------------------------- | :----------------------------- | :------------------ | :--------------------------------------------- |
| **First-Match Acceptance Rate** | Intelligent Matching           | >85%                | Fewer rejected donations, faster cycles        |
| **Proactive Stock Identification** | Dormant Stock Prediction       | 30–40% of stock identified before declaration | Earlier engagement, better product condition |
| **Association Retention**    | Demand Forecasting             | +20% active association retention | Stronger network effect                        |
| **Average Transfer Cost**    | Logistics Optimization         | -15% reduction      | Better unit economics at scale                 |
| **Matching Cycle Time** | Intelligent Matching | <12h average (down from 48h) | Core competitive advantage |
| **ESG Reporting Accuracy** | All | Automated, ML-driven metrics | Premium service tier for clients |

---

## Stack Recommendations

The following recommendations ensure each business case is processed reliably, cost-effectively, and at scale.

### 1. Data Layer — BigQuery as the Single Source of Truth

| Recommendation | Rationale |
| :--- | :--- |
| **Centralize all data in BigQuery** | Every use case starts with data. Keeping inventory feeds, association profiles, donation history, and logistics records in a single BigQuery dataset eliminates data silos and reduces ETL complexity. |
| **Use partitioned and clustered tables** | Partition by `event_date` and cluster by `product_category` / `region` to minimize query cost and speed up model training. |
| **Implement a Feature Store** | Use **Vertex AI Feature Store** for shared, point-in-time correct features (e.g., "association acceptance rate over last 90 days"). This prevents training-serving skew and avoids duplicating feature logic across use cases. |
| **Version your datasets** | Tag training snapshots with `DVC` or BigQuery snapshot decorators (`FOR SYSTEM_TIME AS OF`) to guarantee reproducibility. |

### 2. Training Layer — Start Simple, Scale Smart

| Phase | Tool | When to Use |
| :--- | :--- | :--- |
| **Phase 1: Baseline** | BigQuery ML | First 2 minutes of any task. Use `LOGISTIC_REG` or `LINEAR_REG` to set a low-cost, fast baseline. |
| **Phase 2: Optimize** | BQML AutoML | When accuracy is insufficient. Allow 1–3 hours for training. Best for complex tabular data. |
| **Phase 3: Unstructured**| Vertex AI | Directly use Vertex AI AutoML or Custom Training for Images, Video, and complex NLP. |

> [!TIP]
> **Do not skip Phase 1.** BQML baselines are critical for setting realistic expectations and identifying data quality issues before investing in more expensive training.

### 3. Experiment Tracking — MLflow for Visibility

- **Deploy a centralized MLflow server**: Backed by Cloud SQL (PostgreSQL) + GCS for artifacts. This gives the entire team a single pane of glass for experiment comparison.
- **Log everything, including BQML**: Wrap BQML evaluation queries in lightweight Python scripts that log metrics to MLflow. This ensures BQML and Vertex AI models are compared in the same place.
- **Enforce model signatures**: Every model logged to MLflow must include an `infer_signature()` call. This prevents schema mismatches during deployment.
- **Use stage transitions**: Promote models through `Staging → Production → Archived`. Trigger automated validation (accuracy thresholds, latency checks) on each transition.

### 4. Serving Layer — Vertex AI Endpoints

- **Intelligent Matching** (**Online**): Deploy a **Robyn** container to a Vertex AI Endpoint (<50ms p95 latency).
- **Dormant Stock Prediction** (**Batch**): Use `ML.PREDICT` in BigQuery (no endpoint cost).
- **Demand Forecasting** (**Batch**): Use `ML.PREDICT` in BigQuery (no endpoint cost).
- **Logistics Optimization** (**Online**): Deploy as a **Robyn** API step or endpoint for real-time cost assignment.

> [!IMPORTANT]
> **Use Case 1 (Matching) is the only use case that requires an online endpoint.** Start batch-first for the other three to minimize serving costs.

### 5. Orchestration — ZenML for Reproducibility

- **One pipeline per use case**: Keep pipelines independent. A failure in the Dormant Stock pipeline should never block the Matching pipeline.
- **Use the Vertex AI orchestrator for production**: Run pipelines as serverless Vertex AI Custom Jobs. No cluster to manage, pay-per-use.
- **Use the local orchestrator for development**: Developers iterate locally, then push to production with a single stack swap (`zenml stack set production`).
- **Trigger pipelines on data events**: Use **Cloud Scheduler** for batch pipelines (daily/weekly). Use **Eventarc** to trigger the matching pipeline when a new stock declaration lands in BigQuery.

### 6. Monitoring — Detect Drift Before It Hurts

| Signal | Tool | Threshold | Action |
| :--- | :--- | :--- | :--- |
| **Training-Serving Skew** | Vertex AI Model Monitoring | Feature distribution divergence > 0.3 (Jensen-Shannon) | Alert the team + trigger a retraining pipeline. |
| **Prediction Drift** | Vertex AI Model Monitoring | Prediction distribution shift > 0.2 over 7 days | Investigate data quality. If confirmed, retrain. |
| **Model Staleness** | ZenML Pipeline Metadata | Model age > 30 days without retraining | Auto-trigger the retraining pipeline via Cloud Scheduler. |
| **Serving Latency** | Cloud Monitoring | p95 latency > 500ms on the matching endpoint | Scale up endpoint nodes or optimize model size. |

> [!CAUTION]
> **Do not wait for accuracy to drop in production.** By the time you notice, hundreds of poor matches may have already been made. Proactive monitoring is non-negotiable.

### 7. Cost Optimization

| Strategy | Estimated Savings |
| :--- | :--- |
| **Use BQML for prototyping** instead of Vertex AI Custom Training | 60–80% lower training cost in early phases (BigQuery flat-rate slots vs. GPU hours). |
| **Batch-first serving** for 3 out of 4 use cases | Avoid Endpoint costs (~€0.10/node-hour) for use cases that don't need real-time. |
| **ZenML caching** | Skip unchanged pipeline steps → 30–50% reduction in pipeline execution time and cost. |
| **BigQuery reservations** | Move to flat-rate pricing once training queries exceed ~$5k/month on-demand. |
| **Vertex AI committed-use discounts** | Negotiate 1-year CUDs for the matching endpoint once traffic stabilizes. |

### 8. Phased Rollout Plan

```
Phase 1 (Month 1–2)     Phase 2 (Month 3–4)     Phase 3 (Year 1)
─────────────────────    ─────────────────────    ─────────────────────
• BigQuery data setup    • Vertex AI AutoML       • Vertex AI Monitoring
• BQML baselines (UC1)   • Online Endpoint (UC1)  • Demand Forecasting
• MLflow server deploy   • Dormant Stock (UC2)    • Logistics Opt. (UC4)
• ZenML local pipelines  • ZenML prod pipelines   • Full CI/CD + alerts
```

| Phase       | Focus                                    | Risk Level                                     |
| :---------- | :--------------------------------------- | :--------------------------------------------- |
| **Phase 1** | Data foundation + BQML prototypes        | 🟢 Low — SQL-only, no infra complexity         |
| **Phase 2** | First production model + batch use case  | 🟡 Medium — Endpoint management, monitoring setup |
| **Phase 3** | Full ecosystem + advanced use cases      | 🔴 Higher — Multi-model orchestration, cost management |

---

## 9. The Extended MLOps Core — Established Skills

The core stack is supported by a suite of established skills and specialized tools that close gaps in **data quality**, **real-time processing**, **semantic understanding**, and **infrastructure management**. The following tools are integrated into our project standard.

### 1. Data Quality & Validation — Great Expectations

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Garbage in, garbage out. Client inventory feeds arrive in inconsistent formats, with missing fields, duplicates, and schema drift. No amount of model tuning will fix bad data. |
| **Tool** | [**Great Expectations**](https://greatexpectations.io/) — Open-source data validation framework. |
| **Why** | Define "expectations" (e.g., `product_category IS NOT NULL`, `weight > 0`) that run automatically every time data is ingested. Failures block the pipeline before bad data reaches training. |
| **Integration** | Plug directly into ZenML as a **Data Validator** step. Results are logged as artifacts alongside model experiments. |
| **Use Cases Served** | All four — data quality is the foundation of every model. |

### 2. Real-Time Event Streaming — Apache Kafka (or Google Pub/Sub)

| Aspect | Detail |
| :--- | :--- |
| **Problem** | The matching use case (UC1) currently relies on batch data landing in BigQuery. As Dealinka scales, companies will expect **instant matching** the moment stock is declared. |
| **Tool** | [**Google Pub/Sub**](https://cloud.google.com/pubsub) (managed, GCP-native) or **Apache Kafka** (Confluent Cloud for more control). |
| **Why** | Pub/Sub can stream stock declarations in real-time to a Vertex AI Endpoint and simultaneously write to BigQuery for retraining. This unlocks sub-second matching triggers. |
| **Architecture** | `Company App → Pub/Sub → Cloud Function → Vertex AI Endpoint (match) → Pub/Sub → Notification to Association` |
| **Use Cases Served** | UC1 (Intelligent Matching), UC4 (Logistics — real-time cost scoring). |

### 3. NLP & Semantic Understanding — Vertex AI Embeddings + LangChain

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Product descriptions from companies are free-text, multilingual, and inconsistent ("T-shirt homme XL" vs. "Men's tee, extra large"). Rules-based category matching will miss semantic equivalences. |
| **Tool** | [**Vertex AI Text Embeddings API**](https://cloud.google.com/vertex-ai/docs/generative-ai/embeddings/get-text-embeddings) + [**LangChain**](https://www.langchain.com/) for orchestrating LLM-powered workflows. |
| **Why** | Convert product descriptions and association need profiles into **vector embeddings**. Semantic similarity replaces brittle keyword matching and handles multilingual inputs natively. |
| **Integration** | Use as a preprocessing step in the ZenML matching pipeline: embed both supply and demand, then feed cosine-similarity scores as features to the matching model. |
| **Use Cases Served** | UC1 (Intelligent Matching — dramatically improves cross-language, cross-category matching). |

### 4. Vector Database — Weaviate or Vertex AI Vector Search

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Once product and association profiles are embedded, you need an efficient way to perform nearest-neighbor retrieval at scale (thousands of associations × thousands of stock items). |
| **Tool** | [**Vertex AI Vector Search**](https://cloud.google.com/vertex-ai/docs/vector-search/overview) (GCP-native, managed) or [**Weaviate**](https://weaviate.io/) (open-source, more flexible). |
| **Why** | Sub-millisecond approximate nearest neighbor (ANN) search across millions of embeddings. This replaces exhaustive SQL `JOIN`s for candidate generation. |
| **Architecture** | `Stock Declaration → Embed → Vector Search (top-50 candidates) → Matching Model (rerank) → Top-5 Recommendations` |
| **Use Cases Served** | UC1 (Intelligent Matching — two-stage retrieval + reranking). |

### 5. Data Orchestration & Transformation — dbt (data build tool)

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Raw data in BigQuery needs to be transformed into clean, tested, documented feature tables before models can consume it. Ad-hoc SQL scripts are unmaintainable. |
| **Tool** | [**dbt**](https://www.getdbt.com/) — SQL-first transformation framework with testing, documentation, and lineage. |
| **Why** | dbt brings software engineering best practices (version control, CI/CD, testing) to your SQL transformations. It creates a clean **staging → intermediate → mart** layer that BQML and Vertex AI consume. |
| **Integration** | Run dbt models as a ZenML step before training. Use dbt tests (`not_null`, `unique`, `accepted_values`) as a lightweight alternative to Great Expectations for SQL-native teams. |
| **Use Cases Served** | All four — dbt is the bridge between raw data and ML-ready features. |

### 6. Observability & Incident Management — Grafana + PagerDuty

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Vertex AI Model Monitoring detects drift, but the operations team needs a unified dashboard and an alerting workflow that goes beyond email. |
| **Tool** | [**Grafana**](https://grafana.com/) (dashboards) + [**PagerDuty**](https://www.pagerduty.com/) (incident routing). |
| **Why** | Grafana aggregates metrics from Vertex AI, BigQuery, Cloud Monitoring, and MLflow into a single real-time dashboard. PagerDuty ensures the right person is paged at the right time with escalation policies. |
| **Integration** | Cloud Monitoring → Grafana (via Prometheus exporter) → PagerDuty (via webhook on critical alerts). |
| **Use Cases Served** | All production models — operational visibility is critical as model count grows. |

### 7. Infrastructure as Code — Terraform

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Manually provisioning BigQuery datasets, Vertex AI endpoints, Pub/Sub topics, and IAM roles does not scale and introduces human error. |
| **Tool** | [**Terraform**](https://www.terraform.io/) with the Google Cloud provider. |
| **Why** | Define all cloud infrastructure (datasets, endpoints, monitoring jobs, service accounts) as code. Changes are reviewed via pull requests, versioned in Git, and applied consistently across environments (dev, staging, prod). |
| **Integration** | Terraform provisions the infrastructure, ZenML orchestrates the ML workflows on top of it. |
| **Use Cases Served** | All — infrastructure reliability is a prerequisite for production ML. |

### 8. LLM-Powered Reporting — Vertex AI Gemini

| Aspect | Detail |
| :--- | :--- |
| **Problem** | Dealinka's clients need ESG/CSR reports. Today, these are likely manual or templated. ML-generated data (matching stats, waste reduction metrics) is underutilized. |
| **Tool** | [**Vertex AI Gemini API**](https://cloud.google.com/vertex-ai/docs/generative-ai/learn/overview) — Google's multimodal LLM. |
| **Why** | Automatically generate natural-language ESG reports from structured ML outputs. "In Q1 2026, your donations prevented 12 tons of waste and served 45 associations across 8 regions." |
| **Integration** | A ZenML step at the end of the matching pipeline: aggregate donation metrics → prompt Gemini → generate PDF report → email to client. |
| **Use Cases Served** | Directly supports the **ESG Reporting Accuracy** KPI and enables a premium service tier. |

---

### Revised Full Stack Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                          ZenML (Orchestrator)                        │
├─────────┬──────────┬──────────┬──────────┬──────────┬────────────────┤
│  dbt    │  Great   │  Train   │  Evaluate│  Deploy  │  Report        │
│  (ELT)  │  Expect. │  (BQML/  │  (MLflow)│  (Vertex │  (Gemini)      │
│         │  (Valid.)│  Vertex) │         │  AI)     │                │
└─────────┴──────────┴──────────┴──────────┴──────────┴────────────────┘
     │          │           │          │          │           │
     ▼          ▼           ▼          ▼          ▼           ▼
┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌──────────┐
│BigQuery ││Feature  ││Vertex AI││MLflow   ││Vertex AI││Vertex AI │
│(DWH)    ││Store    ││(Train)  ││(Track)  ││Endpoint ││Gemini    │
└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└──────────┘
     │                                           │
     ▼                                           ▼
┌─────────┐                                ┌──────────┐
│Pub/Sub  │ ◄── Real-time stock events ──► │Vector    │
│(Stream) │                                │Search    │
└─────────┘                                └──────────┘
     │                                           │
     └────────────►  Grafana + PagerDuty  ◄──────┘
                    (Observability)
```

### Tool Priority Matrix

| Tool                       | Priority         | Status            | Effort          | Impact        |
| -------------------------- | ---------------- | ----------------  | --------------- | ------------- |
| **dbt**                    | 🔴 Critical      | ✅ Established     | Low             | High          |
| **Great Expectations**     | 🔴 Critical      | ✅ Established     | Low             | High          |
| **Terraform**              | 🔴 Critical      | ✅ Established     | Medium          | High          |
| **Robyn (APA API)**        | 🔴 Critical      | ✅ Established     | Low             | Very High     |
| **Pub/Sub**                | 🟡 Important     | ✅ Established     | Medium          | High          |
| **Vertex AI Embeddings**   | 🟡 Important     | ⏳ Planned         | Medium          | Very High     |
| **Vector Search**          | 🟡 Important     | ⏳ Planned         | Medium          | High          |
| **Grafana + PagerDuty**    | 🟡 Important     | ⏳ Planned         | Low             | Medium        |
| **Vertex AI Gemini**       | 🟢 Nice to Have  | ⏳ Planned         | Low             | Medium        |

---

## 10. Orchestrator Selection: ZenML vs. Airflow 3.1

Choosing the right orchestrator is critical for balancing development velocity with production reliability. While **Apache Airflow 3.1** is a powerful general-purpose tool, **ZenML** (backed by Vertex AI) remains the most pragmatic choice for Dealinka.

| Feature | ZenML + Vertex AI | Apache Airflow 3.1 (AIP-61/72) |
| :--- | :--- | :--- |
| **ML Abstractions** | **Native.** Steps are designed for model training, data validation, and tracking. | **General.** Designed for generic task-based DAGs; requires custom operators for ML. |
| **GCP Integration** | **Direct.** Seamlessly triggers serverless Vertex AI Custom Jobs. | **Complex.** Requires managing Cloud Composer (GKE) or complex KubernetesPodOperators. |
| **Local-to-Cloud** | **Zero Code Change.** Swap stacks (`zenml stack set`) to move from local to GCP. | **Heavy Friction.** Local development rarely mirrors the complexities of a production Airflow cluster. |
| **Data Versioning** | **Built-in.** Automatically versions artifacts and links them to specific pipeline runs. | **Manual.** Requires external tools (DVC/BigQuery Snapshots) managed within tasks. |
| **GenAI Support** | **Specialized.** Integrates with Vertex AI Gemini and Vector Search natively. | **New (HITL).** Introduces Human-in-the-Loop patterns, but lacks the end-to-end ML lifecycle. |

### Decision Summary
We prioritize **ZenML** as our primary MLOps orchestrator. Its ability to abstract away infrastructure management (via Vertex AI) allows the team to focus on model logic rather than DAG maintenance or GKE cluster management. We will leverage ZenML's modularity to integrate with Airflow 3.1 if complex, non-ML enterprise data pipelines (ETL) are required in the future.

### How to Scale
1. **ZenML Remote Stacks:** Provision production stacks using Terraform to include Vertex AI Orchestrators and Artifact Stores.
2. **Modular Steps:** Ensure all steps use ZenML `ModelControl` to ensure every execution is reproducible and audit-trailed.
3. **Hybrid Flow:** Use ZenML's Airflow orchestrator implementation if we ever need to embed ML pipelines inside a broader enterprise data workflow.

## IT Manager Summary
For Dealinka, **ZenML** provides an "MLOps-in-a-box" experience that minimizes the need for dedicated platform engineers. By leveraging serverless Vertex AI orchestration, we achieve enterprise-grade scale with a pay-per-use cost model, avoiding the overhead of managing dedicated Airflow clusters.

