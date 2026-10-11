-- Silver: geolocation
-- The source has ~1M points with many rows per zip-code prefix and some
-- coordinates outside Brazil. Output: one row per zip-code prefix with the
-- average coordinates of the points that fall inside Brazil.

with source as (
    select * from {{ source('bronze', 'geolocation') }}
),

typed as (
    select
        lpad(trim(geolocation_zip_code_prefix), 5, '0')   as zip_code_prefix,
        trim(geolocation_lat)::double precision           as latitude,
        trim(geolocation_lng)::double precision           as longitude,
        lower(trim(geolocation_city))                     as city,
        upper(trim(geolocation_state))                    as state
    from source
),

inside_brazil as (
    -- Brazil bounding box
    select * from typed
    where latitude  between -33.75 and 5.27
      and longitude between -73.99 and -34.79
)

select
    zip_code_prefix,
    round(avg(latitude)::numeric, 6)        as latitude,
    round(avg(longitude)::numeric, 6)       as longitude,
    mode() within group (order by city)     as city,
    mode() within group (order by state)    as state,
    count(*)                                as points
from inside_brazil
group by zip_code_prefix
