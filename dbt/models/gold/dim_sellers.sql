-- Gold: dim_sellers
-- One row per seller, with coordinates for map visuals.

with first_sale as (
    select i.seller_id, min(o.purchased_at)::date as first_sale_date
    from {{ ref('order_items') }} i
    join {{ ref('orders') }} o on o.order_id = i.order_id
    where i.is_valid
    group by i.seller_id
)

select
    s.seller_id,
    s.zip_code_prefix,
    coalesce(s.city, 'unknown')         as city,
    s.state,
    g.latitude,
    g.longitude,
    f.first_sale_date
from {{ ref('sellers') }} s
left join first_sale f on f.seller_id = s.seller_id
left join {{ ref('geolocation') }} g on g.zip_code_prefix = s.zip_code_prefix
