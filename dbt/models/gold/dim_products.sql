-- Gold: dim_products
-- One row per product with a readable English category for reports:
-- "health_beauty" -> "Health Beauty", missing category -> "Unknown".

select
    p.product_id,
    coalesce(
        initcap(replace(t.category_name_english, '_', ' ')),
        'Unknown'
    )                                   as category,
    p.category_name                     as category_name_pt,
    p.name_length,
    p.description_length,
    p.photos_qty,
    p.weight_g,
    p.length_cm,
    p.height_cm,
    p.width_cm
from {{ ref('products') }} p
left join {{ ref('category_translation') }} t on t.category_name = p.category_name
