{{ config(tags=["every_3_hours"]) }}

SELECT
    c.company_id AS company_key,
    c.name AS company_name,
    c.status,
    c.created_at,
    c.industry,
    c.employee_count,
    c.credit_limit,
    c.billing_cycle,
    CASE
        WHEN c.status = 'active' AND c.credit_limit > 0 THEN true
        ELSE false
    END AS is_active_credit
FROM {{ source('app_db', 'companies') }} c
WHERE c._fivetran_deleted = false
