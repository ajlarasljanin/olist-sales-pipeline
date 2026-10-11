-- Gold: dim_customers
-- One row per real customer (customer_unique_id). Olist gives a customer a new
-- customer_id for every order; this dimension groups them back into one person.
-- Location = the address of the customer's most recent valid order.

with valid_orders as (
    select o.order_id, o.purchased_at, c.customer_unique_id, c.zip_code_prefix, c.city, c.state
    from {{ ref('orders') }} o
    join {{ ref('customers') }} c on c.customer_id = o.customer_id
    where o.is_valid
),

ranked as (
    select
        *,
        row_number() over (partition by customer_unique_id order by purchased_at desc) as recency_rank
    from valid_orders
),

order_stats as (
    select
        customer_unique_id,
        min(purchased_at)::date     as first_order_date,
        max(purchased_at)::date     as last_order_date,
        count(*)                    as order_count
    from valid_orders
    group by customer_unique_id
)

select
    r.customer_unique_id                as customer_key,
    r.zip_code_prefix,
    r.city,
    r.state,
    g.latitude,
    g.longitude,
    s.first_order_date,
    s.last_order_date,
    s.order_count,
    s.order_count > 1                   as is_repeat_customer
from ranked r
join order_stats s using (customer_unique_id)
left join {{ ref('geolocation') }} g on g.zip_code_prefix = r.zip_code_prefix
where r.recency_rank = 1
