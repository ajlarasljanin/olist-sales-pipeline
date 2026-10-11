-- No order flagged as invalid in silver may reach the gold layer.

select f.order_id, o.invalid_reason
from {{ ref('fct_orders') }} f
join {{ ref('orders') }} o on o.order_id = f.order_id
where not o.is_valid
