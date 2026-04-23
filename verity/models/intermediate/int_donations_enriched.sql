-- int_donations_enriched.sql
-- Joins donations with declarations, companies, and associations
-- to produce a denormalized intermediate table for feature engineering.

WITH donations AS (
    SELECT * FROM {{ ref('stg_donations') }}
),

declarations AS (
    SELECT * FROM {{ ref('stg_stock_declarations') }}
),

companies AS (
    SELECT * FROM {{ ref('stg_companies') }}
),

associations AS (
    SELECT * FROM {{ ref('stg_associations') }}
),

enriched AS (
    SELECT
        don.donation_id,
        don.declaration_id,
        don.association_id,
        don.outcome,
        don.matched_at,
        don.transport_cost_eur,
        don.distance_km,

        -- Declaration attributes
        decl.company_id,
        decl.category,
        decl.quantity_kg,
        decl.condition,
        decl.description AS product_description,
        decl.declared_at,
        decl.expiry_days,

        -- Company attributes
        comp.company_name,
        comp.region AS company_region,
        comp.sector AS company_sector,

        -- Association attributes
        assoc.association_name,
        assoc.region AS association_region,
        assoc.type AS association_type,
        assoc.capacity_kg AS association_capacity_kg,
        assoc.accepted_categories

    FROM donations don
    LEFT JOIN declarations decl
        ON don.declaration_id = decl.declaration_id
    LEFT JOIN companies comp
        ON decl.company_id = comp.company_id
    LEFT JOIN associations assoc
        ON don.association_id = assoc.association_id
)

SELECT * FROM enriched
