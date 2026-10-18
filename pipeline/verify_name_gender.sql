BEGIN;
DELETE FROM core.stage_orders;

DO $$
DECLARE base_id bigint;
BEGIN
    SELECT least(coalesce(min(raw_id),0),0)-10 INTO base_id FROM core.raw_records;

    INSERT INTO core.raw_records(raw_id,source_locator,source_record,disposition)
    SELECT base_id+v.n,'name-gender-test',jsonb_build_object(
        'order_id','FD-90000000000' || v.n,
        'order_datetime','2026-01-01 12:00',
        'customer_info',v.customer_info,
        'courier_info',v.courier_info,
        'restaurant_info','R1 / Бургер Хаус / Москва',
        'dish_details','D1; Чизбургер; x1',
        'total_amount','390'
    ),'pending'
    FROM (VALUES
        (1,'Морозов Анна / +79991000012','самовывоз'),
        (2,'Морозова Анна','самовывоз'),
        (3,'U001 Иванов Мина / +79991000001','самовывоз'),
        (4,'Иванов Алексей','Илия Иванов'),
        (5,'U001 Иванов Саша / +79991000001','самовывоз'),
        (6,'Морозов А.С.','Морозова А.С.')
    ) v(n,customer_info,courier_info);

    INSERT INTO core.stage_orders(
        raw_id,order_id,ordered_at,customer_info,courier_info,fulfillment_type,
        restaurant_source_id,restaurant_name,restaurant_city,
        dish_source_id,dish_name,quantity,total_amount
    )
    SELECT raw_id,source_record->>'order_id',timestamp '2026-01-01 12:00',
           source_record->>'customer_info',source_record->>'courier_info',
           CASE WHEN source_record->>'courier_info'='самовывоз' THEN 'pickup' ELSE 'delivery' END,
           'R1','Бургер Хаус','Москва','D1','Чизбургер',1,390
    FROM core.raw_records WHERE raw_id BETWEEN base_id+1 AND base_id+6;

    PERFORM core.step_06_resolve_entities();
    PERFORM core.step_07_load_quarantine();
    PERFORM core.step_08_load_orders();

    ASSERT (SELECT count(*) FROM core.orders WHERE source_raw_id BETWEEN base_id+1 AND base_id+6)=3;
    ASSERT (SELECT count(*) FROM core.quarantine WHERE raw_id BETWEEN base_id+1 AND base_id+6)=3;
    ASSERT (SELECT 'customer_name_gender_ambiguous'=ANY(reasons) FROM core.quarantine WHERE raw_id=base_id+3);
    ASSERT (SELECT 'courier_name_gender_ambiguous'=ANY(reasons) FROM core.quarantine WHERE raw_id=base_id+4);
    ASSERT (SELECT 'customer_name_gender_unknown'=ANY(reasons) FROM core.quarantine WHERE raw_id=base_id+5);
    ASSERT NOT EXISTS (
        SELECT 1 FROM core.raw_records
        WHERE raw_id BETWEEN base_id+1 AND base_id+6 AND disposition='pending'
    );
    ASSERT (SELECT customer_id FROM core.orders WHERE source_raw_id=base_id+1)='U012';
    ASSERT (SELECT customer_id FROM core.orders WHERE source_raw_id=base_id+2)='U012';
    ASSERT (SELECT courier_id FROM core.orders WHERE source_raw_id=base_id+6)='C012';
    ASSERT (SELECT family_name FROM core.customers WHERE customer_id='U012')='Морозова';
END $$;

ROLLBACK;
