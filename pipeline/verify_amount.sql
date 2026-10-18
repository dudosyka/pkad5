BEGIN;
SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'));
DELETE FROM core.quarantine;
DELETE FROM core.order_items;
DELETE FROM core.orders;
DELETE FROM core.stage_orders;
DELETE FROM core.raw_records;

INSERT INTO core.raw_records(raw_id,source_locator,source_record,disposition)
SELECT -v.n,'amount-test',jsonb_build_object(
    'order_id','FD-' || (900000000000+v.n),
    'order_datetime','2026-01-01 12:00',
    'customer_info',CASE WHEN v.n=19 THEN 'Неизвестный клиент' ELSE 'Иванов Алексей' END,
    'courier_info','самовывоз',
    'restaurant_info',CASE WHEN v.n=20 THEN 'Неизвестный ресторан'
                           WHEN v.n IN (2,12,22) THEN 'R2 / Пицца 24 / Москва'
                           ELSE 'R1 / Бургер Хаус / Москва' END,
    'dish_details',v.dish_details,'total_amount',v.amount
),'pending'
FROM (VALUES
    (1,'Чизбургер × 2','780'),
    (2,'Чизбургер × 3',''),
    (3,'Чизбургер × 1',NULL),
    (4,'Чизбургер × 2','-'),
    (5,'Чизбургер × 4','не указано'),
    (6,'Чизбургер × 2','NULL'),
    (7,'Чизбургер × 2','около 800'),
    (8,'Чизбургер × 2','0'),
    (9,'Чизбургер × 2','-780'),
    (10,'Чизбургер × 2','восемьсот'),
    (11,'Пепперони × 2','1000'),
    (12,'Пепперони × 1','650'),
    (13,'Пепперони × 3',NULL),
    (14,'Филадельфия × 2',NULL),
    (15,'Неизвестное блюдо × 2',NULL),
    (16,'Чизбургер',NULL),
    (17,'Чизбургер × 0',NULL),
    (18,'Чизбургер × -2',NULL),
    (19,'Чизбургер × 2',NULL),
    (20,'Чизбургер × 2',NULL),
    (21,'Борщ × 3','0.99'),
    (22,'Борщ × 2',NULL),
    (23,'Лапша с курицей × 1','999999999999.99'),
    (24,'Лапша с курицей × 2',NULL),
    (25,'Паста × 3','1'),
    (26,'Паста × 2',NULL),
    (27,'Чизбургер × 2','1.234'),
    (28,'Неизвестное блюдо',NULL),
    (29,'Чизбургер','780')
) v(n,dish_details,amount);

INSERT INTO core.quarantine_corrections(source_record,corrected_record,administrator)
SELECT source_record,source_record || '{"dish_details":"Чизбургер × 3","total_amount":"-"}'::jsonb,
       'amount-test'
FROM core.raw_records WHERE raw_id=-28;

SELECT core.step_03_mark_duplicates();
SELECT core.step_04_parse_orders();
SELECT core.step_06_resolve_entities();
SELECT core.step_07_load_quarantine();
SELECT core.step_08_load_orders();

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM core.orders)=19;
    ASSERT (SELECT count(*) FROM core.quarantine)=10;
    ASSERT (SELECT count(*) FROM core.stage_orders WHERE 'amount_inferred'=ANY(warnings))=14;
    ASSERT NOT EXISTS (
        SELECT 1 FROM (VALUES
            (2,1170),(3,390),(4,780),(5,1560),(6,780),(7,780),(8,780),
            (9,780),(10,780),(19,780),(20,780),(22,0.66),(27,780),(28,1170)
        ) v(n,amount)
        LEFT JOIN core.stage_orders s ON s.raw_id=-v.n
        WHERE s.total_amount IS DISTINCT FROM v.amount OR NOT ('amount_inferred'=ANY(s.warnings))
           OR s.errors && ARRAY['amount_missing','amount_invalid_or_approximate']
    );
    ASSERT (SELECT array_agg(-raw_id ORDER BY -raw_id) FROM core.quarantine)=
        ARRAY[13,14,15,16,17,18,19,20,24,26]::bigint[];
    ASSERT NOT EXISTS (
        SELECT 1 FROM core.stage_orders WHERE raw_id IN (-13,-14,-15,-16,-17,-18,-24,-26)
          AND (total_amount IS NOT NULL OR NOT ('amount_missing'=ANY(errors)))
    );
    ASSERT NOT EXISTS (
        SELECT 1 FROM (VALUES (1,780),(11,1000),(12,650),(21,0.99),(23,999999999999.99),(25,1)) v(n,amount)
        LEFT JOIN core.stage_orders s ON s.raw_id=-v.n
        WHERE s.total_amount IS DISTINCT FROM v.amount OR 'amount_inferred'=ANY(s.warnings)
    );
    ASSERT (SELECT quantity=2 AND total_amount=780 AND 'dish_quantity_inferred'=ANY(warnings)
            FROM core.stage_orders WHERE raw_id=-29);
    ASSERT (SELECT quantity IS NULL AND total_amount IS NULL FROM core.stage_orders WHERE raw_id=-16);
    ASSERT (SELECT 'customer_unresolved_or_conflicting'=ANY(reasons) FROM core.quarantine WHERE raw_id=-19);
    ASSERT (SELECT 'restaurant_unrecognized_or_conflicting'=ANY(reasons) FROM core.quarantine WHERE raw_id=-20);
    ASSERT (SELECT source_record->>'dish_details' FROM core.raw_records WHERE raw_id=-28)='Неизвестное блюдо';
    ASSERT NOT EXISTS (SELECT 1 FROM core.raw_records WHERE disposition='pending');

    UPDATE core.stage_orders SET total_amount=NULL,errors=ARRAY['amount_missing'] WHERE raw_id=-29;
    PERFORM core.step_06_resolve_entities();
    ASSERT (SELECT total_amount IS NULL FROM core.stage_orders WHERE raw_id=-29);

    DELETE FROM core.stage_orders WHERE NOT (warnings && ARRAY['dish_quantity_inferred','amount_inferred']);
    UPDATE core.stage_orders SET total_amount=NULL,errors=ARRAY['amount_missing'],warnings='{}' WHERE raw_id=-2;
    UPDATE core.stage_orders SET quantity=NULL,total_amount=780,
                                errors=ARRAY['dish_quantity_missing_or_invalid'],warnings='{}' WHERE raw_id=-29;
    PERFORM core.step_06_resolve_entities();
    ASSERT (SELECT total_amount IS NULL AND 'amount_missing'=ANY(errors) FROM core.stage_orders WHERE raw_id=-2);
    ASSERT (SELECT quantity IS NULL AND 'dish_quantity_missing_or_invalid'=ANY(errors) FROM core.stage_orders WHERE raw_id=-29);
END $$;

ROLLBACK;
