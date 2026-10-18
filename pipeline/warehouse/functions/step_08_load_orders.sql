CREATE OR REPLACE FUNCTION core.step_08_load_orders() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.orders(order_id,source_raw_id,ordered_at,customer_id,
                            restaurant_id,courier_id,fulfillment_type,
                            customer_phone_extension,total_amount)
    SELECT order_id,raw_id,ordered_at,customer_id,restaurant_id,courier_id,
           fulfillment_type,phone_extension,total_amount
    FROM core.stage_orders WHERE cardinality(errors)=0;
    INSERT INTO core.order_items(order_id,line_no,dish_id,quantity)
    SELECT order_id,1,dish_id,quantity
    FROM core.stage_orders WHERE cardinality(errors)=0;

    UPDATE core.raw_records r SET disposition='loaded'
    FROM core.orders o WHERE o.source_raw_id=r.raw_id;
END $$;
