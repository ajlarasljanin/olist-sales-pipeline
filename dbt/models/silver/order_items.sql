-- Silver: order_items
-- One row per item in an order. is_valid is inherited from the order.

with source as (
    select * from {{ source('bronze', 'order_items') }}
),

orders as (
    select order_id, is_valid from {{ ref('orders') }}
)

select
    trim(s.order_id) || '-' || trim(s.order_item_id)    as order_item_key,
    trim(s.order_id)                                    as order_id,
    trim(order_item_id)::integer                        as item_number,
    trim(product_id)                                    as product_id,
    trim(seller_id)                                     as seller_id,
    nullif(trim(shipping_limit_date), '')::timestamp    as shipping_limit_at,
    trim(price)::numeric(12, 2)                         as price,
    trim(freight_value)::numeric(12, 2)                 as freight_value,
    coalesce(o.is_valid, false)                         as is_valid,
    s._loaded_at
from source s
left join orders o on o.order_id = trim(s.order_id)
