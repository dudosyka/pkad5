CREATE TABLE IF NOT EXISTS core.mart_restaurant_daily (
    order_date date NOT NULL,
    restaurant_id text NOT NULL REFERENCES core.restaurants(restaurant_id),
    orders_count bigint NOT NULL,
    revenue numeric(18,2) NOT NULL,
    average_order_amount numeric(14,2) NOT NULL,
    units_count bigint NOT NULL,
    PRIMARY KEY (order_date,restaurant_id)
);
CREATE TABLE IF NOT EXISTS core.mart_dish_daily (
    order_date date NOT NULL,
    dish_id text NOT NULL REFERENCES core.dishes(dish_id),
    orders_count bigint NOT NULL,
    units_count bigint NOT NULL,
    order_revenue numeric(18,2) NOT NULL,
    PRIMARY KEY (order_date,dish_id)
);
CREATE TABLE IF NOT EXISTS core.mart_fulfillment_daily (
    order_date date NOT NULL,
    fulfillment_type text NOT NULL,
    courier_key text NOT NULL,
    orders_count bigint NOT NULL,
    revenue numeric(18,2) NOT NULL,
    PRIMARY KEY (order_date,fulfillment_type,courier_key)
);
