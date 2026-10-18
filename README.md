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

Скопируйте `backend/.env.example` в `backend/.env`, задайте `DATABASE_URL` и запустите приложение:

```sh
docker compose --env-file backend/.env -f backend/compose.yaml up -d --build
```

Интерфейс: http://127.0.0.1:8080. Проверки: `docker compose --env-file backend/.env -f backend/compose.yaml --profile test run --build --rm tests`.

Ссылка «Схема данных» открывает `/er.jpg`. Nginx отдаёт файл `pipeline/er.jpg` напрямую; старый адрес `/api/schema.svg` перенаправляется на него.
