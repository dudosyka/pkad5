from contextlib import contextmanager
from contextvars import ContextVar
import os

from fastapi import HTTPException
import psycopg
from psycopg import IsolationLevel
from psycopg.rows import dict_row

read_connection = ContextVar("read_connection", default=None)


def connection_options():
    if os.environ.get("DATABASE_URL"):
        return {"conninfo": os.environ["DATABASE_URL"]}
    if os.environ.get("PGHOST"):
        return {}
    raise HTTPException(503, "Задайте DATABASE_URL или параметры PGHOST, PGDATABASE, PGUSER, PGPASSWORD.")


@contextmanager
def database(*, write=False):
    current = read_connection.get()
    if not write and current is not None:
        yield current
        return
    timeout = 90000 if write else 15000
    with psycopg.connect(**connection_options(), connect_timeout=8, row_factory=dict_row,
                         options=f"-c statement_timeout={timeout} -c lock_timeout=5000") as connection:
        if connection.info.dbname != "practice_02":
            raise HTTPException(503, "Приложение работает с базой practice_02.")
        connection.read_only = not write
        connection.isolation_level = IsolationLevel.READ_COMMITTED
        if not write:
            connection.execute("SELECT pg_advisory_xact_lock_shared(hashtext(current_database()),hashtext('core.run_pipeline'))")
        token = read_connection.set(connection) if not write else None
        try:
            yield connection
        finally:
            if token is not None:
                read_connection.reset(token)
