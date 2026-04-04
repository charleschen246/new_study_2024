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
        `Row ID`        as row_id,
        `Order ID`      as order_id,
        `Order Date`    as order_date,
        `Ship Date`     as ship_date,
        `Ship Mode`     as ship_mode,
        `Customer ID`   as customer_id,
        `Customer Name` as customer_name,
        `Segment`       as segment,
        `Country`       as country,
        `City`          as city,
        `State`         as state,
        `Postal Code`   as postal_code,
        `Region`        as region,
        `Product ID`    as product_id,
        `Category`      as category,
        `Sub-Category`  as sub_category,
        `Product Name`  as product_name,
        ROUND(CAST(`Sales` AS FLOAT64), 2)    as sales,
        CAST(`Quantity` AS INT64)             as quantity,
        ROUND(CAST(`Discount` AS FLOAT64), 2) as discount,
        ROUND(CAST(`Profit` AS FLOAT64), 2)   as profit

    from source

)

select * from renamed
