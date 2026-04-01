{{ config(tags=["every_morning"]) }}

SELECT
    DATE_TRUNC('month', s.cleared_at) AS report_month,
    c.industry,
    COUNT(DISTINCT s.company_id) AS active_companies,
    COUNT(*) AS transaction_count,
    SUM(s.amount) AS total_spend,
    AVG(s.amount) AS avg_transaction_amount
FROM {{ ref('spend_activity') }} s
JOIN {{ ref('company') }} c ON s.company_id = c.company_key
WHERE s.status = 'Cleared'
GROUP BY 1, 2
