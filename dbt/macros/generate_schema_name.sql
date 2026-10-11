{#
    Keep every model inside the medallion layers.

    * A model must get its schema from its folder (silver/ or gold/ in dbt_project.yml).
    * The schema is used as-is (silver, gold), not dbt's default "<target>_<custom>".
    * A model without a layer, or with any other schema, fails the run instead of
      silently landing in a fourth schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set allowed_layers = ["silver", "gold"] -%}

    {%- if custom_schema_name is not none -%}
        {%- set layer = custom_schema_name | trim | lower -%}
        {%- if layer not in allowed_layers -%}
            {{ exceptions.raise_compiler_error(
                "'" ~ node.name ~ "' uses schema '" ~ layer ~ "'. Allowed layers: " ~ allowed_layers | join(", ")
            ) }}
        {%- endif -%}
        {{ layer }}

    {%- elif node.resource_type == "model" -%}
        {{ exceptions.raise_compiler_error(
            "Model '" ~ node.name ~ "' has no layer. Put it in models/silver/ or models/gold/."
        ) }}

    {%- else -%}
        {#- tests and other non-model nodes never create tables here -#}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
