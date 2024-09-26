{{
  config(
    tags = ["finance"]
  )
}}
with 

source as (

    select * from {{ source('super_store_analysis', 'Orders') }}

),

renamed as (

    select
       *

    from source

)

select * from renamed
