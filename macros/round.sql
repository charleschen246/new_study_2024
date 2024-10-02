{% macro rounding(number, places)%}
    ROUND({{number}}, {{places}})

{% endmacro%}



{% macro generate_profit_model(table_name)%}
    Select * from {{ source('super_store_analysis',table_name) }}where sales >= 10
{% endmacro%}



{% macro generate_profit_model_1(table_name)%}
    Select * from {{ref(table_name) }} where quanity >= 10
{% endmacro%}
