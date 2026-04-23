WITH source AS (
    SELECT * FROM {{ source('erp', 'stock_declarations') }}
),
renamed AS (
    SELECT
        declaration_id,
        company_id,
        category,
        CAST(quantity_kg AS DOUBLE) AS quantity_kg,
        condition,
        description,
        declared_at,
        CAST(expiry_days AS INTEGER) AS expiry_days
    FROM source
)
SELECT * FROM renamed
