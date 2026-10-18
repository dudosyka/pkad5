FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app/backend
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/*.py ./
COPY pipeline/warehouse/corrections.sql /app/pipeline/warehouse/corrections.sql
COPY pipeline/warehouse/functions/step_04_parse_orders.sql /app/pipeline/warehouse/functions/step_04_parse_orders.sql
RUN useradd --uid 10001 --create-home app
USER app
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
