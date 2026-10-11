-- An order cannot reach the customer before it was purchased or approved.

select order_id, purchased_at, approved_at, delivered_at
from {{ ref('orders') }}
where delivered_at < purchased_at
   or approved_at  < purchased_at
