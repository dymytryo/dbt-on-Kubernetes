{% macro select_all(source_name, table_name) %}
    SELECT * FROM {{ source(source_name, table_name) }}
    WHERE _fivetran_deleted = false
{% endmacro %}
