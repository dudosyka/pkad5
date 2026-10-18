CREATE OR REPLACE VIEW core.idempotency_comparison AS
WITH previous AS (
    SELECT run_id,metrics,
           lag(run_id) OVER (ORDER BY run_id) AS previous_run_id,
           lag(metrics) OVER (ORDER BY run_id) AS previous_metrics
    FROM core.pipeline_runs WHERE finished_at IS NOT NULL
)
SELECT previous_run_id,run_id,
       previous_metrics->>'raw_checksum'=metrics->>'raw_checksum' AS same_raw,
       previous_metrics->>'target_checksum'=metrics->>'target_checksum' AS same_business_rows,
       previous_metrics->>'dispositions_checksum'=metrics->>'dispositions_checksum' AS same_dispositions,
       previous_metrics->>'marts_checksum'=metrics->>'marts_checksum' AS same_marts,
       previous_metrics=metrics AS all_metrics_equal,
       previous_metrics,metrics
FROM previous WHERE previous_run_id IS NOT NULL;

CREATE OR REPLACE VIEW core.analytics_restaurants AS
SELECT r.restaurant_id,r.restaurant_name,r.city,
       sum(m.orders_count)::bigint AS orders_count,
       sum(m.revenue) AS revenue,
       round(sum(m.revenue)/nullif(sum(m.orders_count),0),2) AS average_order_amount,
       sum(m.units_count)::bigint AS units_count
FROM core.mart_restaurant_daily m JOIN core.restaurants r USING(restaurant_id)
GROUP BY r.restaurant_id;

CREATE OR REPLACE VIEW core.analytics_dishes AS
SELECT d.dish_id,d.dish_name,sum(m.orders_count)::bigint AS orders_count,
       sum(m.units_count)::bigint AS units_count,sum(m.order_revenue) AS order_revenue
FROM core.mart_dish_daily m JOIN core.dishes d USING(dish_id)
GROUP BY d.dish_id;

CREATE OR REPLACE VIEW core.analytics_monthly AS
SELECT date_trunc('month',order_date)::date AS order_month,
       sum(orders_count)::bigint AS orders_count,sum(revenue) AS revenue,
       round(sum(revenue)/nullif(sum(orders_count),0),2) AS average_order_amount
FROM core.mart_restaurant_daily GROUP BY 1;

CREATE OR REPLACE VIEW core.analytics_fulfillment AS
SELECT m.fulfillment_type,m.courier_key,c.full_name AS courier_name,
       sum(m.orders_count)::bigint AS orders_count,sum(m.revenue) AS revenue
FROM core.mart_fulfillment_daily m
LEFT JOIN core.couriers c ON c.courier_id=m.courier_key
GROUP BY m.fulfillment_type,m.courier_key,c.full_name;
