{{
    config(
        materialized='table',
        schema='marts'
    )
}}

with final as (

    select
        earthquake_key,
        id,
        event_time,
        event_date,
        magnitude,
        magnitude_type,
        place,
        event_type,
        depth_km,
        longitude,
        latitude
    from {{ ref('stg_usgs__earthquakes') }}

)

select * from final
