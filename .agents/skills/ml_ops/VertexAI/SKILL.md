---
name: Vertex AI
description: Comprehensive guide for custom training, model management, deployment, and monitoring on Vertex AI.
---

# Vertex AI Best Practices Guide

Vertex AI is Google Cloud's unified machine learning platform. It integrates various services into a single environment for building, deploying, and scaling ML models.

## 1. Data Modality: Unstructured Data (Images & Videos)

Vertex AI is the primary platform for models dealing with unstructured data.

> [!IMPORTANT]
> **Use Vertex AI for Computer Vision & NLP.**
> For tasks such as Image Classification, Object Detection, Video Tracking, or complex Natural Language Processing, do not use BigQuery ML. Go directly through the **Vertex AI AutoML** interface for rapid prototyping or **Custom Training** for proprietary architectures.

## 2. Dataset & Feature Management

Efficient data management is the foundation of robust MLOps.

### Managed Datasets
- **Version Control:** Use Managed Datasets to keep track of the data versions used for each training run.
- **Data Labeling:** Leverage Vertex AI Data Labeling services for high-quality ground truth generation.

### Vertex AI Feature Store
- **Centralized Features:** Share features across teams to avoid redundant computation and ensure consistency.
- **Point-in-Time Lookups:** Use Feature Store to prevent data leakage by retrieving feature values at a specific timestamp.

## 3. Model Training

Choose the right training strategy based on your expertise and requirements.

### AutoML vs. Custom Training
- **AutoML:** Use for standard tabular, image, text, or video tasks where time-to-market and baseline performance are priorities.
- **Custom Training:** Use for proprietary architectures, specific framework requirements (PyTorch, TensorFlow, JAX), or complex preprocessing.
- **Prebuilt Containers:** Use Google-provided prebuilt containers for training to simplify environment management.

### Hyperparameter Tuning
- **Vertex AI Vizier:** Use for automated black-box optimization to find the best hyperparameters for your custom models.

## 4. Vertex AI Model Registry

The Model Registry is a central repository to manage the lifecycle of your ML models.

### Best Practices:
- **Versioning:** Always create a new version when updating a model instead of overwriting.
- **Aliases:** Use aliases like `default` or `production` to decouple deployment logic from specific version numbers.
- **Metadata:** Log model signatures and metadata (metrics, training parameters) to the Registry.

## 5. Model Serving & Deployment

Vertex AI provides flexible options for both real-time and offline inference.

### Online Prediction
- **Endpoints:** Deploy models to Endpoints for low-latency, real-time requests.
- **Auto-scaling:** Configure scaling policies (minimum and maximum nodes) based on request volume and latency requirements.
- **Traffic Splitting:** Use traffic splitting for A/B testing or canary rollouts between model versions.

### Batch Prediction
- **Large-scale Inference:** Use Batch Prediction jobs for high-throughput, offline processing where real-time response is not required.

## 6. Model Monitoring

Maintain model performance in production by detecting degradation early.

### Best Practices:
- **Training-Serving Skew:** Monitor if the distribution of incoming requests differs significantly from the training data.
- **Prediction Drift:** Track if the model's predictions shift over time (e.g., due to changing user behavior).
- **Alerting:** Set up Cloud Monitoring alerts to notify the team when drift or skew exceeds predefined thresholds.

## 7. Vertex AI Pipelines

Orchestrate your ML workflows with Vertex AI Pipelines (Serverless).

### Best Practices:
- **Componentization:** Build reusable components for data ingestion, preprocessing, training, and evaluation.
- **Reproducibility:** Use Kubeflow Pipelines (KFP) or TFX SDKs to define pipelines that are fully repeatable and versioned.
- **Integration:** Trigger pipelines automatically via Cloud Scheduler or Eventarc (e.g., when new data arrives in GCS).

## 8. Ecosystem Integration

Vertex AI is the core compute and registry hub of the ecosystem.

- **BigQuery ML:** Act as the deployment destination for BQML models, providing scaling, monitoring, and online inference.
- **MLflow:** Integrate by using Vertex AI as the runtime for MLflow Projects or as a deployment target for MLflow-managed models.
- **ZenML:** Use ZenML as the high-level orchestrator to manage state and reproducibility across **Vertex AI Pipelines**, registry, and monitoring.
