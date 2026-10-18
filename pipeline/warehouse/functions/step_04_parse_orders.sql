CREATE OR REPLACE FUNCTION core.step_04_parse_orders() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.stage_orders(
        raw_id,order_id,ordered_at,customer_info,phone_extension,
        restaurant_source_id,restaurant_name,restaurant_city,
        courier_info,fulfillment_type,dish_source_id,dish_name,quantity,total_amount,
        errors,warnings
    )
    SELECT r.raw_id,core.clean_order_id(j->>'order_id'),
           core.clean_datetime(j->>'order_datetime'),j->>'customer_info',
           substring(split_part(j->>'customer_info','/',2) from 'доб\.[ ]*([0-9]+)'),
           restaurant.source_restaurant_id,restaurant.restaurant_name,restaurant.city,
           j->>'courier_info',
           CASE WHEN core.norm_text(j->>'courier_info')='самовывоз' THEN 'pickup'
                WHEN core.is_missing(j->>'courier_info') THEN 'unknown'
                ELSE 'delivery' END,
           dish.source_dish_id,dish.dish_name,dish.quantity,
           core.clean_amount(j->>'total_amount'),
           array_remove(ARRAY[
               CASE WHEN core.clean_order_id(j->>'order_id') IS NULL
                    THEN CASE WHEN core.is_missing(j->>'order_id') THEN 'order_id_missing' ELSE 'order_id_invalid' END END,
               CASE WHEN core.clean_datetime(j->>'order_datetime') IS NULL
                    THEN CASE WHEN core.is_missing(j->>'order_datetime') THEN 'datetime_missing' ELSE 'datetime_invalid_or_relative' END END,
               CASE WHEN core.clean_amount(j->>'total_amount') IS NULL
                    THEN CASE WHEN core.is_missing(j->>'total_amount') THEN 'amount_missing' ELSE 'amount_invalid_or_approximate' END END,
               CASE WHEN dish.quantity IS NULL THEN 'dish_quantity_missing_or_invalid' END,
               CASE WHEN NOT core.is_missing(split_part(j->>'customer_info','/',2))
                          AND core.clean_phone(split_part(j->>'customer_info','/',2)) IS NULL
                    THEN 'phone_invalid' END
           ]::text[],NULL),
           array_remove(ARRAY[
               CASE WHEN core.is_missing(split_part(j->>'customer_info','/',2)) THEN 'customer_phone_missing' END,
               CASE WHEN core.is_missing(j->>'courier_info') THEN 'courier_unspecified' END,
               CASE WHEN core.norm_text(j->>'courier_info')='не назначен' THEN 'courier_unassigned' END
           ]::text[],NULL)
    FROM core.effective_raw_records r
    CROSS JOIN LATERAL (SELECT r.effective_record AS j) payload
    CROSS JOIN LATERAL core.parse_dish(j->>'dish_details') dish
    CROSS JOIN LATERAL core.parse_restaurant(j->>'restaurant_info') restaurant
    WHERE r.duplicate_of IS NULL;

    WITH conflicts AS (
        SELECT order_id FROM core.stage_orders
        WHERE order_id IS NOT NULL GROUP BY order_id HAVING count(*)>1
    )
    UPDATE core.stage_orders s SET errors=s.errors || ARRAY['order_id_conflict']
    FROM conflicts c WHERE s.order_id=c.order_id;
END $$;
