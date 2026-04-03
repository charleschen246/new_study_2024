{{
  config(
    materialized = 'table',
    description  = 'Geography dimension — one row per unique city/state/country combination'
  )
}}

with orders as (

    select distinct
        country,
        city,
        state,
        postal_code,
        region
    from {{ ref('stg_super_store_analysis__orders') }}

),

final as (

    select
        TO_HEX(MD5(CONCAT(
            COALESCE(country, ''),
            '|',
            COALESCE(city, ''),
            '|',
            COALESCE(state, ''),
            '|',
            COALESCE(CAST(postal_code AS STRING), '')
        )))          as geography_key,
        country,
        city,
        state,
        CAST(postal_code AS STRING) as postal_code,
        region
    from orders

)

select * from final
