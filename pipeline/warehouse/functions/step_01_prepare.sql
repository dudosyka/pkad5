CREATE OR REPLACE FUNCTION core.step_01_prepare() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE core.mart_restaurant_daily,core.mart_dish_daily,core.mart_fulfillment_daily,
             core.order_items,core.orders,core.person_aliases,
             core.customers,core.couriers,core.restaurants,core.dishes,
             core.quarantine,core.stage_orders,core.raw_records,
             core.raw_column_profile,core.raw_format_profile,core.quality_results;

    INSERT INTO core.raw_records(raw_id,source_locator,source_record,disposition)
    SELECT row_number() OVER (ORDER BY to_jsonb(r)::text,r.ctid),
           r.ctid::text,to_jsonb(r),'pending'
    FROM public.raw_data_02 r;
END $$;
