{{
  config(
    materialized = 'table',
    description  = 'Customer dimension — one row per unique customer'
  )
}}

with orders as (

    select distinct
        customer_id,
        customer_name,
        segment
    from {{ ref('stg_super_store_analysis__Orders') }}

),

final as (

    select
        TO_HEX(MD5(customer_id))  as customer_key,
        customer_id,
        customer_name,
        segment
    from orders

)

select * from final
