-- Gold: fct_order_items
-- Grain: one row per item of a valid order.
-- Use for product, category and seller analysis.

select
    i.order_item_key,
    i.order_id,
    i.item_number,
    i.product_id,
    i.seller_id,
    c.customer_unique_id                                as customer_key,
    o.purchased_at::date                                as purchase_date,
    o.order_status,
    o.order_status not in ('canceled', 'unavailable')   as is_revenue_order,
    i.price,
    i.freight_value
from {{ ref('order_items') }} i
join {{ ref('orders') }} o    on o.order_id = i.order_id
join {{ ref('customers') }} c on c.customer_id = o.customer_id
where i.is_valid
