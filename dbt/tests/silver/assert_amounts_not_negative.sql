-- Prices, freight and payments can never be negative.
-- A test passes when this query returns no rows.

select 'order_items.price' as field, order_item_key as row_key
from {{ ref('order_items') }} where price < 0 or freight_value < 0

union all

select 'order_payments.payment_value', payment_key
from {{ ref('order_payments') }} where payment_value < 0
