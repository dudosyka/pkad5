from pathlib import Path

from db import database


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent / "pipeline"
    with database(write=True) as connection:
        connection.execute("SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'))")
        for line in (root / "warehouse.sql").read_text().splitlines():
            if line.startswith("\\ir "):
                connection.execute((root / line[4:]).read_text())
    print("Warehouse schema and pipeline installed.")
