CREATE OR REPLACE FUNCTION core.step_09_build_marts() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE core.mart_restaurant_daily,core.mart_dish_daily,core.mart_fulfillment_daily;
    INSERT INTO core.mart_restaurant_daily
    SELECT o.ordered_at::date,o.restaurant_id,count(*),sum(o.total_amount),
           round(avg(o.total_amount),2),sum(i.quantity)
    FROM core.orders o JOIN core.order_items i USING(order_id)
    GROUP BY 1,2;
    INSERT INTO core.mart_dish_daily
    SELECT o.ordered_at::date,i.dish_id,count(*),sum(i.quantity),sum(o.total_amount)
    FROM core.orders o JOIN core.order_items i USING(order_id)
    GROUP BY 1,2;
    INSERT INTO core.mart_fulfillment_daily
    SELECT ordered_at::date,fulfillment_type,coalesce(courier_id,'UNASSIGNED'),count(*),sum(total_amount)
    FROM core.orders GROUP BY 1,2,3;
END $$;
