{{ config(tags=["business_hours", "week_nights", "weekends"]) }}

SELECT
    t.transaction_id AS transaction_key,
    t.company_id,
    t.user_id,
    t.card_id,
    t.amount,
    t.currency,
    t.merchant_name,
    t.merchant_category_code,
    t.transaction_type,
    t.status,
    t.authorized_at,
    t.cleared_at,
    t.created_at
FROM {{ source('app_db', 'transactions') }} t
WHERE t._fivetran_deleted = false
  AND t.status != 'Declined'
