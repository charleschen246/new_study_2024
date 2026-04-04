{{
  config(
    materialized = 'table',
    description  = 'Iris fact table — one row per flower measurement with species FK'
  )
}}

with measurements as (

    select * from {{ ref('stg_iris__measurements') }}

),

final as (

    select
        measurement_id,
        TO_HEX(MD5(species))  as species_key,
        sepal_length_cm,
        sepal_width_cm,
        petal_length_cm,
        petal_width_cm,
        ROUND(sepal_length_cm * sepal_width_cm, 2) as sepal_area_cm2,
        ROUND(petal_length_cm * petal_width_cm, 2)  as petal_area_cm2
    from measurements

)

select * from final