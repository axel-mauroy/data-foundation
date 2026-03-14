---
name: BigQuery ML & AutoML
description: Comprehensive best practices guide for the complete model lifecycle within BigQuery ML and integration with Vertex AI.
---

# BigQuery ML (BQML) Best Practices Guide

BigQuery ML enables data scientists and analysts to build and operationalize machine learning models directly within BigQuery using SQL. This guide covers the complete lifecycle from data preparation to production monitoring.

## 1. Model Selection & Creation

Always choose the model type based on your data complexity and business requirements.

### Standard Models vs. AutoML
- **Standard Models (Linear, Logistic, K-means, etc.):** Best for interpretability, speed, and when the relationship is relatively linear or well-understood.
- **AutoML Tables:** Best for complex tabular datasets where you want the highest accuracy without manual feature engineering and hyperparameter tuning.

### SQL Syntax Pattern
Use `CREATE OR REPLACE MODEL` to ensure reproducibility and easy updates.

```sql
/* Example: Training a Boosted Tree Classifier */
CREATE OR REPLACE MODEL `your_project.your_dataset.customer_churn_model`
OPTIONS (
  MODEL_TYPE = 'BOOSTED_TREE_CLASSIFIER',
  INPUT_LABEL_COLS = ['churn_flag'],
  MAX_ITERATIONS = 50,
  LEARN_RATE = 0.1,
  DATA_SPLIT_METHOD = 'AUTO_SPLIT'
) AS
SELECT
  * EXCEPT(user_id)
FROM
  `your_project.your_dataset.training_data`;
```

## 2. Feature Engineering in SQL

Leverage the `TRANSFORM` clause to encapsulate preprocessing logic within the model object. This prevents "training-serving skew" by ensuring the same transformations are applied during prediction.

### Best Practices:
- **Scaling:** Use `ML.STANDARD_SCALER` or `ML.MAX_ABS_SCALER`.
- **Encoding:** Use `ML.ONE_HOT_ENCODER` or `ML.LABEL_ENCODER`.
- **Imputation:** Handle nulls explicitly in the `TRANSFORM` clause.

```sql
CREATE OR REPLACE MODEL `dataset.model`
TRANSFORM(
  ML.STANDARD_SCALER(income) OVER() as income_scaled,
  ML.ONE_HOT_ENCODER(category) OVER() as category_encoded,
  label
)
OPTIONS(...) AS SELECT * FROM training_table;
```

## 3. Model Evaluation

Never deploy a model without evaluating its performance on a holdout set.

- **Classification:** Use `ML.EVALUATE`, `ML.CONFUSION_MATRIX`, and `ML.ROC_CURVE`.
- **Regression:** Check R-squared, Mean Absolute Error (MAE), and Mean Squared Error (MSE).
- **Time Series:** Use `ML.EVALUATE` specifically designed for `ARIMA_PLUS`.

```sql
SELECT * FROM ML.EVALUATE(MODEL `dataset.model`, (
  SELECT * FROM `dataset.test_data`
));
```

## 4. Vertex AI & Operations

Operationalizing BQML models involves integrating with the broader Google Cloud AI ecosystem.

### Vertex AI Model Registry
Registering your BQML models in the Vertex AI Model Registry allows for better version control and simplified deployment to online endpoints.

```sql
/* Registering a model into Vertex AI Model Registry */
CREATE OR REPLACE MODEL `dataset.model`
OPTIONS(
  MODEL_TYPE = '...',
  MODEL_REGISTRY = 'VERTEX_AI',
  VERTEX_AI_MODEL_ID = 'my_custom_model_v1'
) AS SELECT ...
```

### Monitoring & Drift Detection
Use **Vertex AI Model Monitoring** to track your production models.
1. **Training-Serving Skew:** Detect if the feature distribution in production differs from what was seen during training.
2. **Prediction Drift:** Detect if the model's predictions are shifting over time, indicating potential concept drift.

## 5. Optimization & Cost Management

- **Dry Runs:** Always perform a dry run to estimate the bytes processed before training large models.
- **Data Locality:** Keep your training data in the same region as your BigQuery dataset to avoid egress costs and latency.
- **Batch Prediction:** For large-scale offline inference, use `ML.PREDICT` directly in SQL for maximum throughput.

## 6. Technical Comparison: AutoML vs. Custom

| Feature | AutoML Tables | Custom Training (BQML) |
| :--- | :--- | :--- |
| **Effort** | Low (Automated) | High (Manual Tuning) |
| **Accuracy** | Generally Higher | Dependent on Expertise |
| **Cost** | Higher (Vertex AI Training) | Lower (BigQuery Slot Usage) |
| **Training Time** | Hours (Minimum 1h) | Minutes to Hours |
| **Interpretability** | Moderate (Feature Importance) | High (Coefficients/Gains) |

## 7. Ecosystem Integration

BigQuery ML is the "Data First" entry point for MLOps on Google Cloud.

- **Vertex AI:** Seamlessly register models into the **Vertex AI Model Registry** using the `MODEL_REGISTRY` option. This enables deployment to **Vertex AI Endpoints** for online serving.
- **ZenML:** Use ZenML's BigQuery component to ingest data or trigger warehouse-native training as part of a larger orchestration workflow.
- **MLflow:** While BQML uses Google's registry, you can log high-level BQML evaluation metrics to a central **MLflow Tracking Server** via lightweight Python wrapper steps.
