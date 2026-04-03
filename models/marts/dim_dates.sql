{{
  config(
    materialized = 'table',
    description  = 'Date dimension — one row per unique date found in order or ship dates'
  )
}}

with order_dates as (

    select parse_date('%m/%d/%Y', order_date) as date_value from {{ ref('stg_super_store_analysis__Orders') }}
    union distinct
    select parse_date('%m/%d/%Y', ship_date)  as date_value from {{ ref('stg_super_store_analysis__Orders') }}

),

final as (

    select
        FORMAT_DATE('%Y%m%d', date_value)           as date_key,
        date_value                                  as full_date,
        EXTRACT(YEAR        FROM date_value)        as year,
        EXTRACT(QUARTER     FROM date_value)        as quarter,
        EXTRACT(MONTH       FROM date_value)        as month,
        FORMAT_DATE('%B',    date_value)            as month_name,
        FORMAT_DATE('%b',    date_value)            as month_short,
        EXTRACT(WEEK        FROM date_value)        as week_of_year,
        EXTRACT(DAY         FROM date_value)        as day_of_month,
        EXTRACT(DAYOFWEEK   FROM date_value)        as day_of_week,
        FORMAT_DATE('%A',    date_value)            as day_name,
        FORMAT_DATE('%a',    date_value)            as day_short,
        CASE
            WHEN EXTRACT(DAYOFWEEK FROM date_value) IN (1, 7) THEN TRUE
            ELSE FALSE
        END                                         as is_weekend,
        CONCAT(
            CAST(EXTRACT(YEAR FROM date_value) AS STRING),
            '-Q',
            CAST(EXTRACT(QUARTER FROM date_value) AS STRING)
        )                                           as year_quarter
    from order_dates
    where date_value is not null

)

select * from final
