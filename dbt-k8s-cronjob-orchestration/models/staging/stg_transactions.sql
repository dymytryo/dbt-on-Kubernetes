{{ config(alias='transactions', tags=["data_lake"]) }}

{{ select_all('app_db', 'transactions') }}
