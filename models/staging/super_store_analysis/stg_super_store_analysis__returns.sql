with 

source as (

    select * from {{ source('super_store_analysis', 'returns') }}

),

renamed as (

    select
        returned,
        'order id' as order_id

    from source

)

select * from renamed
