-- Gold must contain exactly the valid data from silver: same number of orders,
-- same number of items and the same revenue. Returns a row for every check that fails.

with checks as (
    select
        'order count' as check_name,
        (select count(*) from {{ ref('orders') }} where is_valid)::numeric      as silver_value,
        (select count(*) from {{ ref('fct_orders') }})::numeric                  as gold_value

    union all
    select
        'item count',
        (select count(*) from {{ ref('order_items') }} where is_valid),
        (select count(*) from {{ ref('fct_order_items') }})

    union all
    select
        'item revenue',
        (select sum(price) from {{ ref('order_items') }} where is_valid),
        (select sum(price) from {{ ref('fct_order_items') }})

    union all
    select
        'order revenue vs item revenue',
        (select sum(price) from {{ ref('fct_order_items') }}),
        (select sum(items_amount) from {{ ref('fct_orders') }})
)

select * from checks
where silver_value is distinct from gold_value
