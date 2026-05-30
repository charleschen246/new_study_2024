{{
  config(
    materialized = 'table',
    description  = 'Order fact table — one row per order line item with FK references to all dimensions'
  )
}}

with orders as (

    select * from {{ ref('stg_super_store_analysis__orders') }}

),

returns as (

    select order_id from {{ ref('stg_super_store_analysis__returns') }}
    where returned = 'Yes'

),

customers as (

    select customer_key, customer_id
    from {{ ref('dim_customers') }}

),

products as (

    select product_key, product_id
    from {{ ref('dim_products') }}

),

geography as (

    select
        geography_key,
        country,
        city,
        state,
        postal_code,
        region
    from {{ ref('dim_geography') }}

),

order_dates as (

    select date_key, full_date
    from {{ ref('dim_dates') }}

),

ship_dates as (

    select date_key, full_date
    from {{ ref('dim_dates') }}

),

final as (

    select
        -- natural keys
        o.row_id                                as order_line_id,
        o.order_id,

        -- foreign keys
        c.customer_key,
        p.product_key,
        g.geography_key,
        od.date_key                             as order_date_key,
        sd.date_key                             as ship_date_key,
        od.full_date                            as order_date,
        sd.full_date                            as ship_date,

        -- degenerate dimensions
        o.ship_mode,

        -- measures
        o.sales,
        o.quantity,
        o.discount,
        o.profit,
        ROUND(o.sales * (1 - o.discount), 2)   as net_sales,
        ROUND(o.profit / NULLIF(o.sales, 0), 4) as profit_margin,

        -- flags
        CASE WHEN r.order_id IS NOT NULL THEN TRUE ELSE FALSE END as is_returned

    from orders             o
    left join customers     c  on o.customer_id  = c.customer_id
    left join products      p  on o.product_id   = p.product_id
    left join geography     g  on o.country       = g.country
                               and o.city         = g.city
                               and o.state        = g.state
                               and CAST(o.postal_code AS STRING) = g.postal_code
    left join order_dates   od on parse_date('%m/%d/%Y', o.order_date)    = od.full_date
    left join ship_dates    sd on parse_date('%m/%d/%Y', o.ship_date)     = sd.full_date
    left join returns       r  on o.order_id      = r.order_id

)

select * from final
