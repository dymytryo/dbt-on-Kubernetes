{% macro warehouse_resize(modifier) %}
    {% set increase %}
        ALTER WAREHOUSE prod_wh
            SET WAREHOUSE_SIZE = xsmall
                SCALING_POLICY = standard
                MIN_CLUSTER_COUNT = 1
                MAX_CLUSTER_COUNT = 4
                AUTO_SUSPEND = 300
                AUTO_RESUME = true;
    {% endset %}

    {% set decrease %}
        ALTER WAREHOUSE prod_wh
            SET WAREHOUSE_SIZE = xsmall
                SCALING_POLICY = economy
                MIN_CLUSTER_COUNT = 1
                MAX_CLUSTER_COUNT = 2
                AUTO_SUSPEND = 60
                AUTO_RESUME = true;
    {% endset %}

    {% if modifier == 'increase' %}
        {% do run_query(increase) %}
    {% elif modifier == 'decrease' %}
        {% do run_query(decrease) %}
    {% endif %}
{% endmacro %}
