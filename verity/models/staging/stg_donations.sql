WITH source AS (
    SELECT * FROM {{ source('erp', 'donations') }}
),
renamed AS (
    SELECT
        donation_id,
        declaration_id,
        association_id,
        outcome,
        matched_at,
        CAST(transport_cost_eur AS DOUBLE) AS transport_cost_eur,
        CAST(distance_km AS DOUBLE) AS distance_km
    FROM source
)
SELECT * FROM renamed
