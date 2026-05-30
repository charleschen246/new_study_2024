{{
  config(
    materialized = 'table',
    description  = 'Regional profitability summary — one row per region with key financial metrics'
  )
}}

with orders as (

    select * from {{ ref('fct_orders') }}

),

geography as (

    select
        geography_key,
        region,
        state
    from {{ ref('dim_geography') }}

),

region_state_metrics as (

    select
        g.region,
        g.state,
        COUNT(*)                                    as total_orders,
        SUM(CASE WHEN o.is_returned THEN 1 ELSE 0 END) as returned_orders,
        ROUND(SUM(o.sales), 2)                      as total_sales,
        ROUND(SUM(o.profit), 2)                     as total_profit,
        ROUND(SUM(o.net_sales), 2)                  as total_net_sales,
        ROUND(SUM(o.discount * o.sales), 2)         as total_discount_amount,
        ROUND(AVG(o.profit_margin), 4)              as avg_profit_margin,
        ROUND(AVG(o.sales), 2)                      as avg_order_value
    from orders o
    inner join geography g on o.geography_key = g.geography_key
    group by g.region, g.state

),

best_state as (

    select
        region,
        state as most_profitable_state
    from region_state_metrics
    qualify ROW_NUMBER() OVER (PARTITION BY region ORDER BY total_profit DESC) = 1

),

worst_state as (

    select
        region,
        state as least_profitable_state
    from region_state_metrics
    qualify ROW_NUMBER() OVER (PARTITION BY region ORDER BY total_profit ASC) = 1

),

region_summary as (

    select
        r.region,
        SUM(r.total_orders)                           as total_orders,
        SUM(r.returned_orders)                        as returned_orders,
        ROUND(SAFE_DIVIDE(SUM(r.returned_orders), SUM(r.total_orders)), 4) as return_rate,
        ROUND(SUM(r.total_sales), 2)                  as total_sales,
        ROUND(SUM(r.total_profit), 2)                 as total_profit,
        ROUND(SUM(r.total_net_sales), 2)              as total_net_sales,
        ROUND(SUM(r.total_discount_amount), 2)        as total_discount_amount,
        ROUND(SAFE_DIVIDE(SUM(r.total_profit), SUM(r.total_sales)), 4) as overall_profit_margin,
        ROUND(SAFE_DIVIDE(SUM(r.total_sales), SUM(r.total_orders)), 2) as avg_order_value,
        COUNT(DISTINCT r.state)                       as state_count,
        b.most_profitable_state,
        w.least_profitable_state
    from region_state_metrics r
    inner join best_state b on r.region = b.region
    inner join worst_state w on r.region = w.region
    group by r.region, b.most_profitable_state, w.least_profitable_state

),

final as (

    select
        region,
        total_orders,
        returned_orders,
        return_rate,
        total_sales,
        total_profit,
        total_net_sales,
        total_discount_amount,
        overall_profit_margin,
        avg_order_value,
        state_count,
        most_profitable_state,
        least_profitable_state,
        RANK() OVER (ORDER BY total_profit DESC)    as profit_rank
    from region_summary

)

select * from final