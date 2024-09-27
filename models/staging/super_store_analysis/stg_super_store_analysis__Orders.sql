{{
  config(
    tags = ["finance"]
  )
}}
with 

source as (

    select * from {{ source('super_store_analysis', 'Orders') }}

),

renamed as (

    select
         'Order ID' as Order_id
        ,'Order Date' as order_date
        , 'Ship Date' as ship_date
        , 'Ship Mode' as ship_mode
        , 'Customer ID' as customer_id
        , 'Segment' as segment
        , 'Country' as country
        , 'Product ID' as product_id
        , 'Discount' as discount
        , 'Profit' as profit
    from source

)

select * from renamed
