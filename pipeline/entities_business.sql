BEGIN;

CREATE SCHEMA IF NOT EXISTS core;

CREATE TABLE IF NOT EXISTS core.customers (
    customer_id text PRIMARY KEY CHECK (customer_id ~ '^U[0-9]{3,}$'),
    family_name text NOT NULL,
    given_name text NOT NULL,
    patronymic text,
    full_name text GENERATED ALWAYS AS
        (family_name || ' ' || given_name || coalesce(' ' || patronymic,'')) STORED,
    phone text UNIQUE CHECK (phone ~ '^\+7[0-9]{10}$')
);
CREATE TABLE IF NOT EXISTS core.couriers (
    courier_id text PRIMARY KEY CHECK (courier_id ~ '^C[0-9]{3,}$'),
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

COMMIT;
