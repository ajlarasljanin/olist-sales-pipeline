-- Orders excluded from gold because of a data contradiction (see silver.orders).
-- Severity "warn": the build continues, but the number of invalid orders is
-- reported on every run, so a sudden increase in the source is noticed.
{{ config(severity = 'warn') }}

select order_id, order_status, invalid_reason
from {{ ref('orders') }}
where not is_valid
