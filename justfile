# Dealinka Data Platform — Justfile
# Run `just` to list all available commands.
# Docs: https://github.com/casey/just

set dotenv-load := true
set shell := ["zsh", "-cu"]

# ─── Variables (all overridable via .env or shell) ───────────────────────────
PROJECT      := env_var("GCP_PROJECT")
REGION       := env_var("GCP_REGION")
REGISTRY     := env_var("ARTIFACT_REGISTRY")
FEED_DATE    := `date +%Y-%m-%d`
DBT_TARGET   := env_var("DBT_TARGET")
ZENML_STACK  := env_var("ZENML_STACK")


# ─── Default: list all recipes ────────────────────────────────────────────────
[doc('List all available recipes')]
default:
    @just --list

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 0 — Setup
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Bootstrap the Python environment with uv')]
setup:
    uv init
    uv add dbt-bigquery great-expectations google-cloud-bigquery \
            zenml mlflow apache-airflow google-cloud-pubsub \
            google-cloud-aiplatform faker polars pyarrow

[doc('Provision GCP infrastructure with Terraform (dev workspace by default)')]
infra-init:
    cd terraform && terraform init
    cd terraform && terraform workspace new dev || true

[doc('Preview infrastructure changes')]
infra-plan:
    cd terraform && terraform plan -out=plan.tfplan

[doc('Apply infrastructure changes')]
infra-apply: infra-plan
    cd terraform && terraform apply plan.tfplan

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Fake Data
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Generate fake company, association, stock and donation data')]
generate-data:
    mkdir -p data/raw
    uv run scripts/generate_fake_data.py

[doc('Upload generated fake data to GCS (simulates ERP feed arrival)')]
upload-data: generate-data
    gsutil -m cp data/raw/*.json gs://dealinka-raw/feeds/{{FEED_DATE}}/
    @echo "✅ Fake data uploaded for {{FEED_DATE}}"

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Airflow
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Start Airflow locally for DAG development')]
airflow-dev:
    airflow standalone

[doc('Validate all DAG files for syntax errors')]
airflow-check:
    airflow dags list-import-errors

[doc('Trigger the daily data platform DAG manually')]
airflow-trigger date=FEED_DATE:
    airflow dags trigger daily_data_platform --exec-date {{date}}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3 — dbt
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Run dbt build (run + test) on the selected target')]
dbt-build target=DBT_TARGET:
    cd dealinka && dbt build --target {{target}}

[doc('Run only staging models')]
dbt-staging target=DBT_TARGET:
    cd dealinka && dbt build --select staging --target {{target}}

[doc('Run only Gold mart models')]
dbt-gold target=DBT_TARGET:
    cd dealinka && dbt build --select marts --target {{target}}

[doc('Generate and serve dbt documentation')]
dbt-docs target=DBT_TARGET:
    cd dealinka && dbt docs generate --target {{target}}
    cd dealinka && dbt docs serve

[doc('Run dbt tests only (no materializations)')]
dbt-test target=DBT_TARGET:
    cd dealinka && dbt test --target {{target}}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Great Expectations
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Validate the Gold feature mart against expectation suite')]
gx-validate:
    uv run scripts/validate_gold.py

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 5 — BigQuery ML
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Train the baseline BQML model and log metrics to MLflow')]
bqml-train:
    bq query --project_id={{PROJECT}} --use_legacy_sql=false < sql/train_matching_model.sql

[doc('Log BQML evaluation metrics to MLflow')]
bqml-log:
    uv run scripts/log_bqml_to_mlflow.py

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 6 — ZenML
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Register and configure ZenML stacks (dev + production)')]
zenml-setup:
    zenml init
    # Dev stack
    zenml artifact-store register local_store --flavor=local || true
    zenml orchestrator register local_orch --flavor=local || true
    zenml experiment-tracker register mlflow_local \
        --flavor=mlflow --tracking_uri=http://localhost:5000 || true
    zenml stack register dev -o local_orch -a local_store -e mlflow_local || true
    # Production stack
    zenml artifact-store register gcs_store \
        --flavor=gcp --path=gs://dealinka-zenml-artifacts || true
    zenml orchestrator register vertex_orch \
        --flavor=vertex --project={{PROJECT}} --location={{REGION}} || true
    zenml experiment-tracker register mlflow_prod \
        --flavor=mlflow --tracking_uri="${MLFLOW_TRACKING_URI}" || true
    zenml stack register production -o vertex_orch -a gcs_store -e mlflow_prod || true
    @echo "✅ ZenML stacks registered"

[doc('Run the matching pipeline on the given stack (default: dev)')]
zenml-run stack=ZENML_STACK:
    zenml stack set {{stack}}
    uv run pipelines/matching_pipeline.py
    @echo "✅ Pipeline complete on stack: {{stack}}"

[doc('Run locally in dev stack')]
zenml-dev: (zenml-run "dev")

[doc('Run on Vertex AI production stack')]
zenml-prod: (zenml-run "production")

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 7 — Docker / Robyn API
# ═══════════════════════════════════════════════════════════════════════════════

image-tag := `git rev-parse --short HEAD`

[doc('Build the Robyn serving Docker image')]
docker-build:
    docker build -t {{REGISTRY}}/robyn-matching:{{image-tag}} serving/
    @echo "✅ Image built: robyn-matching:{{image-tag}}"

[doc('Push the Robyn image to Artifact Registry')]
docker-push: docker-build
    docker push {{REGISTRY}}/robyn-matching:{{image-tag}}

[doc('Run the Robyn API locally for smoke testing')]
docker-run:
    docker run --rm -p 8080:8080 {{REGISTRY}}/robyn-matching:{{image-tag}}

[doc('Deploy the Robyn image to a Vertex AI Endpoint')]
deploy endpoint_id:
    gcloud ai endpoints deploy-model {{endpoint_id}} \
        --region={{REGION}} \
        --display-name=robyn-matching-{{image-tag}} \
        --container-image-uri={{REGISTRY}}/robyn-matching:{{image-tag}} \
        --machine-type=n1-standard-4

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 8 — Monitoring
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Enable Vertex AI Model Monitoring on a deployed endpoint')]
monitoring-setup:
    uv run scripts/setup_monitoring.py

# ═══════════════════════════════════════════════════════════════════════════════
# CI / Day-to-Day Aliases
# ═══════════════════════════════════════════════════════════════════════════════

alias g  := generate-data
alias up := upload-data
alias b  := dbt-build
alias v  := gx-validate

[doc('Full local pipeline: generate → upload → dbt → validate → zenml dev')]
run-all: upload-data dbt-build gx-validate zenml-dev
    @echo "🚀 Full local pipeline complete!"

[doc('Full CI pipeline (no docker): dbt test + GX validate')]
ci: dbt-test gx-validate
    @echo "✅ CI checks passed"

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE RUNNERS — test the platform incrementally, phase by phase
# Usage: just phase-0, just phase-1 ... just phase-8
# Each phase depends on the previous to enforce correct execution order.
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Phase 0 — Bootstrap: Python env + Terraform infra')]
phase-0: setup infra-apply
    @echo "✅ Phase 0 complete: environment and infrastructure ready"

[doc('Phase 1 — Fake Data: generate and upload to GCS')]
phase-1: phase-0 upload-data
    @echo "✅ Phase 1 complete: fake data in GCS"

[doc('Phase 2 — Airflow: validate DAG syntax and trigger')]
phase-2: phase-1 airflow-check airflow-trigger
    @echo "✅ Phase 2 complete: Airflow DAG validated and triggered"

[doc('Phase 3 — dbt: run all models and tests')]
phase-3: phase-2 dbt-build
    @echo "✅ Phase 3 complete: Silver and Gold layers built and tested"

[doc('Phase 4 — Great Expectations: validate Gold layer')]
phase-4: phase-3 gx-validate
    @echo "✅ Phase 4 complete: Gold layer expectations passed"

[doc('Phase 5 — BQML: train baseline model and log to MLflow')]
phase-5: phase-4 bqml-train bqml-log
    @echo "✅ Phase 5 complete: baseline model trained and tracked"

[doc('Phase 6 — ZenML: run full ML pipeline locally')]
phase-6: phase-5 zenml-setup zenml-dev
    @echo "✅ Phase 6 complete: ZenML pipeline executed"

[doc('Phase 7 — Docker: build, push and deploy Robyn API (requires endpoint_id)')]
phase-7 endpoint_id: phase-6 docker-push (deploy endpoint_id)
    @echo "✅ Phase 7 complete: Robyn API deployed to Vertex AI"

[doc('Phase 8 — Monitoring: enable Vertex AI model monitoring')]
phase-8 endpoint_id: (phase-7 endpoint_id) monitoring-setup
    @echo "✅ Phase 8 complete: monitoring enabled — platform fully operational 🚀"
