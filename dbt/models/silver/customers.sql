-- Silver: customers
-- One row per customer_id. Olist creates a new customer_id for every order,
-- customer_unique_id identifies the real person.

with source as (
    select * from {{ source('bronze', 'customers') }}
)

select
    trim(customer_id)                                   as customer_id,
    trim(customer_unique_id)                            as customer_unique_id,
    lpad(trim(customer_zip_code_prefix), 5, '0')        as zip_code_prefix,
    lower(trim(customer_city))                          as city,
    upper(trim(customer_state))                         as state,
    _loaded_at
from source
