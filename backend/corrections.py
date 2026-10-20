from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from urllib.parse import urlsplit

from fastapi import APIRouter, HTTPException, Path, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from psycopg.types.json import Jsonb

from db import database
from response_cache import cached

router = APIRouter(prefix="/api", tags=["Исправление карантина"])
RawId = Annotated[int, Path(gt=0)]
SOURCE_FIELDS = {"order_id", "order_datetime", "customer_info", "restaurant_info",
                 "courier_info", "dish_details", "total_amount"}
ISSUE_FIELDS = {
    "order_id_missing": "order_id", "order_id_invalid": "order_id", "order_id_conflict": "order_id",
    "datetime_missing": "ordered_at", "datetime_invalid_or_relative": "ordered_at",
    "amount_missing": "total_amount", "amount_invalid_or_approximate": "total_amount",
    "dish_quantity_missing_or_invalid": "quantity", "phone_invalid": "customer_id",
    "customer_unresolved_or_conflicting": "customer_id",
    "customer_name_gender_ambiguous": "customer_id", "customer_name_gender_unknown": "customer_id",
    "courier_unresolved_or_conflicting": "courier_id",
    "courier_name_gender_ambiguous": "courier_id", "courier_name_gender_unknown": "courier_id",
    "restaurant_unrecognized_or_conflicting": "restaurant_id",
    "dish_unrecognized_or_conflicting": "dish_id",
}


class Correction(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_record: dict[str, Annotated[str, Field(max_length=2000)] | None] = Field(min_length=7, max_length=7)
    expected_correction_id: int | None = Field(default=None, gt=0)
    order_id: str = Field(min_length=1, max_length=80)
    ordered_at: datetime
    customer_id: str = Field(pattern=r"^U[0-9]{3,}$")
    restaurant_id: str = Field(pattern=r"^R[0-9]+$", max_length=30)
    dish_id: str = Field(pattern=r"^D[0-9]+$", max_length=30)
    quantity: int = Field(ge=1, le=999999999)
    total_amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)
    fulfillment_type: Literal["pickup", "delivery", "unknown"]
    courier_id: str | None = Field(default=None, pattern=r"^C[0-9]{3,}$")
    phone_extension: str | None = Field(default=None, pattern=r"^[0-9]{1,12}$")
    comment: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def check_record(self):
        if set(self.source_record) != SOURCE_FIELDS:
            raise ValueError("Нужны все семь исходных полей записи.")
        if self.ordered_at.tzinfo is not None:
            raise ValueError("Укажите местное время без часового пояса.")
        if self.fulfillment_type != "delivery" and self.courier_id:
            raise ValueError("Курьер может быть указан только для доставки.")
        return self


def issues(connection, codes):
    rows = connection.execute("SELECT issue_code,description FROM core.issue_catalog WHERE issue_code=ANY(%s)", (codes,)).fetchall()
    labels = {row["issue_code"]: row["description"] for row in rows}
    return [{"code": code, "field": ISSUE_FIELDS.get(code), "message": labels.get(code, code)} for code in codes]


def field_error(field, message):
    raise HTTPException(422, {"message": "Проверьте заполненные поля.", "fields": {field: message}})


@router.get("/correction-options")
def correction_options():
    with database() as connection:
        return {
            "customers": connection.execute("SELECT customer_id,full_name,phone FROM core.customers ORDER BY full_name").fetchall(),
            "couriers": connection.execute("SELECT courier_id,full_name FROM core.couriers ORDER BY full_name").fetchall(),
            "restaurants": connection.execute("SELECT restaurant_id,restaurant_name,city FROM core.restaurants ORDER BY restaurant_name").fetchall(),
            "dishes": connection.execute("SELECT dish_id,dish_name FROM core.dishes ORDER BY dish_name").fetchall(),
        }


@router.get("/quarantine/{raw_id}")
def correction_detail(raw_id: RawId):
    with database() as connection:
        row = connection.execute("""
            SELECT r.source_record,r.correction_id,q.reasons,s.order_id,s.ordered_at,
                   s.customer_id,s.restaurant_id,s.dish_id,s.quantity,s.total_amount,
                   s.fulfillment_type,s.courier_id,s.phone_extension
            FROM core.quarantine q JOIN core.effective_raw_records r USING(raw_id)
            JOIN core.stage_orders s USING(raw_id) WHERE q.raw_id=%s
        """, (raw_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Запись уже обработана или отсутствует. Обновите карантин.")
        source = row.pop("source_record")
        version = row.pop("correction_id")
        errors = issues(connection, row.pop("reasons"))
        return {"source_record": source, "expected_correction_id": version, "values": row, "issues": errors}


@router.get("/corrections")
@cached()
def correction_history(request: Request):
    with database() as connection:
        rows = connection.execute("""
            SELECT correction_id,corrected_at,corrected_record->>'order_id' AS order_id,
                   administrator,comment,run_id FROM core.quarantine_corrections
            ORDER BY correction_id DESC LIMIT 20
        """).fetchall()
    return {"rows": rows}


@router.post("/quarantine/{raw_id}/correct")
def correct_quarantine(raw_id: RawId, body: Correction, request: Request):
    origin = request.headers.get("origin")
    if request.headers.get("sec-fetch-site") == "cross-site" or (origin and urlsplit(origin).hostname != request.url.hostname):
        raise HTTPException(403, "Исправления можно отправлять только со страницы приложения.")
    with database(write=True) as connection:
        acquired = connection.execute("SELECT pg_try_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline')) AS ok").fetchone()["ok"]
        if not acquired:
            raise HTTPException(409, "Идёт другая загрузка или исправление. Повторите через несколько секунд.")
        row = connection.execute("""
            SELECT r.source_record,r.correction_id FROM core.quarantine q
            JOIN core.effective_raw_records r USING(raw_id) WHERE q.raw_id=%s
        """, (raw_id,)).fetchone()
        if not row or row["source_record"] != body.source_record or row["correction_id"] != body.expected_correction_id:
            raise HTTPException(409, "Запись изменилась или уже обработана. Обновите карантин и откройте её заново.")

        order_id = connection.execute("SELECT core.clean_order_id(%s) AS value", (body.order_id,)).fetchone()["value"]
        if order_id is None:
            field_error("order_id", "Укажите номер в формате FD-50001.")
        customer = connection.execute("SELECT * FROM core.customers WHERE customer_id=%s", (body.customer_id,)).fetchone()
        restaurant = connection.execute("SELECT * FROM core.restaurants WHERE restaurant_id=%s", (body.restaurant_id,)).fetchone()
        dish = connection.execute("SELECT * FROM core.dishes WHERE dish_id=%s", (body.dish_id,)).fetchone()
        for field, value in (("customer_id", customer), ("restaurant_id", restaurant), ("dish_id", dish)):
            if value is None:
                field_error(field, "Выберите существующее значение из справочника.")
        courier_info = {"pickup": "Самовывоз", "unknown": "Не указан", "delivery": "Не назначен"}[body.fulfillment_type]
        if body.courier_id:
            courier = connection.execute("SELECT * FROM core.couriers WHERE courier_id=%s", (body.courier_id,)).fetchone()
            if courier is None:
                field_error("courier_id", "Выберите существующего курьера.")
            courier_info = f"{courier['courier_id']} {courier['full_name']}"
        customer_info = f"{customer['customer_id']} {customer['full_name']}"
        if customer["phone"]:
            customer_info += f" / {customer['phone']}"
            if body.phone_extension:
                customer_info += f" доб. {body.phone_extension}"
        elif body.phone_extension:
            field_error("phone_extension", "В справочнике клиента нет основного телефона для добавочного.")
        corrected = {
            "order_id": order_id, "order_datetime": body.ordered_at.isoformat(sep=" "),
            "customer_info": customer_info, "courier_info": courier_info,
            "restaurant_info": f"{restaurant['restaurant_id']} / {restaurant['restaurant_name']} / {restaurant['city']}",
            "dish_details": f"{dish['dish_id']}; {dish['dish_name']}; x{body.quantity}",
            "total_amount": str(body.total_amount),
        }
        correction_id = connection.execute("""
            INSERT INTO core.quarantine_corrections(source_record,corrected_record,administrator,comment)
            VALUES (%s,%s,'Пользователь сайта',%s) RETURNING correction_id
        """, (Jsonb(body.source_record), Jsonb(corrected), body.comment.strip())).fetchone()["correction_id"]
        run_id = connection.execute("SELECT core.run_pipeline() AS id").fetchone()["id"]
        result = connection.execute("""
            SELECT r.disposition,q.reasons FROM core.raw_records r
            LEFT JOIN core.quarantine q USING(raw_id)
            WHERE r.source_record=%s AND r.duplicate_of IS NULL
        """, (Jsonb(body.source_record),)).fetchone()
        if not result:
            raise HTTPException(409, "Исходная запись изменилась. Обновите карантин.")
        if result["disposition"] != "loaded":
            problems = issues(connection, result["reasons"] or [])
            raise HTTPException(422, {"message": "Запись ещё содержит ошибки. Исправления не сохранены.",
                                      "fields": {p["field"]: p["message"] for p in problems if p["field"]}, "issues": problems})
        connection.execute("UPDATE core.quarantine_corrections SET run_id=%s WHERE correction_id=%s", (run_id, correction_id))
        processing = connection.execute("SELECT * FROM core.raw_processing_summary").fetchone()
    return {"status": "loaded", "order_id": order_id, "correction_id": correction_id,
            "run_id": run_id, "processing": processing}
