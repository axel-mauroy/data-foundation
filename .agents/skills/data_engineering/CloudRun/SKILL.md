---
name: Cloud Run (Jobs & Services)
description: Best practices for serverless data orchestration and microservices on GCP using Cloud Run.
---

# Cloud Run (Jobs & Services) Best Practices Guide

Cloud Run is a managed compute platform that enables you to run containers that are invocable via requests or events. For data engineering and MLOps, it provides a cost-effective, serverless alternative to always-on clusters.

> [!IMPORTANT]
> **Use Cloud Run Jobs for batch processing (ETL, Training). Use Cloud Run Services for real-time inference (APIs).**
> Jobs run to completion. Services stay up to respond to web traffic (scaling to zero when idle).

## 1. Application Design & Packaging

Containerization is the foundation of Cloud Run. Efficiency starts with the image.

### 🐳 Containerization & Optimization
- **Lean Images**: Use lean base images (e.g., `alpine`, `distroless`, or `uv` variants) to minimize container size and security surface.
- **Statelessness**: Design applications to be 100% stateless. Externalize state to Cloud Storage, BigQuery, or Firestore to allow seamless horizontal scaling.
- **Source-based Deployment**: For simple apps, leverage Cloud Run's ability to build directly from source using buildpacks (`gcloud run deploy --source .`).
- **Graceful Shutdown**: Always handle `SIGTERM`. Cloud Run gives you a **10-second window** to flush logs, close DB connections, and persist intermediate data before instance termination.
- **Port Listening**: Services must listen on the port provided by the `PORT` environment variable (default: 8080).

### 📦 Packaging with `uv`
Efficiency is key to fast scaling and low costs. Use `uv` for lightning-fast builds and small image sizes.

- **Multi-stage (Conditional)**: Multi-stage is usually not needed for Python data apps unless you have complex C-extensions to compile, keeping the Dockerfile simpler.
- **`uv sync` Strategy**: Install dependencies into a virtualenv within the container using `uv sync --frozen --no-dev`.
- **Compact Layers**: Combine `apt-get install` and `rm -rf /var/lib/apt/lists/*` in a single layer to minimize image bloat.
- **Non-root User**: Always run your container as a non-privileged user (e.g., `USER nonroot`) to adhere to security best practices.

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["just"]
```

## 2. Cloud Run Jobs (Batch Orchestration)

Jobs are ideal for tasks that have a start and an end, like dbt runs, fake data generation, or ZenML pipeline steps.

### ⚡ Directives for Jobs
- **Execute via `just`**: Use a `justfile` inside your container to standardize entrypoints (e.g., `just dbt-run`, `just train`).
- **Idempotency**: Ensure that rerunning a failed job for the same execution date is safe.
- **Resource Sizing**: Match your `CPU` and `Memory` limits to the task. Use `--cpu=2 --memory=4Gi` for medium data tasks.
- **Timeouts**: Set a realistic `--timeout` (max 24h). The default is often too short for deep data processing.

```bash
# Example Job Execution
gcloud run jobs execute data-platform-orchestrator \
    --region=europe-west1 \
    --args="just dbt-build production" \
    --wait
```

## 3. Performance, Scaling & Services

Cloud Run Services require specific tuning for high-performance inference and web APIs.

### 🚀 Scaling & Concurrency
- **Concurrency**: Cloud Run can handle up to **1000 concurrent requests** per instance. Optimize your application (async/await in Python) to leverage this and reduce costs.
- **Cold Start Optimization**: Minimize dependencies and use **global variables** for caching data (like ML models) that can be reused across requests within the same instance.
- **Minimum Instances**: For latency-critical apps, set `--min-instances` to keep containers warm, but be mindful of the cost.
- **CPU Allocation**: Default is "CPU allocated during request". For background tasks, use **"CPU always allocated"** (instance-based billing).

### 🛠️ Execution Environments
- **First Gen**: Faster cold starts, lower memory (uses gVisor).
- **Second Gen**: Full Linux compatibility, better performance for CPU/Network, supports GCS FUSE (requires >= 512 MiB).

## 4. Deployment & Security

- **Traffic Management**: Use traffic splitting for safe rollouts (Canary, Blue/Green). Roll back instantly if metrics degrade.
- **Least Privilege**: Always deploy with a **dedicated Service Account**.
- **Secrets**: Use **Secret Manager** to mount sensitive data as environment variables or volumes. Never include `.env` files in images.
- **CI/CD**: Integrate with GitHub Actions or Cloud Build for reproducible deployments.

## 5. Advanced Architectures

- **Event-Driven**: Use **Eventarc** to trigger Cloud Run in response to GCS file uploads, Pub/Sub messages, or BigQuery audit logs.
- **AI/ML Workloads**:
    - **GPUs**: Utilize NVIDIA L4 GPUs for demanding inference.
    - **Model Loading**: Use **Cloud Storage FUSE** to mount buckets as local volumes for high-speed model access.
- **Worker Pools**: For continuous, pull-based background tasks (e.g., Kafka/Pub/Sub consumers).

---

**Data Reliability Summary (CTO):**
Cloud Run provides a "Scale-to-Zero" architecture that eliminates the waste of idle clusters. By packaging every data task as a containerized Job or Service, we ensure 100% environment parity between development and production while maintaining extreme cost efficiency.
