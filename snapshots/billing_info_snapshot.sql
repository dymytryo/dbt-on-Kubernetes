{% snapshot billing_info_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='company_id',
        strategy='check',
        check_cols=['billing_cycle', 'payment_method', 'credit_limit', 'status'],
    )
}}

SELECT
    company_id,
    billing_cycle,
    payment_method,
    credit_limit,
    status,
    updated_at
FROM {{ source('app_db', 'billing_info') }}
WHERE _fivetran_deleted = false

{% endsnapshot %}
