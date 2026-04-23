/*
config:
  name: mart_feature_matching
  owner: data_team
  materialized: table
  governance:
    public: false
    pii: false
*/

-- mart_feature_matching.sql
-- Gold-layer feature table for the matching ML model.
-- ZenML and BQML steps MUST read from this mart only.

WITH enriched AS (
    SELECT * FROM {{ ref('int_donations_enriched') }}
),

features AS (
    SELECT
        donation_id,

        -- Categorical features
        category,
        condition,
        company_region,
        association_region,
        association_type,
        company_sector,

        -- Numerical features
        quantity_kg,
        expiry_days,
        association_capacity_kg,
        transport_cost_eur,
        distance_km,

        -- Label (derived from outcome)
        CASE
            WHEN outcome = 'accepted' THEN 1
            WHEN outcome = 'rejected' THEN 0
            ELSE NULL
        END AS was_matched_label,

        -- Metadata (not features, but useful for debugging)
        declared_at,
        matched_at

    FROM enriched
    WHERE outcome IS NOT NULL
)

SELECT * FROM features
