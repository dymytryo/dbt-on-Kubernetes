{{ config(tags=["risk_daily"]) }}

SELECT
    pm.company_id,
    pm.evaluation_date,
    pm.risk_score,
    pm.spend_velocity_7d,
    pm.spend_velocity_30d,
    pm.balance_utilization,
    pm.days_past_due,
    pm.transaction_count_7d,
    CASE
        WHEN pm.risk_score >= 80 THEN 'high'
        WHEN pm.risk_score >= 50 THEN 'medium'
        ELSE 'low'
    END AS risk_tier
FROM {{ ref('stg_portfolio_metrics') }} pm
WHERE pm.evaluation_date = CURRENT_DATE
