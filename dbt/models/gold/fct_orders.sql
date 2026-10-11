-- Gold: fct_orders
-- Grain: one row per valid order. Main table of the dashboard.
--
-- Revenue definition (agreed): revenue = sum of item prices of orders that are
-- not canceled or unavailable (is_revenue_order). Freight and the amount actually
-- paid (incl. installment interest) are kept as separate columns.

with orders as (
    select o.*, c.customer_unique_id
    from {{ ref('orders') }} o
    join {{ ref('customers') }} c on c.customer_id = o.customer_id
    where o.is_valid
),

items as (
    select
        order_id,
        count(*)                        as item_count,
        count(distinct product_id)      as distinct_products,
        count(distinct seller_id)       as seller_count,
        sum(price)                      as items_amount,
        sum(freight_value)              as freight_amount
    from {{ ref('order_items') }}
    where is_valid
    group by order_id
),

payments as (
    select
        order_id,
        count(*)                        as payment_count,
        sum(payment_value)              as paid_amount,
        max(installments)               as max_installments,
        -- payment type that covered the largest part of the order
        (array_agg(payment_type order by payment_value desc, payment_sequence))[1] as main_payment_type
    from {{ ref('order_payments') }}
    where is_valid
    group by order_id
),

reviews as (
    -- an order can have more than one review; keep the most recent one
    select distinct on (order_id)
        order_id,
        review_score,
        has_comment
    from {{ ref('order_reviews') }}
    where is_valid
    order by order_id, created_at desc, answered_at desc nulls last
)

select
    o.order_id,
    o.customer_unique_id                                    as customer_key,

    -- dates (link to dim_date)
    o.purchased_at::date                                    as purchase_date,
    o.delivered_at::date                                    as delivered_date,
    o.estimated_delivery_date                               as estimated_date,
    o.purchased_at,

    -- status
    o.order_status,
    o.order_status = 'delivered'                            as is_delivered,
    o.order_status not in ('canceled', 'unavailable')       as is_revenue_order,

    -- money
    coalesce(i.items_amount, 0)                             as items_amount,
    coalesce(i.freight_amount, 0)                           as freight_amount,
    coalesce(i.items_amount, 0) + coalesce(i.freight_amount, 0) as order_total,
    coalesce(p.paid_amount, 0)                              as paid_amount,
    coalesce(p.payment_count, 0)                            as payment_count,
    p.max_installments,
    p.main_payment_type,

    -- basket
    coalesce(i.item_count, 0)                               as item_count,
    coalesce(i.distinct_products, 0)                        as distinct_products,
    coalesce(i.seller_count, 0)                             as seller_count,

    -- delivery (null until the order is delivered)
    o.delivered_at::date - o.purchased_at::date             as delivery_days,
    o.estimated_delivery_date - o.purchased_at::date        as estimated_days,
    o.delivered_at::date - o.estimated_delivery_date        as delay_days,
    case when o.delivered_at is not null
         then o.delivered_at::date > o.estimated_delivery_date
    end                                                     as is_late,

    -- satisfaction
    r.review_score,
    r.review_score is not null                              as has_review,
    coalesce(r.has_comment, false)                          as has_comment

from orders o
left join items    i on i.order_id = o.order_id
left join payments p on p.order_id = o.order_id
left join reviews  r on r.order_id = o.order_id
