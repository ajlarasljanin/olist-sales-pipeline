-- Silver: products
-- Fixes the source typos (lenght -> length) and impossible values.
-- English category names are added in gold (dim_products).

with source as (
    select * from {{ source('bronze', 'products') }}
)

select
    trim(product_id)                                            as product_id,
    nullif(lower(trim(product_category_name)), '')              as category_name,
    nullif(trim(product_name_lenght), '')::numeric::integer     as name_length,
    nullif(trim(product_description_lenght), '')::numeric::integer as description_length,
    nullif(trim(product_photos_qty), '')::numeric::integer      as photos_qty,
    -- 4 products have weight 0 g, which is not a real weight
    nullif(nullif(trim(product_weight_g), '')::numeric, 0)      as weight_g,
    nullif(trim(product_length_cm), '')::numeric                as length_cm,
    nullif(trim(product_height_cm), '')::numeric                as height_cm,
    nullif(trim(product_width_cm), '')::numeric                 as width_cm,
    _loaded_at
from source
