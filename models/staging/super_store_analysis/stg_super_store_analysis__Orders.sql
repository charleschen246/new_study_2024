{{
  config(
    tags = ["finance"]
  )
}}
with 

source as (

    select * from {{ source("super_store_analysis", "Orders") }}

),

renamed as (

    select
         `Row ID` as Order_id 
        ,`Order Date` as order_date
        , `Ship Mode` as ship_date
        , `Ship Date` as ship_mode
        , `Customer ID` as customer_id
        , `Segment` as segment
        , `Country` as country
        , `Product ID` as product_id
        , `Discount` as discount
        , {{rounding('Profit', 2)}} as profit
        ,  quantity as quanity
    from source

)

select * from renamed
