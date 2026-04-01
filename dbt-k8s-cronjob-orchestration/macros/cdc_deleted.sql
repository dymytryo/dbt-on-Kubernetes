{% macro source_a_deleted() %}
    {# Hard-delete rows that CDC marked as soft-deleted #}
    {% set tables = [
        'transactions', 'companies', 'users', 'cards',
        'budgets', 'reimbursements', 'subscriptions'
    ] %}

    {% for table in tables %}
        DELETE FROM {{ source('app_db', table) }}
        WHERE _fivetran_deleted = true;
    {% endfor %}
{% endmacro %}
