-- Silver: orders
-- The source is a snapshot: orders that are still "shipped", "invoiced", etc.
-- have no delivery date yet, which is normal and NOT flagged.
-- Only real contradictions are flagged. Rows are kept in silver for auditing;
-- is_valid = false rows are excluded from gold and Power BI.

with source as (
    select * from {{ source('bronze', 'orders') }}
),

typed as (
    select
        trim(order_id)                                          as order_id,
        trim(customer_id)                                       as customer_id,
        lower(trim(order_status))                               as order_status,
        nullif(trim(order_purchase_timestamp), '')::timestamp   as purchased_at,
        nullif(trim(order_approved_at), '')::timestamp          as approved_at,
        nullif(trim(order_delivered_carrier_date), '')::timestamp  as shipped_at,
        nullif(trim(order_delivered_customer_date), '')::timestamp as delivered_at,
        nullif(trim(order_estimated_delivery_date), '')::date   as estimated_delivery_date,
        _loaded_at
    from source
),

flagged as (
    select
        *,
        -- invalid: status is "delivered" but there is no delivery date (8 orders)
        (order_status = 'delivered' and delivered_at is null)       as dq_delivered_without_date,
        -- invalid: handed to the carrier before the purchase happened (166 orders)
        coalesce(shipped_at < purchased_at, false)                  as dq_shipped_before_purchase,
        -- informational only: delivered, then canceled (6 orders, e.g. a return)
        (order_status = 'canceled' and delivered_at is not null)    as dq_canceled_after_delivery
    from typed
)

select
    *,
    not (dq_delivered_without_date or dq_shipped_before_purchase)  as is_valid,
    case
        when dq_shipped_before_purchase then 'shipped_before_purchase'
        when dq_delivered_without_date  then 'delivered_without_date'
    end                                                             as invalid_reason
from flagged
