---
name: Google Cloud Pub/Sub
description: Best practices for asynchronous, event-driven architectures and real-time data streaming in MLOps.
---

# Pub/Sub Best Practices Guide

Google Cloud Pub/Sub is a messaging service for exchanging event data among applications and services. In MLOps, it powers real-time inference and asynchronous pipeline triggers.

## 1. Messaging Patterns

- **Pub/Sub (Publish/Subscribe):** Decouple data producers (e.g., user activity) from consumers (e.g., matching engine).
- **Fan-out:** Publish a single event to multiple topics for different downstream models (e.g., Recommendation vs. Fraud Detection).

## 2. Subscription Types

- **Push Subscriptions:** Use for serverless consumers (Cloud Functions, App Engine) to process events as they arrive.
- **Pull Subscriptions:** Use for high-throughput batch processing or GKE-based consumers where flow control is needed.

## 3. Reliability & Order

- **Dead Letter Queues (DLQ):** Always configure a DLQ to capture messages that fail processing after multiple retries.
- **Exactly-Once Delivery:** Leverage Pub/Sub's exactly-once delivery where strictly required (e.g., financial transactions).
- **Ordering Keys:** Use ordering keys to ensure events for a specific user are processed in chronological order.

## 4. MLOps Integration

- **Real-time Ingest:** Stream high-velocity features from Pub/Sub directly into BigQuery or Vertex AI Feature Store.
- **Asynchronous Matching:** Publish request IDs to Pub/Sub when a matching request is made; the model service consumes the request, runs inference, and publishes the result.
- **Pipeline Triggers:** Use Pub/Sub + Eventarc to trigger **Vertex AI Pipelines** the moment new data batch arrives in Cloud Storage.

## 5. Streaming Feature Engineering (Pub/Sub → Dataflow → BigQuery)

For the **real-time matching use case (UC1)**, streaming feature computation requires a full Dataflow pipeline between Pub/Sub and the Feature Store. Pub/Sub alone only transports events — Dataflow computes features at scale.

```
Company App
    │ declares stock
    ▼
Pub/Sub (stock_declared topic)
    │
    ▼
Cloud Dataflow (Apache Beam)
    │  • Enrich with company profile (BigQuery lookup)
    │  • Compute matching features (category embeddings, location distance)
    │  • Window aggregations (e.g., avg acceptance rate over last 30 days)
    ▼
Vertex AI Feature Store (online serving)
    │
    ▼
Robyn API → Matching Model (sub-50ms)
```

**Key Beam Patterns:**
- **Side Inputs:** Load company profile lookups from BigQuery as Beam side inputs to enrich streaming events.
- **Fixed Windows:** Compute rolling statistics (e.g., 7-day acceptance rate) using `beam.window.FixedWindows(7 * 24 * 3600)`.
- **Dead Letter Queue:** Unconsumed or malformed events from Pub/Sub go to a DLQ topic for replay without blocking the main pipeline.

## 6. Monitoring & Scalability

- **Message Age:** Monitor "Oldest Unacked Message" to detect consumer lag or model serving performance issues.
- **Throughput:** Scale consumer instances (e.g., K8s pods) based on the subscription backlog size.

---

**Senior MLOps Architect Summary:**
Pub/Sub is the nervous system of an event-driven MLOps architecture. It enables the highly responsive, real-time features required for modern applications while ensuring robustness through decoupled, asynchronous processing.
