CREATE OR REPLACE FUNCTION core.current_metrics() RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT to_jsonb(s) || jsonb_build_object(
        'customers',(SELECT count(*) FROM core.customers),
        'couriers',(SELECT count(*) FROM core.couriers),
        'restaurants',(SELECT count(*) FROM core.restaurants),
        'dishes',(SELECT count(*) FROM core.dishes),
        'orders',(SELECT count(*) FROM core.orders),
        'order_items',(SELECT count(*) FROM core.order_items),
        'units',coalesce((SELECT sum(quantity) FROM core.order_items),0),
        'total_amount',coalesce((SELECT sum(total_amount) FROM core.orders),0),
        'quality_checks_passed',(SELECT bool_and(passed) FROM core.quality_results),
        'raw_checksum',(SELECT md5(string_agg(source_record::text,chr(10) ORDER BY source_record::text)) FROM core.raw_records),
        'target_checksum',(
            SELECT md5(string_agg(table_name || ':' || payload,chr(10) ORDER BY table_name,payload))
            FROM (
                SELECT 'customers' AS table_name,to_jsonb(t)::text AS payload FROM core.customers t
                UNION ALL SELECT 'couriers',to_jsonb(t)::text FROM core.couriers t
                UNION ALL SELECT 'restaurants',to_jsonb(t)::text FROM core.restaurants t
                UNION ALL SELECT 'dishes',to_jsonb(t)::text FROM core.dishes t
                UNION ALL SELECT 'orders',to_jsonb(t)::text FROM core.orders t
                UNION ALL SELECT 'order_items',to_jsonb(t)::text FROM core.order_items t
            ) business_rows
        ),
        'dispositions_checksum',(
            SELECT md5(string_agg(to_jsonb(t)::text,chr(10) ORDER BY t.raw_id))
            FROM (
                SELECT r.raw_id,r.disposition,r.duplicate_of,q.reasons,s.warnings
                FROM core.raw_records r LEFT JOIN core.quarantine q USING(raw_id)
                LEFT JOIN core.stage_orders s USING(raw_id)
            ) t
        ),
        'marts_checksum',(
            SELECT md5(string_agg(table_name || ':' || payload,chr(10) ORDER BY table_name,payload))
            FROM (
                SELECT 'restaurant' AS table_name,to_jsonb(t)::text AS payload FROM core.mart_restaurant_daily t
                UNION ALL SELECT 'dish',to_jsonb(t)::text FROM core.mart_dish_daily t
                UNION ALL SELECT 'fulfillment',to_jsonb(t)::text FROM core.mart_fulfillment_daily t
            ) marts
        )
    ) FROM core.raw_processing_summary s
$$;
