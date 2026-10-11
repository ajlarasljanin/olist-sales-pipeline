-- Silver: order_payments
-- One row per payment. An order can be paid in several parts (vouchers + card).
-- is_valid is inherited from the order.

with source as (
    select * from {{ source('bronze', 'order_payments') }}
),

orders as (
    select order_id, is_valid from {{ ref('orders') }}
)

select
    trim(s.order_id) || '-' || trim(payment_sequential) as payment_key,
    trim(s.order_id)                                    as order_id,
    trim(payment_sequential)::integer                   as payment_sequence,
    lower(trim(payment_type))                           as payment_type,
    -- 2 rows have 0 installments; every payment is at least 1 installment
    greatest(trim(payment_installments)::integer, 1)    as installments,
    trim(payment_value)::numeric(12, 2)                 as payment_value,
    coalesce(o.is_valid, false)                         as is_valid,
    s._loaded_at
from source s
left join orders o on o.order_id = trim(s.order_id)
