WITH source AS (
    SELECT * FROM {{ source('erp', 'companies') }}
),
renamed AS (
    SELECT
        company_id,
        company_name,
        region,
        sector,
        created_at
    FROM source
)
SELECT * FROM renamed
