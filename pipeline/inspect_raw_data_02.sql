BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() AS database_name,
       current_user AS database_user,
       current_timestamp AS inspected_at;

SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

SELECT ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default, is_identity,
       character_maximum_length, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'raw_data_02'
ORDER BY ordinal_position;

SELECT c.conname AS constraint_name,
       c.contype AS constraint_type,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint AS c
WHERE c.conrelid = 'public.raw_data_02'::regclass
ORDER BY c.conname;

SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'raw_data_02'
ORDER BY indexname;

WITH expected(column_name) AS (
    VALUES ('order_id'), ('order_datetime'), ('customer_info'),
           ('restaurant_info'), ('dish_details'), ('courier_info'),
           ('total_amount')
)
SELECT e.column_name, c.data_type,
       c.column_name IS NOT NULL AS present_in_actual_table
FROM expected AS e
LEFT JOIN information_schema.columns AS c
  ON c.table_schema = 'public' AND c.table_name = 'raw_data_02'
 AND c.column_name = e.column_name
ORDER BY e.column_name;

SELECT count(*) AS raw_rows FROM public.raw_data_02;

SELECT field.key AS column_name,
       count(*) AS raw_rows,
       count(*) FILTER (WHERE field.value IS NULL) AS null_rows,
       count(*) FILTER (WHERE field.value = '') AS empty_string_rows,
       count(*) FILTER (
           WHERE field.value <> '' AND btrim(field.value) = ''
       ) AS space_only_rows,
       count(*) FILTER (
           WHERE field.value IS NOT NULL
             AND field.value <> btrim(field.value)
       ) AS surrounding_space_rows,
       count(DISTINCT field.value) AS distinct_non_null_values,
       min(length(field.value)) AS min_length,
       max(length(field.value)) AS max_length
FROM public.raw_data_02 AS raw
CROSS JOIN LATERAL jsonb_each_text(to_jsonb(raw)) AS field(key, value)
GROUP BY field.key
ORDER BY field.key;

WITH duplicates AS (
    SELECT to_jsonb(raw) AS raw_record, count(*) AS copies
    FROM public.raw_data_02 AS raw
    GROUP BY to_jsonb(raw)
    HAVING count(*) > 1
)
SELECT count(*) AS duplicate_groups,
       coalesce(sum(copies - 1), 0) AS extra_identical_rows
FROM duplicates;

WITH source AS (
    SELECT to_jsonb(raw) AS j FROM public.raw_data_02 AS raw
), payloads AS (
    SELECT jsonb_build_array(
               j -> 'order_id', j -> 'order_datetime', j -> 'customer_info',
               j -> 'restaurant_info', j -> 'dish_details',
               j -> 'courier_info', j -> 'total_amount'
           ) AS payload
    FROM source
    WHERE j ?& ARRAY['order_id', 'order_datetime', 'customer_info',
                    'restaurant_info', 'dish_details', 'courier_info',
                    'total_amount']
), grouped AS (
    SELECT payload, count(*) AS copies FROM payloads GROUP BY payload
)
SELECT coalesce(sum(copies), 0) AS eligible_rows,
       count(*) FILTER (WHERE copies > 1) AS duplicate_payload_groups,
       coalesce(sum(copies - 1), 0) AS extra_identical_payloads
FROM grouped;

WITH source AS (
    SELECT to_jsonb(raw) AS j FROM public.raw_data_02 AS raw
)
SELECT j ->> 'order_id' AS raw_order_id,
       count(*) AS raw_rows,
       count(DISTINCT j ->> 'order_datetime') AS datetime_variants,
       count(DISTINCT j ->> 'customer_info') AS customer_variants,
       count(DISTINCT j ->> 'restaurant_info') AS restaurant_variants,
       count(DISTINCT j ->> 'courier_info') AS courier_variants,
       count(DISTINCT j ->> 'total_amount') AS amount_variants,
       count(DISTINCT j ->> 'dish_details') AS item_variants
FROM source
WHERE nullif(btrim(j ->> 'order_id'), '') IS NOT NULL
GROUP BY j ->> 'order_id'
HAVING count(*) > 1
ORDER BY raw_rows DESC, raw_order_id
LIMIT 50;

WITH frequencies AS (
    SELECT field.key AS column_name, field.value AS raw_value,
           count(*) AS occurrences
    FROM public.raw_data_02 AS raw
    CROSS JOIN LATERAL jsonb_each_text(to_jsonb(raw)) AS field(key, value)
    GROUP BY field.key, field.value
), ranked AS (
    SELECT *, row_number() OVER (
        PARTITION BY column_name
        ORDER BY occurrences DESC, raw_value NULLS FIRST
    ) AS position
    FROM frequencies
)
SELECT column_name, raw_value, occurrences
FROM ranked
WHERE position <= 10
ORDER BY column_name, position;

SELECT to_jsonb(raw) AS raw_record
FROM public.raw_data_02 AS raw
LIMIT 15;

COMMIT;
