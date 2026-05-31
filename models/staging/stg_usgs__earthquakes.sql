with source as (

    select * from {{ source('usgs', 'raw_usgs_earthquakes') }}

),

deduped as (

    -- Daily "all_day" pulls overlap by design; keep the latest ingestion per quake.
    select *
    from source
    qualify row_number() over (partition by id order by ingested_at desc) = 1

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['id']) }} as earthquake_key,
        id,
        cast(event_time as timestamp)   as event_time,
        date(event_time)                as event_date,
        cast(magnitude as float64)      as magnitude,
        magnitude_type,
        place,
        event_type,
        cast(depth_km as float64)       as depth_km,
        cast(longitude as float64)      as longitude,
        cast(latitude as float64)       as latitude,
        ingested_at
    from deduped

)

select * from final
