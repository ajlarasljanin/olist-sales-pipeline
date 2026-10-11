"""Extract the Olist CSV files and load them into PostgreSQL (bronze layer).

Design choices
--------------
* The bronze layer is a faithful copy of the source: every column is TEXT, nothing is
  cleaned or cast here. Typing and cleaning happen later in dbt, where they are
  versioned and tested.
* Each table is a full refresh inside one transaction: drop, create, COPY, check.
  If any check fails the transaction rolls back and the previous version of the
  table stays untouched.
* Every table load writes a row to `meta.load_audit` (also when it fails), so you
  can always see what was loaded, when, and with which data-quality warnings.

Usage
-----
    python -m pipeline.extract_load                 # load all tables
    python -m pipeline.extract_load --tables orders customers
"""

from __future__ import annotations

import argparse
import csv
import logging
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import psycopg2
from psycopg2 import sql

from pipeline.config import BRONZE_SCHEMA, LOG_DIR, META_SCHEMA, RAW_DATA_DIR, SOURCES, SourceTable, db_settings

log = logging.getLogger("extract_load")

# Olist review comments contain long multi-line text; raise the csv module's limit.
csv.field_size_limit(10_000_000)


class ValidationError(Exception):
    """Raised when a source file or a loaded table fails a blocking check."""


@dataclass
class LoadResult:
    table: str
    source_file: str
    status: str = "FAILED"          # SUCCESS | WARNING | FAILED
    rows_in_file: int | None = None
    rows_loaded: int | None = None
    duplicate_keys: int | None = None
    message: str = ""
    seconds: float = 0.0


# --------------------------------------------------------------------------- #
# File checks (before touching the database)
# --------------------------------------------------------------------------- #
def read_header(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        header = next(csv.reader(f), None)
    if not header:
        raise ValidationError(f"{path.name} is empty")
    return [h.strip() for h in header]


def count_records(path: Path) -> int:
    """Count data records with a real CSV parser (comments may span several lines)."""
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        return sum(1 for _ in reader)


def check_file(source: SourceTable, data_dir: Path) -> tuple[Path, int]:
    path = data_dir / source.file
    if not path.exists():
        raise ValidationError(f"File not found: {path}")

    header = read_header(path)
    missing = [c for c in source.columns if c not in header]
    extra = [c for c in header if c not in source.columns]
    if missing:
        raise ValidationError(f"{source.file} is missing columns: {missing}")
    if extra:
        raise ValidationError(f"{source.file} has unexpected columns: {extra}")
    if header != source.columns:
        raise ValidationError(f"{source.file} columns are in an unexpected order: {header}")

    rows = count_records(path)
    if rows == 0:
        raise ValidationError(f"{source.file} has a header but no data rows")
    return path, rows


# --------------------------------------------------------------------------- #
# Database helpers
# --------------------------------------------------------------------------- #
def ensure_schemas(conn) -> None:
    """Create the bronze (data) and meta (audit) schemas if they do not exist yet."""
    with conn.cursor() as cur:
        for schema in (BRONZE_SCHEMA, META_SCHEMA):
            cur.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(schema)))
        cur.execute(sql.SQL("""
            CREATE TABLE IF NOT EXISTS {}.load_audit (
                run_id          uuid        NOT NULL,
                table_name      text        NOT NULL,
                source_file     text        NOT NULL,
                status          text        NOT NULL,
                rows_in_file    bigint,
                rows_loaded     bigint,
                duplicate_keys  bigint,
                message         text,
                duration_sec    numeric(10, 2),
                loaded_at       timestamptz NOT NULL DEFAULT now()
            )
        """).format(sql.Identifier(META_SCHEMA)))
    conn.commit()


def write_audit(conn, run_id: str, r: LoadResult) -> None:
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("""
                INSERT INTO {}.load_audit
                    (run_id, table_name, source_file, status, rows_in_file,
                     rows_loaded, duplicate_keys, message, duration_sec)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """).format(sql.Identifier(META_SCHEMA)),
            (run_id, r.table, r.source_file, r.status, r.rows_in_file,
             r.rows_loaded, r.duplicate_keys, r.message[:1000], round(r.seconds, 2)),
        )
    conn.commit()


def load_table(conn, source: SourceTable, path: Path, rows_in_file: int, result: LoadResult) -> None:
    """Drop + create + COPY + check, all in one transaction."""
    table = sql.Identifier(BRONZE_SCHEMA, source.name)
    cols = [sql.Identifier(c) for c in source.columns]
    col_defs = sql.SQL(", ").join(sql.SQL("{} text").format(c) for c in cols)

    with conn.cursor() as cur:
        cur.execute(sql.SQL("DROP TABLE IF EXISTS {}").format(table))
        cur.execute(
            sql.SQL("""
                CREATE TABLE {table} (
                    {col_defs},
                    _source_file text        NOT NULL DEFAULT {file},
                    _loaded_at   timestamptz NOT NULL DEFAULT now()
                )
            """).format(table=table, col_defs=col_defs, file=sql.Literal(source.file))
        )

        copy_stmt = sql.SQL(
            "COPY {} ({}) FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
        ).format(table, sql.SQL(", ").join(cols))
        with path.open("rb") as f:
            cur.copy_expert(copy_stmt.as_string(conn), f)

        # --- Check 1: every record in the file reached the table ------------
        cur.execute(sql.SQL("SELECT count(*) FROM {}").format(table))
        rows_loaded = cur.fetchone()[0]
        result.rows_loaded = rows_loaded
        if rows_loaded != rows_in_file:
            raise ValidationError(
                f"Row count mismatch: {rows_in_file} records in file, {rows_loaded} loaded"
            )

        if not source.key:
            return

        key_cols = [sql.Identifier(c) for c in source.key]

        # --- Check 2: key columns are never empty (blocking) ----------------
        null_filter = sql.SQL(" OR ").join(
            sql.SQL("{} IS NULL OR {} = ''").format(c, c) for c in key_cols
        )
        cur.execute(sql.SQL("SELECT count(*) FROM {} WHERE {}").format(table, null_filter))
        null_keys = cur.fetchone()[0]
        if null_keys:
            raise ValidationError(f"{null_keys} rows have an empty key {source.key}")

        # --- Check 3: duplicate keys (warning only, handled in dbt) ---------
        cur.execute(
            sql.SQL("""
                SELECT coalesce(sum(n - 1), 0) FROM (
                    SELECT count(*) AS n FROM {} GROUP BY {} HAVING count(*) > 1
                ) d
            """).format(table, sql.SQL(", ").join(key_cols))
        )
        result.duplicate_keys = int(cur.fetchone()[0])


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run(table_names: list[str] | None = None, data_dir: Path = RAW_DATA_DIR) -> list[LoadResult]:
    sources = SOURCES
    if table_names:
        unknown = set(table_names) - {s.name for s in SOURCES}
        if unknown:
            raise SystemExit(f"Unknown table(s): {', '.join(sorted(unknown))}")
        sources = [s for s in SOURCES if s.name in table_names]

    run_id = str(uuid.uuid4())
    log.info("Run %s: loading %d table(s) from %s", run_id[:8], len(sources), data_dir)

    conn = psycopg2.connect(**db_settings(), application_name="olist-extract-load")
    conn.set_client_encoding("UTF8")
    results: list[LoadResult] = []
    try:
        ensure_schemas(conn)
        for source in sources:
            result = LoadResult(table=f"{BRONZE_SCHEMA}.{source.name}", source_file=source.file)
            started = time.perf_counter()
            try:
                path, rows_in_file = check_file(source, data_dir)
                result.rows_in_file = rows_in_file
                load_table(conn, source, path, rows_in_file, result)
                conn.commit()
                if result.duplicate_keys:
                    result.status = "WARNING"
                    result.message = f"{result.duplicate_keys} duplicate key rows on {source.key}"
                else:
                    result.status = "SUCCESS"
            except (ValidationError, psycopg2.Error, OSError, UnicodeDecodeError) as exc:
                conn.rollback()
                result.status = "FAILED"
                result.message = str(exc).strip()
            result.seconds = time.perf_counter() - started

            level = {"SUCCESS": logging.INFO, "WARNING": logging.WARNING}.get(result.status, logging.ERROR)
            log.log(level, "%-22s %-8s %9s rows  %5.1fs  %s", result.table, result.status,
                    f"{result.rows_loaded:,}" if result.rows_loaded is not None else "-",
                    result.seconds, result.message)
            write_audit(conn, run_id, result)
            results.append(result)
    finally:
        conn.close()

    failed = [r for r in results if r.status == "FAILED"]
    log.info("Run %s finished: %d loaded, %d with warnings, %d failed",
             run_id[:8], len(results) - len(failed),
             sum(r.status == "WARNING" for r in results), len(failed))
    return results


def setup_logging() -> None:
    LOG_DIR.mkdir(exist_ok=True)
    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s", "%Y-%m-%d %H:%M:%S")
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    for handler in (logging.StreamHandler(sys.stdout),
                    logging.FileHandler(LOG_DIR / "pipeline.log", encoding="utf-8")):
        handler.setFormatter(fmt)
        root.addHandler(handler)


def main() -> int:
    parser = argparse.ArgumentParser(description="Load Olist CSV files into PostgreSQL (bronze schema).")
    parser.add_argument("--tables", nargs="+", help="Only load these tables (e.g. orders customers)")
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR, help="Folder with the CSV files")
    args = parser.parse_args()

    setup_logging()
    try:
        results = run(args.tables, args.data_dir)
    except psycopg2.OperationalError as exc:
        log.error("Could not connect to PostgreSQL: %s", str(exc).strip())
        return 2
    except RuntimeError as exc:
        log.error("%s", exc)
        return 2
    return 1 if any(r.status == "FAILED" for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
