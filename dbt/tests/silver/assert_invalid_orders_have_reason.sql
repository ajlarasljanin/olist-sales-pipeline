-- Every invalid order must say why, and a valid order must not have a reason.

select order_id, is_valid, invalid_reason
from {{ ref('orders') }}
where (not is_valid and invalid_reason is null)
   or (is_valid and invalid_reason is not null)
