# 📚 Dealinka Skills Index

This index provides a bird's-eye view of all codified skills available to the AI agents. Each link leads to a detailed Best Practices guide for that specific domain.

---

## 🛠️ Data Engineering

- **[Airflow](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/Airflow/SKILL.md)**: Orchestration, DAG design, and BigQuery operator standards.
- **[BigQuery ML](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/BigQuery_ML/SKILL.md)**: Native SQL modeling, AutoML, and feature engineering.
- **[dbt](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/dbt/SKILL.md)**: Transformation layers (Medallion), Semantic Layer, and MetricFlow.
- **[Great Expectations](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/GreatExpectations/SKILL.md)**: Data quality gates and automated validation.
- **[Pub/Sub](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/PubSub/SKILL.md)**: Real-time event ingestion and streaming patterns.
- **[Vertex AI Feature Store](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/data_engineering/VertexAI_FeatureStore/SKILL.md)**: Online/Offline feature serving and sync patterns.

---

## 🚀 Machine Learning Operations (MLOps)

- **[MLFlow](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/ml_ops/MLFlow/SKILL.md)**: Experiment tracking, model registry, and lifecycle management.
- **[Robyn](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/ml_ops/Robyn/SKILL.md)**: Marketing Mix Modeling (MMM) and budget optimization.
- **[Vertex AI](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/ml_ops/VertexAI/SKILL.md)**: Custom training, model serving, and monitoring.
- **[ZenML](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/ml_ops/ZenML/SKILL.md)**: Pipeline orchestration, stacking, and hardware operators.
- **[DevOps & Containerization](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/ml_ops/DevOps/SKILL.md)**: Serverless strategies, GCR/AR management, and CI/CD.

---

## 🏗️ Platform & Engineering

- **[Code Review](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/engineering/CodeReview/SKILL.md)**: Human-centric reviews, constructive feedback, and stack checks.
- **[Terraform](file:///Users/axelmauroy/Code/data-foundation/.agents/skills/platform/Terraform/SKILL.md)**: Infrastructure as Code (IaC), state management, and modular design.

---

### Core Principles
1. **Medallion Architecture**: Every data point must pass through Bronze → Silver → Gold layers with increasing quality.
2. **Schema-First**: No ingestion without a schema; no transformation without a contract.
3. **MLOps First**: Models are only as good as the pipelines that feed them.
4. **Idempotency**: All pipelines must be safe to rerun for any date without duplication.
