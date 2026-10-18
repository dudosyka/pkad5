DO $$ BEGIN
    IF current_database() <> 'practice_02' THEN
        RAISE EXCEPTION 'Wrong database: %', current_database();
    END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.raw_records (
    raw_id bigint PRIMARY KEY,
    source_locator text NOT NULL,
    source_record jsonb NOT NULL,
    duplicate_of bigint REFERENCES core.raw_records(raw_id),
    disposition text NOT NULL CHECK (disposition IN ('pending','loaded','quarantined','duplicate')),
    CHECK ((disposition = 'duplicate') = (duplicate_of IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS core.customers (
    customer_id text PRIMARY KEY CHECK (customer_id ~ '^U[0-9]{3}$'),
    family_name text NOT NULL,
    given_name text NOT NULL,
    patronymic text,
    full_name text GENERATED ALWAYS AS
        (family_name || ' ' || given_name || coalesce(' ' || patronymic,'')) STORED,
    phone text UNIQUE CHECK (phone ~ '^\+7[0-9]{10}$')
);
CREATE TABLE IF NOT EXISTS core.couriers (
    courier_id text PRIMARY KEY CHECK (courier_id ~ '^C[0-9]{3}$'),
    family_name text NOT NULL,
    given_name text NOT NULL,
    patronymic text,
    full_name text GENERATED ALWAYS AS
        (family_name || ' ' || given_name || coalesce(' ' || patronymic,'')) STORED
);
CREATE TABLE IF NOT EXISTS core.restaurants (
    restaurant_id text PRIMARY KEY CHECK (restaurant_id ~ '^R[0-9]+$'),
    restaurant_name text NOT NULL,
    city text NOT NULL,
    UNIQUE (restaurant_name, city)
);
CREATE TABLE IF NOT EXISTS core.dishes (
    dish_id text PRIMARY KEY CHECK (dish_id ~ '^D[0-9]+$'),
    dish_name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS core.orders (
    order_id text PRIMARY KEY CHECK (order_id ~ '^FD-[0-9]+$'),
    source_raw_id bigint NOT NULL UNIQUE REFERENCES core.raw_records(raw_id),
    ordered_at timestamp without time zone NOT NULL,
    customer_id text NOT NULL REFERENCES core.customers(customer_id),
    restaurant_id text NOT NULL REFERENCES core.restaurants(restaurant_id),
    courier_id text REFERENCES core.couriers(courier_id),
    fulfillment_type text NOT NULL CHECK (fulfillment_type IN ('pickup','delivery','unknown')),
    customer_phone_extension text CHECK (customer_phone_extension ~ '^[0-9]+$'),
    total_amount numeric(14,2) NOT NULL CHECK (total_amount > 0),
    CHECK (courier_id IS NULL OR fulfillment_type = 'delivery')
);
CREATE TABLE IF NOT EXISTS core.order_items (
    order_id text NOT NULL REFERENCES core.orders(order_id),
    line_no integer NOT NULL CHECK (line_no = 1),
    dish_id text NOT NULL REFERENCES core.dishes(dish_id),
    quantity integer NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, line_no)
);
CREATE INDEX IF NOT EXISTS orders_customer_idx ON core.orders(customer_id);
CREATE INDEX IF NOT EXISTS orders_restaurant_date_idx ON core.orders(restaurant_id, ordered_at);
CREATE INDEX IF NOT EXISTS orders_courier_idx ON core.orders(courier_id);
CREATE INDEX IF NOT EXISTS order_items_dish_idx ON core.order_items(dish_id);

CREATE TABLE IF NOT EXISTS core.quarantine (
    raw_id bigint PRIMARY KEY REFERENCES core.raw_records(raw_id),
    source_table text NOT NULL DEFAULT 'public.raw_data_02',
    source_locator text NOT NULL,
    source_record jsonb NOT NULL,
    reasons text[] NOT NULL CHECK (cardinality(reasons) > 0)
);
CREATE TABLE IF NOT EXISTS core.stage_orders (
    raw_id bigint PRIMARY KEY REFERENCES core.raw_records(raw_id),
    order_id text,
    ordered_at timestamp without time zone,
    customer_info text,
    customer_id text,
    phone_extension text,
    restaurant_source_id text,
    restaurant_name text,
    restaurant_city text,
    restaurant_id text,
    courier_info text,
    courier_id text,
    fulfillment_type text,
    dish_source_id text,
    dish_name text,
    dish_id text,
    quantity integer,
    total_amount numeric,
    errors text[] NOT NULL DEFAULT '{}',
    warnings text[] NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS core.person_aliases (
    entity_kind text NOT NULL CHECK (entity_kind IN ('customer','courier')),
    alias_key text NOT NULL,
    person_id text NOT NULL,
    PRIMARY KEY (entity_kind, alias_key, person_id)
);
CREATE TABLE IF NOT EXISTS core.raw_column_profile (
    column_name text PRIMARY KEY,
    raw_rows bigint NOT NULL,
    null_rows bigint NOT NULL,
    empty_rows bigint NOT NULL,
    placeholder_rows bigint NOT NULL,
    surrounding_space_rows bigint NOT NULL,
    distinct_values bigint NOT NULL,
    min_length integer,
    max_length integer
);
CREATE TABLE IF NOT EXISTS core.raw_format_profile (
    column_name text NOT NULL,
    value_shape text NOT NULL,
    occurrences bigint NOT NULL,
    PRIMARY KEY (column_name, value_shape)
);
CREATE TABLE IF NOT EXISTS core.quality_results (
    check_name text PRIMARY KEY,
    passed boolean NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS core.pipeline_runs (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    finished_at timestamptz,
    metrics jsonb
);
CREATE TABLE IF NOT EXISTS core.cleaning_rules (
    rule_code text PRIMARY KEY,
    description text NOT NULL
);
CREATE TABLE IF NOT EXISTS core.issue_catalog (
    issue_code text PRIMARY KEY,
    description text NOT NULL
);
INSERT INTO core.issue_catalog VALUES
('order_id_missing','Не указан номер заказа.'),
('order_id_invalid','Номер заказа не соответствует распознанным форматам FD-N или №FD N.'),
('order_id_conflict','Одному нормализованному номеру заказа соответствуют разные исходные записи.'),
('datetime_missing','Дата/время отсутствует либо заменена маркером неизвестного значения.'),
('datetime_invalid_or_relative','Некорректная календарная дата, время, относительная дата либо нераспознанный формат.'),
('amount_missing','Сумма отсутствует либо заменена маркером неизвестного значения.'),
('amount_invalid_or_approximate','Сумма приблизительная, некорректная, неположительная или не укладывается в допустимую точность.'),
('dish_quantity_missing_or_invalid','Количество блюда некорректно либо отсутствует и не может быть однозначно восстановлено по блюду, сумме и подтверждённой цене порции.'),
('dish_quantity_inferred','Количество восстановлено делением суммы заказа на единственную подтверждённую цену порции этого блюда; результат — положительное целое число.'),
('phone_invalid','Телефон указан, но не может быть безопасно приведён к стандартному формату.'),
('customer_unresolved_or_conflicting','Клиент не определяется однозначно: недостаточно данных, неизвестная сущность либо противоречие кода, телефона и имени.'),
('courier_unresolved_or_conflicting','Указанный курьер не определяется однозначно; одна фамилия без кода недостаточна.'),
('customer_name_gender_ambiguous','Имя клиента встречается в мужском и женском списках либо допускает несколько вариантов рода; требуется ручная проверка.'),
('customer_name_gender_unknown','Род имени клиента не определён по словарю и однозначно найденной записи справочника.'),
('courier_name_gender_ambiguous','Имя курьера встречается в мужском и женском списках либо допускает несколько вариантов рода; требуется ручная проверка.'),
('courier_name_gender_unknown','Род имени курьера не определён по словарю и однозначно найденной записи справочника.'),
('restaurant_unrecognized_or_conflicting','Неизвестный ресторан либо противоречие кода, названия и города.'),
('dish_unrecognized_or_conflicting','Неизвестное блюдо либо противоречие кода и названия.'),
('customer_phone_missing','Телефон в исходной строке не указан; клиент определён по другим признакам.'),
('courier_unspecified','В исходной строке не указан курьер и не определён способ получения.'),
('courier_unassigned','Доставка указана без назначенного курьера.')
ON CONFLICT(issue_code) DO UPDATE SET description=excluded.description;
CREATE TABLE IF NOT EXISTS core.documentation (
    document_key text PRIMARY KEY,
    media_type text NOT NULL,
    body text NOT NULL
);
INSERT INTO core.cleaning_rules VALUES
('identity','Справочники собраны по явно указанным U/C/R/D-кодам, полным ФИО и согласованным телефонам фактического RAW. Неизвестные сущности требуют проверки и дополнения справочника.'),
('names','Регистр, пробелы, запятые, подчёркивания, ё/е и 0/о нормализуются только для сопоставления с проверенным справочником. Порядок имени и фамилии и инициалы допустимы при единственном кандидате. Одна фамилия без кода/телефона недостаточна.'),
('name_gender','Род полного имени определяется по мужскому и женскому спискам Raven-SL/ru-pnames-list. Пересечение списков и неизвестное имя — карантин. Инициалы и пропуски допустимы только при однозначном сопоставлении с полным именем в справочнике.'),
('female_surname','Для однозначно женского имени фамилии на -ов, -ев, -ёв, -ин, -ын получают окончание -а, включая части двойной фамилии. Готовые женские формы и другие окончания не изменяются. Исходные и нормализованные варианты сохраняются в person_aliases.'),
('identity_conflict','Код, телефон и ФИО должны указывать на одну сущность. Противоречие или несколько кандидатов — карантин, без выбора победителя.'),
('phone','+7, 8 и десятизначный мобильный номер приводятся к +7XXXXXXXXXX. Добавочный номер сохраняется отдельно. Отсутствующий телефон не препятствует идентификации по другим признакам.'),
('datetime','ISO, YYYY/MM/DD, DD.MM.YYYY, DD/MM/YYYY, DD.MM.YY, DD Mon YYYY, YYYYMMDD HHMM и AM/PM разбираются с проверкой календаря и времени. Двузначный год означает 2000..2099. Часовой пояс не задан источником.'),
('amount','Целые, десятичная точка/запятая, RUB/₽/руб./р, тысячи с дробной частью и рубли с копейками разбираются точно. Приблизительные, пропущенные, отрицательные суммы не восстанавливаются.'),
('quantity','Поддержаны название × N, N шт. название, Dn; название; xN и блюдо=название; кол-во=N. Если указано только название блюда, количество восстанавливается из суммы по единственной цене порции среди корректных записей с явным количеством во всех ресторанах. Результат должен быть положительным целым в диапазоне integer; добавляется предупреждение dish_quantity_inferred. Явное некорректное количество, неоднозначная цена и дробный результат остаются ошибкой.'),
('grain','Профилирование установило одну товарную позицию в заказе; 196 повторов оказались полными копиями. Повторный номер заказа с разными исходными строками помещается в карантин целиком.'),
('courier','Самовывоз сохраняется отдельно; не назначен означает доставку без назначенного курьера; пусто/не указан — неизвестный способ. Неоднозначное имя курьера — карантин.'),
('duplicates','Точные копии всех семи исходных полей выделяются до очистки в отдельную категорию duplicate. Копии ошибочной строки также считаются только дубликатами.'),
('lineage','RAW не меняется. Снимок хранит исходный JSON, ctid на момент чтения и отдельный ordinal для каждого вхождения. ctid не используется как постоянный бизнес-ключ.'),
('rerun','Полная атомарная пересборка core; история запусков сохраняется. Сравниваются все бизнес-строки, категории RAW, контрольные суммы и суммы заказов. Изменение RAW требует повторного обследования новых форматов.')
ON CONFLICT (rule_code) DO UPDATE SET description=excluded.description;
