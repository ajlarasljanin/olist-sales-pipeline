"""Pipeline configuration: database connection and the source tables to load."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_ROOT / ".env")

RAW_DATA_DIR = Path(os.getenv("RAW_DATA_DIR", PROJECT_ROOT / "data" / "raw"))
LOG_DIR = PROJECT_ROOT / "logs"
RAW_SCHEMA = "raw"


def db_settings() -> dict:
    """Connection settings read from environment variables (.env file)."""
    missing = [k for k in ("PGHOST", "PGDATABASE", "PGUSER", "PGPASSWORD") if not os.getenv(k)]
    if missing:
        raise RuntimeError(
            f"Missing database settings: {', '.join(missing)}. "
            "Copy .env.example to .env and fill in your PostgreSQL details."
        )
    return {
        "host": os.environ["PGHOST"],
        "port": int(os.getenv("PGPORT", "5432")),
        "dbname": os.environ["PGDATABASE"],
        "user": os.environ["PGUSER"],
        "password": os.environ["PGPASSWORD"],
    }


@dataclass(frozen=True)
class SourceTable:
    """One CSV file and the raw table it lands in."""

    name: str                 # target table: raw.<name>
    file: str                 # file name inside RAW_DATA_DIR
    columns: list[str]        # expected header, in order
    key: list[str] = field(default_factory=list)  # natural key, used for quality checks


SOURCES: list[SourceTable] = [
    SourceTable(
        "customers", "olist_customers_dataset.csv",
        ["customer_id", "customer_unique_id", "customer_zip_code_prefix",
         "customer_city", "customer_state"],
        key=["customer_id"],
    ),
    SourceTable(
        "orders", "olist_orders_dataset.csv",
        ["order_id", "customer_id", "order_status", "order_purchase_timestamp",
         "order_approved_at", "order_delivered_carrier_date",
         "order_delivered_customer_date", "order_estimated_delivery_date"],
        key=["order_id"],
    ),
    SourceTable(
        "order_items", "olist_order_items_dataset.csv",
        ["order_id", "order_item_id", "product_id", "seller_id",
         "shipping_limit_date", "price", "freight_value"],
        key=["order_id", "order_item_id"],
    ),
    SourceTable(
        "order_payments", "olist_order_payments_dataset.csv",
        ["order_id", "payment_sequential", "payment_type",
         "payment_installments", "payment_value"],
        key=["order_id", "payment_sequential"],
    ),
    SourceTable(
        "order_reviews", "olist_order_reviews_dataset.csv",
        ["review_id", "order_id", "review_score", "review_comment_title",
         "review_comment_message", "review_creation_date", "review_answer_timestamp"],
        key=["review_id"],  # known issue: some review_ids repeat across orders
    ),
    SourceTable(
        "products", "olist_products_dataset.csv",
        ["product_id", "product_category_name", "product_name_lenght",
         "product_description_lenght", "product_photos_qty", "product_weight_g",
         "product_length_cm", "product_height_cm", "product_width_cm"],
        key=["product_id"],
    ),
    SourceTable(
        "sellers", "olist_sellers_dataset.csv",
        ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"],
        key=["seller_id"],
    ),
    SourceTable(
        "category_translation", "product_category_name_translation.csv",
        ["product_category_name", "product_category_name_english"],
        key=["product_category_name"],
    ),
    SourceTable(
        "geolocation", "olist_geolocation_dataset.csv",
        ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng",
         "geolocation_city", "geolocation_state"],
        key=[],  # no natural key: the file has many points per zip prefix
    ),
]
