---
name: Robyn
description: Guide for high-performance ML model serving and low-latency APIs with Robyn.
---

# Robyn High-Performance API Guide

Robyn is a high-performance Python web framework featuring a Rust runtime. It is designed for the "AI era," providing extreme throughput and low latency for machine learning model serving.

## 1. High-Performance Model Serving

Robyn's Rust runtime and async-first architecture make it ideal for serving compute-intensive ML models.

### Best Practices:
- **Singleton Model Loading**: Load your ML models once during the application's startup.
- **Async Prediction**: Use `async def` for all inference routes. Robyn handles concurrent requests efficiently without blocking.
- **Multi-Core Scaling**: Launch Robyn with optimized process and worker counts: `python app.py --processes n --workers m`.

```python
from robyn import Robyn
import joblib

app = Robyn(__file__)

# Load model globally (once at startup)
model = joblib.load("model.pkl")

@app.post("/predict")
async def predict(request):
    data = request.json()
    prediction = model.predict([data["features"]])
    return {"prediction": prediction.tolist()}

app.start(port=8080)
```

## 2. Platform Optimizations

- **Const Routes**: Use Robyn's Const Routes for static data (e.g., model metadata, feature schemas). These are served directly from the Rust layer without touching the Python interpreter.
- **Direct Rust Integration**: For extremely performance-critical preprocessing or post-processing, embed Rust code directly into your Robyn application.

## 3. Comparison with FastAPI/Uvicorn

| Feature                    | Robyn                           | FastAPI + Uvicorn               |
| :---                       | :---                            | :---                            |
| **Runtime**                | Rust (High-Performance)         | Python                          |
| **Latency**                | Extremely Low                   | Low                             |
| **Throughput**             | High (Managed concurrent load)  | Moderate                        |
| **Developer Experience**   | Simple, Rust-backed             | Rich ecosystem (Pydantic, etc.) |

## 4. Ecosystem Integration

Robyn is designed to be the high-performance serving layer within a broader MLOps ecosystem.

- **Vertex AI Endpoints**: Robyn is the preferred API server for Vertex AI Endpoints. Its low-latency Rust runtime ensures that the serving layer never becomes a bottleneck for deep learning or complex inference tasks.
- **Google Cloud Pub/Sub**: Robyn's async-first nature makes it an excellent choice for consuming and processing real-time event streams from Pub/Sub.
- **BigQuery**: Use the BigQuery Python SDK within Robyn routes for real-time point-in-time feature retrieval during inference.
- **Great Expectations**: Implement data quality checks as Robyn middleware or pre-inference steps to prevent invalid data from reaching the model.
- **MLflow**: Log inference-time telemetry, request/response metadata, and system performance to an MLflow Tracking Server using standard hooks.

---
## Senior MLOps Architect Summary

For low-latency applications where every millisecond counts—such as real-time fraud detection or recommendation engines—**Robyn** is the preferred choice over FastAPI. It provides the speed of Rust with the flexibility of Python, ensuring that the serving layer never becomes the bottleneck of the ML lifecycle.
