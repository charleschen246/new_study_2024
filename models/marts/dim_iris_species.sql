{{
  config(
    materialized = 'table',
    description  = 'Iris species dimension — one row per species with average measurements'
  )
}}

with measurements as (

    select * from {{ ref('stg_iris__measurements') }}

),

species_stats as (

    select
        species,
        COUNT(*)                        as observation_count,
        ROUND(AVG(sepal_length_cm), 2)  as avg_sepal_length_cm,
        ROUND(AVG(sepal_width_cm), 2)   as avg_sepal_width_cm,
        ROUND(AVG(petal_length_cm), 2)  as avg_petal_length_cm,
        ROUND(AVG(petal_width_cm), 2)   as avg_petal_width_cm
    from measurements
    group by species

),

final as (

    select
        TO_HEX(MD5(species)) as species_key,
        species,
        observation_count,
        avg_sepal_length_cm,
        avg_sepal_width_cm,
        avg_petal_length_cm,
        avg_petal_width_cm
    from species_stats

)

select * from final