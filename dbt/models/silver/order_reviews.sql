-- Silver: order_reviews
-- Grain: one row per (review_id, order_id).
-- 789 review_ids appear on several orders with identical content: the customer
-- left one review for several orders bought together. These are NOT removed,
-- otherwise those orders would lose their review. The bronze "duplicate
-- review_id" warning is expected and explained here.
-- is_valid is inherited from the order.

with source as (
    select * from {{ source('bronze', 'order_reviews') }}
),

orders as (
    select order_id, is_valid from {{ ref('orders') }}
),

typed as (
    select
        trim(review_id)                                         as review_id,
        trim(order_id)                                          as order_id,
        trim(review_score)::integer                             as review_score,
        nullif(trim(review_comment_title), '')                  as comment_title,
        nullif(trim(review_comment_message), '')                as comment_message,
        nullif(trim(review_creation_date), '')::timestamp       as created_at,
        nullif(trim(review_answer_timestamp), '')::timestamp    as answered_at,
        _loaded_at
    from source
),

-- safety net: exact (review_id, order_id) repeats are dropped, keeping the latest answer
deduplicated as (
    select
        *,
        row_number() over (
            partition by review_id, order_id
            order by answered_at desc nulls last
        ) as row_num
    from typed
)

select
    d.review_id || '-' || d.order_id                    as review_order_key,
    d.review_id,
    d.order_id,
    review_score,
    comment_title,
    comment_message,
    comment_message is not null                         as has_comment,
    created_at,
    answered_at,
    coalesce(o.is_valid, false)                         as is_valid,
    d._loaded_at
from deduplicated d
left join orders o on o.order_id = d.order_id
where d.row_num = 1
