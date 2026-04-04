with

source as (

    select * from {{ source("iris", "raw_iris") }}

),

renamed as (

    select
        ROW_NUMBER() OVER (ORDER BY sepal_length, sepal_width, petal_length, petal_width, species) as measurement_id,
        ROUND(sepal_length, 1) as sepal_length_cm,
        ROUND(sepal_width, 1)  as sepal_width_cm,
        ROUND(petal_length, 1) as petal_length_cm,
        ROUND(petal_width, 1)  as petal_width_cm,
        species
    from source

)

select * from renamed