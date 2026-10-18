CREATE OR REPLACE FUNCTION core.step_10_quality_checks() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE failed text;
BEGIN
    TRUNCATE core.quality_results;
    INSERT INTO core.quality_results(check_name,passed,details)
    SELECT 'all_raw_accounted',
           raw_rows=loaded+quarantined+duplicates AND unaccounted=0,to_jsonb(s)
    FROM core.raw_processing_summary s
    UNION ALL
    SELECT 'raw_multiset_unchanged',
           (SELECT md5(string_agg(to_jsonb(r)::text,chr(10) ORDER BY to_jsonb(r)::text)) FROM public.raw_data_02 r)
           IS NOT DISTINCT FROM
           (SELECT md5(string_agg(source_record::text,chr(10) ORDER BY source_record::text)) FROM core.raw_records),
           jsonb_build_object('live_rows',(SELECT count(*) FROM public.raw_data_02),
                              'snapshot_rows',(SELECT count(*) FROM core.raw_records))
    UNION ALL
    SELECT 'dispositions_are_disjoint',NOT EXISTS(
        SELECT 1 FROM core.raw_records r
        LEFT JOIN core.orders o ON o.source_raw_id=r.raw_id
        LEFT JOIN core.quarantine q ON q.raw_id=r.raw_id
        WHERE CASE r.disposition
            WHEN 'loaded' THEN o.order_id IS NULL OR q.raw_id IS NOT NULL
            WHEN 'quarantined' THEN q.raw_id IS NULL OR o.order_id IS NOT NULL
            WHEN 'duplicate' THEN q.raw_id IS NOT NULL OR o.order_id IS NOT NULL
            ELSE true END
    ),'{}'::jsonb
    UNION ALL
    SELECT 'duplicate_lineage_valid',NOT EXISTS(
        SELECT 1 FROM core.raw_records r
        LEFT JOIN core.raw_records original ON original.raw_id=r.duplicate_of
        WHERE r.disposition='duplicate' AND
              (original.raw_id IS NULL OR original.source_record<>r.source_record
               OR original.duplicate_of IS NOT NULL OR original.raw_id>=r.raw_id)
    ),'{}'::jsonb
    UNION ALL
    SELECT 'quarantine_original_and_reasons_saved',NOT EXISTS(
        SELECT 1 FROM core.quarantine q JOIN core.raw_records r USING(raw_id)
        WHERE q.source_record<>r.source_record OR cardinality(q.reasons)=0
    ),'{}'::jsonb
    UNION ALL
    SELECT 'every_nonduplicate_prepared',
           (SELECT count(*) FROM core.stage_orders)=
           (SELECT count(*) FROM core.raw_records WHERE duplicate_of IS NULL),'{}'::jsonb
    UNION ALL
    SELECT 'one_item_per_order',NOT EXISTS(
        SELECT o.order_id FROM core.orders o LEFT JOIN core.order_items i USING(order_id)
        GROUP BY o.order_id HAVING count(i.order_id)<>1
    ),'{}'::jsonb
    UNION ALL
    SELECT 'person_aliases_have_reference',NOT EXISTS(
        SELECT 1 FROM core.person_aliases a LEFT JOIN core.person_lookup p
        ON p.entity_kind=a.entity_kind AND p.person_id=a.person_id
        WHERE p.person_id IS NULL
    ),'{}'::jsonb
    UNION ALL
    SELECT 'restaurant_mart_reconciles',
           coalesce((SELECT sum(revenue) FROM core.mart_restaurant_daily),0)=
           coalesce((SELECT sum(total_amount) FROM core.orders),0)
           AND coalesce((SELECT sum(orders_count) FROM core.mart_restaurant_daily),0)=
           (SELECT count(*) FROM core.orders),'{}'::jsonb
    UNION ALL
    SELECT 'dish_mart_reconciles',
           coalesce((SELECT sum(order_revenue) FROM core.mart_dish_daily),0)=
           coalesce((SELECT sum(total_amount) FROM core.orders),0)
           AND coalesce((SELECT sum(units_count) FROM core.mart_dish_daily),0)=
           coalesce((SELECT sum(quantity) FROM core.order_items),0),'{}'::jsonb
    UNION ALL
    SELECT 'fulfillment_mart_reconciles',
           coalesce((SELECT sum(revenue) FROM core.mart_fulfillment_daily),0)=
           coalesce((SELECT sum(total_amount) FROM core.orders),0)
           AND coalesce((SELECT sum(orders_count) FROM core.mart_fulfillment_daily),0)=
           (SELECT count(*) FROM core.orders),'{}'::jsonb
    UNION ALL
    SELECT 'loaded_person_names_unambiguous',NOT EXISTS(
        SELECT 1 FROM core.orders o
        JOIN core.customers c USING(customer_id)
        LEFT JOIN core.couriers k USING(courier_id)
        WHERE core.given_name_gender(c.given_name) NOT IN ('male','female')
           OR (o.courier_id IS NOT NULL AND core.given_name_gender(k.given_name) NOT IN ('male','female'))
    ),'{}'::jsonb
    UNION ALL
    SELECT 'female_surnames_standardized',NOT EXISTS(
        SELECT 1 FROM core.person_lookup p
        WHERE core.given_name_gender(p.given_name)='female'
          AND p.family_name IS DISTINCT FROM core.clean_family_name(p.family_name,p.given_name)
    ),'{}'::jsonb;
    SELECT string_agg(check_name,', ' ORDER BY check_name) INTO failed
    FROM core.quality_results WHERE NOT passed;
    IF failed IS NOT NULL THEN RAISE EXCEPTION 'Quality checks failed: %',failed; END IF;
END $$;
