import csv
from datetime import date, datetime, timedelta, timezone
import io
import logging
from pathlib import Path
from typing import Annotated, Literal

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
import psycopg
from pydantic import Field

from db import database
from corrections import router as corrections_router
from response_cache import cached

ROOT = Path(__file__).resolve().parent
app = FastAPI(title="Срез · Аналитика доставки", version="1.0.0")
app.include_router(corrections_router)
Restaurant = Annotated[str | None, Query(pattern=r"^R[0-9]+$")]
RestaurantIds = Annotated[list[Annotated[str, Field(pattern=r"^R[0-9]+$")]] | None, Query()]
PERIOD = "order_date BETWEEN %(start)s AND %(end)s AND (%(restaurant)s::text IS NULL OR restaurant_id=%(restaurant)s)"
ORDER_PERIOD = "o.ordered_at >= %(start)s AND o.ordered_at < %(after_end)s AND (%(restaurant)s::text IS NULL OR o.restaurant_id=%(restaurant)s)"


@app.exception_handler(psycopg.Error)
def database_error(_request: Request, error: psycopg.Error):
    logging.error("Database request failed: %s", type(error).__name__)
    return JSONResponse(status_code=503, content={"detail": "База данных временно недоступна. Повторите запрос."})


@app.middleware("http")
async def api_cache_policy(request: Request, call_next):
    response = await call_next(request)
    if request.url.path.startswith("/api/"):
        response.headers.setdefault("Cache-Control", "no-store")
    return response


def period(connection, start, end, restaurant):
    if start is None or end is None:
        bounds = connection.execute("SELECT min(order_date) AS start, max(order_date) AS end FROM core.mart_restaurant_daily").fetchone()
        start, end = start or bounds["start"], end or bounds["end"]
    if start is None or end is None:
        raise HTTPException(409, "Витрины пусты. Сначала выполните загрузку данных.")
    if start > end:
        raise HTTPException(422, "Начало периода должно быть не позже окончания.")
    if (end - start).days > 3660 or end == date.max:
        raise HTTPException(422, "Выберите период не длиннее десяти лет.")
    if start.toordinal() <= (end-start).days+1:
        raise HTTPException(422, "Начало периода слишком раннее для сравнения.")
    if restaurant and not connection.execute("SELECT 1 FROM core.restaurants WHERE restaurant_id=%s", (restaurant,)).fetchone():
        raise HTTPException(404, "Ресторан не найден.")
    return dict(start=start, end=end, after_end=end+timedelta(days=1), restaurant=restaurant)


def hourly_orders(connection, p, restaurants):
    return connection.execute("""
        WITH hourly AS (
            SELECT extract(hour FROM o.ordered_at)::integer AS hour, count(*) AS orders
            FROM core.orders o
            WHERE o.ordered_at >= %(start)s AND o.ordered_at < %(after_end)s
              AND (%(restaurants)s::text[] IS NULL OR o.restaurant_id=ANY(%(restaurants)s::text[]))
            GROUP BY 1
        )
        SELECT h.hour, coalesce(hourly.orders, 0)::bigint AS orders
        FROM generate_series(0, 23) AS h(hour)
        LEFT JOIN hourly USING(hour)
        ORDER BY h.hour
    """, {**p, "restaurants": restaurants or None}).fetchall()


@app.get("/api/health")
def health():
    with database() as connection:
        connection.execute("SELECT 1")
    return {"status": "ok"}


@app.get("/api/bootstrap")
@cached()
def bootstrap(request: Request):
    with database() as connection:
        bounds = connection.execute("SELECT min(order_date) AS start, max(order_date) AS end FROM core.mart_restaurant_daily").fetchone()
        restaurants = connection.execute("SELECT restaurant_id, restaurant_name FROM core.restaurants ORDER BY restaurant_name").fetchall()
        latest_run = connection.execute("SELECT run_id, finished_at FROM core.pipeline_runs WHERE finished_at IS NOT NULL ORDER BY run_id DESC LIMIT 1").fetchone()
        processing = connection.execute("SELECT * FROM core.raw_processing_summary").fetchone()
    return {"bounds": bounds, "restaurants": restaurants, "latest_run": latest_run, "processing": processing}


@app.get("/api/orders-by-hour")
@cached(content=True)
def orders_by_hour(request: Request, start: date | None = None, end: date | None = None,
                   restaurant: RestaurantIds = None):
    with database() as connection:
        p = period(connection, start, end, None)
        selected = sorted(set(restaurant or []))
        if selected:
            found = connection.execute(
                "SELECT restaurant_id FROM core.restaurants WHERE restaurant_id=ANY(%s::text[])",
                (selected,),
            ).fetchall()
            if len(found) != len(selected):
                raise HTTPException(404, "Ресторан не найден.")
        return {"rows": hourly_orders(connection, p, selected)}


@app.get("/api/dashboard")
@cached(content=True)
def dashboard(request: Request, start: date | None = None, end: date | None = None, restaurant: Restaurant = None,
              granularity: Literal["day", "week", "month"] = "week"):
    with database() as connection:
        p = period(connection, start, end, restaurant)
        summary = connection.execute(f"""
            SELECT coalesce(sum(revenue),0) AS revenue, coalesce(sum(orders_count),0)::bigint AS orders,
                   coalesce(round(sum(revenue)/nullif(sum(orders_count),0),2),0) AS average_order,
                   coalesce(sum(units_count),0)::bigint AS units
            FROM core.mart_restaurant_daily WHERE {PERIOD}
        """, p).fetchone()
        days = (p["end"]-p["start"]).days + 1
        previous = {**p, "start": p["start"]-timedelta(days=days), "end": p["start"]-timedelta(days=1)}
        previous_summary = connection.execute(f"""
            SELECT coalesce(sum(revenue),0) AS revenue, coalesce(sum(orders_count),0)::bigint AS orders,
                   coalesce(round(sum(revenue)/nullif(sum(orders_count),0),2),0) AS average_order,
                   coalesce(sum(units_count),0)::bigint AS units
            FROM core.mart_restaurant_daily WHERE {PERIOD}
        """, previous).fetchone()
        trend = connection.execute(f"""
            WITH daily AS (
                SELECT order_date, sum(revenue) AS revenue,sum(orders_count) AS orders
                FROM core.mart_restaurant_daily WHERE {PERIOD} GROUP BY order_date
            ), days AS (
                SELECT generate_series(%(start)s::timestamp,%(end)s::timestamp,interval '1 day')::date AS day
            )
            SELECT greatest(date_trunc(%(grain)s,day)::date,%(start)s) AS date,
                   coalesce(sum(revenue),0) AS revenue,coalesce(sum(orders),0)::bigint AS orders
            FROM days LEFT JOIN daily ON daily.order_date=days.day GROUP BY 1 ORDER BY 1
        """, {**p, "grain": granularity}).fetchall()
        restaurants = connection.execute(f"""
            SELECT r.restaurant_id,r.restaurant_name,r.city,sum(m.orders_count)::bigint AS orders,
                   sum(m.revenue) AS revenue,round(sum(m.revenue)/nullif(sum(m.orders_count),0),2) AS average_order,
                   sum(m.units_count)::bigint AS units
            FROM core.mart_restaurant_daily m JOIN core.restaurants r USING(restaurant_id)
            WHERE {PERIOD} GROUP BY r.restaurant_id ORDER BY revenue DESC,r.restaurant_id
        """, p).fetchall()
        orders_by_hour = hourly_orders(connection, p, [restaurant] if restaurant else None)
        dishes = connection.execute(f"""
            SELECT d.dish_id,d.dish_name,count(*) AS orders,sum(i.quantity)::bigint AS units,
                   sum(o.total_amount) AS revenue
            FROM core.orders o JOIN core.order_items i USING(order_id) JOIN core.dishes d USING(dish_id)
            WHERE {ORDER_PERIOD} GROUP BY d.dish_id ORDER BY units DESC,d.dish_id
        """, p).fetchall()
        fulfillment = connection.execute(f"""
            SELECT CASE WHEN fulfillment_type='delivery' AND courier_id IS NULL THEN 'unassigned'
                        ELSE fulfillment_type END AS type,count(*) AS orders,sum(total_amount) AS revenue
            FROM core.orders o WHERE {ORDER_PERIOD} GROUP BY 1 ORDER BY 1
        """, p).fetchall()
    return {"summary": summary, "previous": previous_summary,
            "period": {"start": p["start"], "end": p["end"], "previous_start": previous["start"], "previous_end": previous["end"]},
            "trend": trend, "restaurants": restaurants, "orders_by_hour": orders_by_hour,
            "dishes": dishes, "fulfillment": fulfillment,
            "fetched_at": datetime.now(timezone.utc)}


@app.get("/api/customers")
@cached(content=True)
def customers(request: Request, start: date | None = None, end: date | None = None, restaurant: Restaurant = None):
    with database() as connection:
        p = period(connection, start, end, restaurant)
        rows = connection.execute(f"""
            SELECT c.customer_id,c.full_name,count(*) AS orders,
                   sum(i.quantity)::bigint AS units,sum(o.total_amount) AS revenue,
                   round(avg(o.total_amount),2) AS average_order,
                   max(o.ordered_at)::date AS last_order_date,
                   dense_rank() OVER (ORDER BY sum(i.quantity) DESC) AS portion_rank
            FROM core.orders o JOIN core.order_items i USING(order_id)
            JOIN core.customers c USING(customer_id)
            WHERE {ORDER_PERIOD}
            GROUP BY c.customer_id ORDER BY units DESC,revenue DESC,c.customer_id
        """, p).fetchall()
        dishes = connection.execute(f"""
            SELECT o.customer_id,d.dish_id,d.dish_name,count(*) AS orders,
                   sum(i.quantity)::bigint AS units,sum(o.total_amount) AS revenue
            FROM core.orders o JOIN core.order_items i USING(order_id)
            JOIN core.dishes d USING(dish_id)
            WHERE {ORDER_PERIOD}
            GROUP BY o.customer_id,d.dish_id
            ORDER BY o.customer_id,units DESC,orders DESC,d.dish_id
        """, p).fetchall()
    by_customer = {row["customer_id"]: [] for row in rows}
    for dish in dishes:
        by_customer[dish.pop("customer_id")].append(dish)
    for row in rows:
        row["dishes"] = by_customer[row["customer_id"]]
    return {"rows": rows}


@app.get("/api/quality")
@cached()
def quality(request: Request):
    with database() as connection:
        summary = connection.execute("SELECT * FROM core.raw_processing_summary").fetchone()
        reasons = connection.execute("SELECT * FROM core.quarantine_reasons ORDER BY affected_raw_rows DESC,reason").fetchall()
        checks = connection.execute("SELECT * FROM core.quality_results ORDER BY check_name").fetchall()
        profile = connection.execute("SELECT * FROM core.raw_column_profile ORDER BY column_name").fetchall()
    return {"summary": summary, "reasons": reasons, "checks": checks, "profile": profile}


@app.get("/api/quarantine")
@cached()
def quarantine(request: Request, page: Annotated[int, Query(ge=1, le=100000)] = 1,
               page_size: Annotated[int, Query(ge=1, le=100)] = 12,
               q: Annotated[str, Query(max_length=160)] = "",
               reason: Annotated[str | None, Query(max_length=80)] = None):
    p = dict(q=q, reason=reason, limit=page_size, offset=(page-1)*page_size)
    where = "(%(reason)s::text IS NULL OR %(reason)s=ANY(reasons)) AND (%(q)s='' OR strpos(lower(source_record::text),lower(%(q)s))>0)"
    with database() as connection:
        total = connection.execute(f"SELECT count(*) AS n FROM core.quarantine WHERE {where}", p).fetchone()["n"]
        rows = connection.execute(f"""
            SELECT raw_id,source_record,reasons FROM core.quarantine WHERE {where}
            ORDER BY raw_id LIMIT %(limit)s OFFSET %(offset)s
        """, p).fetchall()
    return {"rows": rows, "total": total, "page": page, "page_size": page_size}


@app.get("/api/runs")
@cached()
def runs(request: Request):
    with database() as connection:
        rows = connection.execute("""
            SELECT r.run_id,r.started_at,r.finished_at,
                   extract(epoch FROM (r.finished_at-r.started_at)) AS duration_seconds,
                   r.metrics,c.previous_run_id,c.all_metrics_equal
            FROM core.pipeline_runs r LEFT JOIN core.idempotency_comparison c USING(run_id)
            WHERE r.finished_at IS NOT NULL ORDER BY run_id DESC LIMIT 50
        """).fetchall()
    return {"rows": rows}


@app.get("/api/export.csv")
def export(start: date | None = None, end: date | None = None, restaurant: Restaurant = None):
    with database() as connection:
        p = period(connection, start, end, restaurant)
        rows = connection.execute(f"""
            SELECT o.order_id,o.ordered_at,c.full_name AS customer,r.restaurant_name,
                   d.dish_name,i.quantity,o.total_amount,o.fulfillment_type,cr.full_name AS courier
            FROM core.orders o JOIN core.customers c USING(customer_id)
            JOIN core.restaurants r USING(restaurant_id) JOIN core.order_items i USING(order_id)
            JOIN core.dishes d USING(dish_id) LEFT JOIN core.couriers cr USING(courier_id)
            WHERE {ORDER_PERIOD} ORDER BY o.ordered_at,o.order_id
        """, p).fetchall()
    output = io.StringIO(newline="")
    writer = csv.writer(output, delimiter=";")
    writer.writerow(["Заказ", "Дата и время", "Клиент", "Ресторан", "Блюдо", "Количество", "Сумма, ₽", "Способ получения", "Курьер"])
    for row in rows:
        values = list(row.values())
        writer.writerow(["'"+v if isinstance(v,str) and v.lstrip().startswith(("=","+","-","@")) else v for v in values])
    return Response(content="\ufeff"+output.getvalue(), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="orders-{p["start"]}-{p["end"]}.csv"'})


if (ROOT.parent / "frontend/dist").is_dir():
    app.mount("/", StaticFiles(directory=ROOT.parent / "frontend/dist", html=True), name="frontend")
