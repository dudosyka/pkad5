# pkad5

Аналитика заказов доставки: PostgreSQL, FastAPI, React.

- `backend/` — API, Docker Compose, деплой и интеграционные тесты.
- `frontend/` — интерфейс и Nginx.
- `pipeline/` — SQL-функции ETL, проверки и схема `er.jpg`.

Нужны PostgreSQL с базой `practice_02` и исходной таблицей `public.raw_data_02`, `psql` и Docker Compose.

Укажите подключение через переменные PostgreSQL и установите хранилище:

```sh
psql -X -d practice_02 -f pipeline/warehouse.sql
psql -X -v ON_ERROR_STOP=1 -d practice_02 -c "SELECT core.run_pipeline();"
```

Pipeline восстанавливает пропущенное количество по сумме заказа и цене блюда, а пропущенную или нераспознанную сумму — по явно указанному количеству и цене. Например, `Чизбургер × 2` без суммы получает `780` при подтверждённой цене `390`. В текущей модели в заказе одно блюдо с указанным количеством порций. Цена должна совпадать во всех корректных записях с явно указанными суммой и количеством; восстановленные значения не используются как подтверждение. Расчёт выполняется без округления, исходный RAW сохраняется, в `stage_orders.warnings` записывается `dish_quantity_inferred` или `amount_inferred`. Если данных недостаточно или цена неоднозначна, запись остаётся в карантине. Распознанная сумма не пересчитывается.

Проверки pipeline: `pipeline/verify_pipeline.sql`; проверки восстановления с откатом изменений: `pipeline/verify_quantity.sql` и `pipeline/verify_amount.sql`.

Скопируйте `backend/.env.example` в `backend/.env`, задайте `DATABASE_URL` и запустите приложение:

```sh
docker compose --env-file backend/.env -f backend/compose.yaml up -d --build
```

Интерфейс: http://127.0.0.1:8080. Проверки: `docker compose --env-file backend/.env -f backend/compose.yaml --profile test run --build --rm tests`.

Ссылка «Схема данных» открывает `/er.jpg`. Nginx отдаёт файл `pipeline/er.jpg` напрямую; старый адрес `/api/schema.svg` перенаправляется на него.
