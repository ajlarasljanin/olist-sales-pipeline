{#
    Keep every model inside the medallion layers.

    * A model must get its schema from its folder (silver/ or gold/ in dbt_project.yml).
    * The schema is used as-is (silver, gold), not dbt's default "<target>_<custom>".
    * A model without a layer, or with any other schema, fails the run instead of
      silently landing in a fourth schema.
    * Everything that is not a model (tests, seeds, snapshots) goes to the target
      schema `meta`. dbt gives tests the custom schema "dbt_test__audit"; it is
      ignored on purpose so stored test failures would also land in `meta`.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set allowed_layers = ["silver", "gold"] -%}

    {%- if node.resource_type != "model" -%}
        {{ target.schema }}

    {%- elif custom_schema_name is none -%}
        {{ exceptions.raise_compiler_error(
            "Model '" ~ node.name ~ "' has no layer. Put it in models/silver/ or models/gold/."
        ) }}

    {%- else -%}
        {%- set layer = custom_schema_name | trim | lower -%}
        {%- if layer not in allowed_layers -%}
            {{ exceptions.raise_compiler_error(
                "Model '" ~ node.name ~ "' uses schema '" ~ layer ~ "'. Allowed layers: " ~ allowed_layers | join(", ")
            ) }}
        {%- endif -%}
        {{ layer }}
    {%- endif -%}
{%- endmacro %}
