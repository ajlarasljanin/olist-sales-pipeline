"""Run dbt with the database settings from .env.

dbt does not read .env files, so this wrapper loads them first and then calls dbt
with the project and profiles folder already set.

Usage:
    python -m pipeline.run_dbt debug     # test the connection
    python -m pipeline.run_dbt build     # run all models and tests
    python -m pipeline.run_dbt build --select silver
"""

import sys

from dbt.cli.main import dbtRunner

from pipeline.config import PROJECT_ROOT  # importing config loads .env

DBT_DIR = PROJECT_ROOT / "dbt"


def main() -> int:
    args = sys.argv[1:] or ["build"]
    result = dbtRunner().invoke(
        args + ["--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    )
    return 0 if result.success else 1


if __name__ == "__main__":
    sys.exit(main())
