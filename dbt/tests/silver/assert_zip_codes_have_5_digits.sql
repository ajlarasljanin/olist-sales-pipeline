-- Brazilian zip-code prefixes are exactly 5 digits (leading zeros included).

select 'customers' as model, customer_id as row_key, zip_code_prefix
from {{ ref('customers') }} where zip_code_prefix !~ '^[0-9]{5}$'

union all

select 'sellers', seller_id, zip_code_prefix
from {{ ref('sellers') }} where zip_code_prefix !~ '^[0-9]{5}$'
