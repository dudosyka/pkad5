from pathlib import Path

from db import database


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent / "pipeline"
    with database(write=True) as connection:
        connection.execute("SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'))")
        for file in ("warehouse/corrections.sql", "warehouse/functions/step_04_parse_orders.sql"):
            connection.execute((root / file).read_text())
    print("Quarantine correction schema installed.")
