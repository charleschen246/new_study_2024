with

source as (

    select * from {{ source('super_store_analysis', 'returns') }}

),

renamed as (

    select
        `Returned`  as returned,
        `Order ID`  as order_id

    from source

)

select * from renamed
