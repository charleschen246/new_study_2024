{{
  config(
    materialized = 'table',
    description  = 'Product dimension — one row per unique product'
  )
}}

with orders as (

    select distinct
        product_id,
        product_name,
        category,
        sub_category
    from {{ ref('stg_super_store_analysis__orders') }}

),

final as (

    select
        TO_HEX(MD5(product_id))  as product_key,
        product_id,
        product_name,
        category,
        sub_category
    from orders

)

select * from final
