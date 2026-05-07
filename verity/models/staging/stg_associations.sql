WITH source AS (
    SELECT * FROM {{ source('erp', 'associations') }}
),
renamed AS (
    SELECT
        association_id,
        association_name,
        region,
        type,
        CAST(capacity_kg AS FLOAT64) AS capacity_kg,
        accepted_categories,
        created_at
    FROM source
)
SELECT * FROM renamed
