{{ config(alias='companies', tags=["data_lake"]) }}

{{ select_all('app_db', 'companies') }}
