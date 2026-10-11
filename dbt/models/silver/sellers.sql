-- Silver: sellers
-- Seller city is free text in the source. Some values contain the state
-- ("sao paulo / sp"), abbreviations ("sbc") or junk (an e-mail, a zip code).

with source as (
    select * from {{ source('bronze', 'sellers') }}
),

city_parts as (
    select
        *,
        -- keep the part before a "/" or "\" separator: "maua/sao paulo" -> "maua"
        lower(trim(split_part(replace(seller_city, '\', '/'), '/', 1))) as city_raw
    from source
)

select
    trim(seller_id)                                     as seller_id,
    lpad(trim(seller_zip_code_prefix), 5, '0')          as zip_code_prefix,
    case
        when city_raw ~ '[0-9@]'          then null                       -- e-mail or number, not a city
        when city_raw = 'sp'              then 'sao paulo'
        when city_raw = 'sbc'             then 'sao bernardo do campo'
        else nullif(city_raw, '')
    end                                                 as city,
    upper(trim(seller_state))                           as state,
    _loaded_at
from city_parts
