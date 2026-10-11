-- Gold: dim_date
-- One row per calendar day, covering every purchase, delivery and estimated date.
-- Power BI: mark this table as the date table (Table tools > Mark as date table).

with bounds as (
    select
        date_trunc('year', min(purchased_at))::date                              as first_day,
        (date_trunc('year', max(estimated_delivery_date)) + interval '1 year - 1 day')::date as last_day
    from {{ ref('orders') }}
),

days as (
    select generate_series(first_day, last_day, interval '1 day')::date as date
    from bounds
)

select
    date,
    extract(year from date)::int                        as year,
    extract(quarter from date)::int                     as quarter,
    'Q' || extract(quarter from date)::int              as quarter_name,
    extract(month from date)::int                       as month,
    trim(to_char(date, 'Month'))                        as month_name,
    to_char(date, 'Mon')                                as month_short,
    to_char(date, 'YYYY-MM')                            as year_month,
    (extract(year from date) * 100 + extract(month from date))::int as year_month_sort,
    extract(week from date)::int                        as week_of_year,     -- ISO week
    extract(day from date)::int                         as day_of_month,
    extract(isodow from date)::int                      as day_of_week,      -- 1 = Monday
    trim(to_char(date, 'Day'))                          as day_name,
    extract(isodow from date) in (6, 7)                 as is_weekend
from days
