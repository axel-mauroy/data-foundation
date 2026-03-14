---
name: DevOps & Containerization
description: Best practices for standardized packaging, serverless orchestration, and scalable infrastructure in MLOps.
---

# DevOps & Containerization Strategy Guide

Standardized environments and serverless orchestration are critical for minimizing technical debt and ensuring that machine learning models are reliable and scalable from local development to production.

## 1. Container-First Strategy (Docker)

All ML components—from preprocessing scripts to model serving APIs—must be packaged as Docker containers.

### Best Practices:
- **Base Images:** Use slim, official base images (e.g., `python:3.12-slim`) to reduce the attack surface and image size.
- **standardization:** Ensure the exact same container image used in training is used for evaluation to prevent environment-related bugs.
- **Multistage Builds:** Use multistage builds to separate build-time dependencies from the final production runtime.
- **Versioning:** Tag every image with a unique Git commit SHA or version number. Never use `latest` in production.

```dockerfile
# Example: High-Performance ML Serving with Robyn
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
EXPOSE 8080

# Launch with optimized processes and workers for the Rust runtime
CMD ["python", "src/main.py", "--processes", "4", "--workers", "2"]
```

## 2. Serverless-First Orchestration (Vertex AI)

Prioritize managed services over raw Kubernetes (GKE) clusters to reduce operational overhead while retaining industrial scale.

### Core Principles:
- **Vertex AI Pipelines:** Use for orchestrating multi-step ML workflows. It provides a serverless execution environment based on KFP (Kubeflow Pipelines).
- **Vertex AI Endpoints:** Deploy models to managed endpoints for auto-scaling real-time inference.
- **No Manual Clusters:** Avoid managing GKE nodes or namespaces manually unless custom networking or extreme low-latency requirements (gRPC/Sidecars) mandate it.

## 3. Resource & Infrastructure Management

Efficiency is key to cost-effective MLOps.

- **CPU/GPU Selection:** Match the hardware to the task. Use T4/L4 GPUs for inference and A100/H100s only for high-memory training.
- **Memory Limits:** Always define `memory_limit` and `cpu_limit` in your pipeline components to prevent resource starvation in shared environments.
- **Spot Instances:** Leverage preemptible (Spot) VMs for non-critical training jobs to reduce costs by up to 80%.

## 4. CI/CD for ML

- **Automated Re-training:** Trigger pipelines automatically when new data or updated code is pushed to the repository.
- **Integration Testing:** Run unit tests on preprocessing logic and integration tests on the containerized serving layer before deployment.
- **Canary Rollouts:** Use Vertex AI traffic splitting to roll out new models to a small percentage of users (e.g., 5%) before full deployment.

---
## Senior MLOps Architect Summary

| Component          | Standard Approach      | Strategic Goal       |
| :---               | :---                   | :---                 |
| **Packaging**      | Docker (Portable)      | Environment Parity   |
| **Orchestration**  | Vertex AI (Serverless) | Zero-Ops Scaling     |
| **Infrastructure** | Vertex AI Endpoints    | Managed Availability |
| **Optimization**   | Spot VMs / GPU Sizing  | Cost Efficiency      |

By adopting a **Container-first, Serverless-preferred** approach, we ensure that the infrastructure scales with the business without requiring a massive DevOps team to manage underlying clusters.
