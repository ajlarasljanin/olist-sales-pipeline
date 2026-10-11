-- Silver: category_translation
-- Portuguese -> English category names. The source file misses 2 categories
-- that do appear in products; they are added here so no product is left untranslated.

with source as (
    select
        lower(trim(product_category_name))          as category_name,
        lower(trim(product_category_name_english))  as category_name_english
    from {{ source('bronze', 'category_translation') }}
),

missing_in_source (category_name, category_name_english) as (
    values
        ('pc_gamer', 'pc_gamer'),
        ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers')
)

select category_name, category_name_english, false as is_manual_translation from source
union all
select m.category_name, m.category_name_english, true
from missing_in_source m
where not exists (select 1 from source s where s.category_name = m.category_name)
