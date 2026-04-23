# Dealinka Data Platform — Justfile
# Thin task runner. Not a CI/CD pipeline, not an orchestrator.
# Run `just` to list all available commands.

set dotenv-load := true
set shell := ["sh", "-cu"]

# ─── Project paths ────────────────────────────────────────────────────────────
GCP_CONFIG   := justfile_directory() + "/.gcp"
DBT_DIR      := "dealinka"
VERITY_DIR   := "verity"

# ─── Environment & Auth ──────────────────────────────────────────────────────
PROJECT      := env_var("GCP_PROJECT")
REGION       := env_var("GCP_REGION")
REGISTRY     := env_var_or_default("ARTIFACT_REGISTRY", REGION + "-docker.pkg.dev/" + PROJECT + "/data-platform")
DBT_TARGET   := env_var("DBT_TARGET")
ZENML_STACK  := env_var("ZENML_STACK")

# Service Account for data tasks
SA_EMAIL     := "data-platform-job-sa@" + PROJECT + ".iam.gserviceaccount.com"

# Impersonation control: Use IMPERSONATE=false to skip globally
IMPERSONATE  := env_var_or_default("IMPERSONATE", "true")

# Global exports
export GOOGLE_APPLICATION_CREDENTIALS := GCP_CONFIG + "/application_default_credentials.json"
export TF_VAR_project_id := PROJECT
export TF_VAR_region     := REGION

# Helper to inject impersonation into recipes
# Data recipes use {{AS_SA}} prefix. Infra recipes stay Admin.
AS_SA := if IMPERSONATE == "true" { "env GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=" + SA_EMAIL } else { "" }



# ─── Default ──────────────────────────────────────────────────────────────────
[doc('List all available recipes')]
default:
    @just --list

# ═══════════════════════════════════════════════════════════════════════════════
# Auth — project-local GCP config (.gcp/)
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Refresh isolated personal GCP credentials (ADC) for this project')]
auth-refresh:
    @echo "Refreshing Dealinka ADC in project-local config (.gcp/)..."
    @mkdir -p {{GCP_CONFIG}}
    env CLOUDSDK_CONFIG={{GCP_CONFIG}} GOOGLE_APPLICATION_CREDENTIALS="" \
        gcloud auth application-default login --no-launch-browser
    @echo "✅ Dealinka ADC refreshed. Your global ADC remains untouched."

[doc('Login to isolated personal GCP account for CLI tasks')]
auth-login:
    @echo "Logging in to project-local gcloud config (.gcp/)..."
    @mkdir -p {{GCP_CONFIG}}
    env CLOUDSDK_CONFIG={{GCP_CONFIG}} gcloud auth login --no-launch-browser
    @echo "✅ Dealinka CLI authenticated."

[doc('Set the quota project for the isolated Dealinka ADC')]
quota-set:
    env CLOUDSDK_CONFIG={{GCP_CONFIG}} gcloud auth application-default set-quota-project {{PROJECT}}

[doc('Set the active project in the isolated gcloud config')]
project-set:
    env CLOUDSDK_CONFIG={{GCP_CONFIG}} gcloud config set project {{PROJECT}}

[doc('Set or update a secret value in Secret Manager (interactive, hidden from shell history)')]
secret-set name:
    @echo -n "Enter value for secret {{name}}: "
    @read -s secret_value; \
    if [ -z "$secret_value" ]; then echo "\n❌ Error: Secret value cannot be empty."; exit 1; fi; \
    echo -n "$secret_value" | {{AS_SA}} \
        gcloud secrets versions add {{name}} --data-file=- && \
    echo "\n✅ Secret version added for {{name}}."

[doc('Enable all required GCP APIs for the data platform')]
apis-enable:
    @echo "Enabling required GCP APIs on {{PROJECT}}..."
    env CLOUDSDK_CONFIG={{GCP_CONFIG}} \
        gcloud services enable \
            bigquery.googleapis.com \
            artifactregistry.googleapis.com \
            run.googleapis.com \
            iam.googleapis.com \
            aiplatform.googleapis.com \
            cloudresourcemanager.googleapis.com \
            secretmanager.googleapis.com \
            cloudscheduler.googleapis.com \
            iamcredentials.googleapis.com \
            --project={{PROJECT}}
    @echo "✅ All required APIs enabled."

# ═══════════════════════════════════════════════════════════════════════════════
# Setup
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Sync the Python environment from lockfile')]
setup:
    uv sync

# ═══════════════════════════════════════════════════════════════════════════════
# Terraform — ⚠️ LOCAL DEV ONLY. Production infra changes go through CI.
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Initialize Terraform (no dependency chain)')]
tf-init:
    cd terraform && terraform init

[doc('Preview infrastructure changes')]
tf-plan:
    cd terraform && terraform plan -out=plan.tfplan

[doc('Apply infrastructure changes — review the plan first')]
tf-apply:
    cd terraform && terraform apply plan.tfplan

# ═══════════════════════════════════════════════════════════════════════════════
# Data — Generate & Upload
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Generate fake company, association, stock and donation data')]
generate-data:
    uv run src/generate_fake_data.py

[doc('Upload raw data to GCS (deterministic date, simulates ERP feed)')]
upload-data date=`date +%Y-%m-%d`:
    {{AS_SA}} gcloud storage cp src/data/raw/*.json gs://{{PROJECT}}-erp-feed/{{date}}/

# ═══════════════════════════════════════════════════════════════════════════════
# Cloud Run
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Build and push the orchestrator image with git SHA tag')]
cr-prepare:
    docker build -t {{REGISTRY}}/orchestrator:$(git rev-parse --short HEAD) .
    docker push {{REGISTRY}}/orchestrator:$(git rev-parse --short HEAD)
    @echo "✅ Image pushed: {{REGISTRY}}/orchestrator:$(git rev-parse --short HEAD)"
    @echo "🚀 Next step: Update 'container_image_tag' in variables.tf and run 'just tf-apply'"

[doc('Run a specific just command as a Cloud Run Job')]
cr-run command:
    gcloud run jobs execute data-platform-orchestrator \
        --region={{REGION}} \
        --args="{{command}}" \
        --wait

[doc('Trigger the dbt build job on Cloud Run')]
cr-dbt target=DBT_TARGET:
    @just cr-run "just dbt-build {{target}}"

[doc('Trigger the scheduled Verity job manually now')]
verity-trigger:
    gcloud scheduler jobs run verity-daily-check --location={{REGION}} --project={{PROJECT}}

# ═══════════════════════════════════════════════════════════════════════════════
# dbt
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Run dbt build (run + test) on the selected target')]
dbt-build target=DBT_TARGET:
    {{AS_SA}} cd {{DBT_DIR}} && dbt build --target {{target}}

[doc('Run only staging models')]
dbt-staging target=DBT_TARGET:
    {{AS_SA}} cd {{DBT_DIR}} && dbt build --select staging --target {{target}}

[doc('Run only Gold mart models')]
dbt-gold target=DBT_TARGET:
    {{AS_SA}} cd {{DBT_DIR}} && dbt build --select marts --target {{target}}

[doc('Generate and serve dbt documentation')]
dbt-docs target=DBT_TARGET:
    {{AS_SA}} cd {{DBT_DIR}} && dbt docs generate --target {{target}}
    {{AS_SA}} cd {{DBT_DIR}} && dbt docs serve

[doc('Run dbt tests only (no materializations)')]
dbt-test target=DBT_TARGET:
    {{AS_SA}} cd {{DBT_DIR}} && dbt test --target {{target}}

# ═══════════════════════════════════════════════════════════════════════════════
# Great Expectations
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Validate the Gold feature mart against expectation suite')]
gx-validate:
    {{AS_SA}} uv run scripts/validate_gold.py

# ═══════════════════════════════════════════════════════════════════════════════
# BigQuery ML
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Train the baseline BQML model and log metrics to MLflow')]
bqml-train:
    {{AS_SA}} bq query --project_id={{PROJECT}} --use_legacy_sql=false < sql/train_matching_model.sql

[doc('Log BQML evaluation metrics to MLflow')]
bqml-log:
    {{AS_SA}} uv run scripts/log_bqml_to_mlflow.py

# ═══════════════════════════════════════════════════════════════════════════════
# ZenML
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

[doc('Run the matching pipeline on the given stack')]
zenml-run stack=ZENML_STACK:
    zenml stack set {{stack}}
    uv run pipelines/matching_pipeline.py
    @echo "✅ Pipeline complete on stack: {{stack}}"

[doc('Run locally in dev stack')]
zenml-dev: (zenml-run "dev")

[doc('Run on Vertex AI production stack')]
zenml-prod: (zenml-run "production")

# ═══════════════════════════════════════════════════════════════════════════════
# Docker / Robyn API
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Build the Robyn serving Docker image')]
docker-build:
    docker build -t {{REGISTRY}}/robyn-matching:$(git rev-parse --short HEAD) serving/
    @echo "✅ Image built: robyn-matching:$(git rev-parse --short HEAD)"

[doc('Push the Robyn image to Artifact Registry')]
docker-push: docker-build
    docker push {{REGISTRY}}/robyn-matching:$(git rev-parse --short HEAD)

[doc('Run the Robyn API locally for smoke testing')]
docker-run:
    docker run --rm -p 8080:8080 {{REGISTRY}}/robyn-matching:$(git rev-parse --short HEAD)

[doc('Deploy the Robyn image to a Vertex AI Endpoint')]
deploy endpoint_id:
    gcloud ai endpoints deploy-model {{endpoint_id}} \
        --region={{REGION}} \
        --display-name=robyn-matching-$(git rev-parse --short HEAD) \
        --container-image-uri={{REGISTRY}}/robyn-matching:$(git rev-parse --short HEAD) \
        --machine-type=n1-standard-4

# ═══════════════════════════════════════════════════════════════════════════════
# Monitoring
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Enable Vertex AI Model Monitoring on a deployed endpoint')]
monitoring-setup:
    uv run scripts/setup_monitoring.py

# ═══════════════════════════════════════════════════════════════════════════════
# Verity — Governance-as-Code (experimental)
# ═══════════════════════════════════════════════════════════════════════════════

[doc('Convert NDJSON data to CSV for Verity DataFusion')]
verity-data:
    uv run {{VERITY_DIR}}/scripts/convert_ndjson_to_csv.py

[doc('Run Verity pipeline (DataFusion local)')]
verity-run: verity-data
    cd {{VERITY_DIR}} && verity run

[doc('Run Verity with strict governance mode')]
verity-strict: verity-data
    cd {{VERITY_DIR}} && VERITY_STRICT=true verity run

[doc('Generate Verity sources from data/ directory')]
verity-generate:
    cd {{VERITY_DIR}} && verity generate --owner "data_team" --pii

[doc('Check data lineage for PII leaks')]
verity-lineage:
    cd {{VERITY_DIR}} && verity lineage --check

[doc('Generate Verity data catalog')]
verity-docs:
    cd {{VERITY_DIR}} && verity docs

[doc('Run Verity pipeline against BigQuery (dev dataset)')]
verity-bq: verity-data
    cd {{VERITY_DIR}} && GOOGLE_CLOUD_PROJECT={{PROJECT}} VERITY_DATASET=verity_dev verity run --target bigquery_dev

[doc('Run Verity pipeline against BigQuery (prod dataset, strict mode)')]
verity-bq-prod: verity-data
    cd {{VERITY_DIR}} && GOOGLE_CLOUD_PROJECT={{PROJECT}} VERITY_DATASET=verity_prod VERITY_STRICT=true verity run --target bigquery_prod

# ═══════════════════════════════════════════════════════════════════════════════
# CI — stateless checks only
# ═══════════════════════════════════════════════════════════════════════════════

[doc('CI pipeline: dbt test + GX validate')]
ci: dbt-test gx-validate
    @echo "✅ CI checks passed"

# ═══════════════════════════════════════════════════════════════════════════════
# Aliases
# ═══════════════════════════════════════════════════════════════════════════════

alias g  := generate-data
alias up := upload-data
alias b  := dbt-build
alias v  := gx-validate
