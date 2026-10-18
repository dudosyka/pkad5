BEGIN;
SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'));
DELETE FROM core.quarantine;
DELETE FROM core.order_items;
DELETE FROM core.orders;
DELETE FROM core.stage_orders;
DELETE FROM core.raw_records;

INSERT INTO core.raw_records(raw_id,source_locator,source_record,disposition)
SELECT -v.n,'quantity-test',jsonb_build_object(
    'order_id','FD-' || (900000000000+v.n),
    'order_datetime','2026-01-01 12:00',
    'customer_info',CASE WHEN v.n IN (11,21) THEN 'Неизвестный клиент' ELSE 'Иванов Алексей' END,
    'courier_info','самовывоз',
    'restaurant_info',CASE WHEN v.n=23 THEN 'Неизвестный ресторан'
                           WHEN v.n IN (2,13,18) THEN 'R2 / Пицца 24 / Москва'
                           ELSE 'R1 / Бургер Хаус / Москва' END,
    'dish_details',v.dish_details,'total_amount',v.amount
),'pending'
FROM (VALUES
    (1,'Чизбургер × 2','780'),
    (2,'Чизбургер','1170'),
    (3,'Чизбургер','390'),
    (4,'Чизбургер','400'),
    (5,'Чизбургер',NULL),
    (6,'Чизбургер','0'),
    (7,'Чизбургер','-390'),
    (8,'Чизбургер','837518622720'),
    (9,'Чизбургер × 0','780'),
    (10,'Чизбургер × -2','780'),
    (11,'Чизбургер','780'),
    (12,'Пепперони × 1','650'),
    (13,'Пепперони × 1','700'),
    (14,'Пепперони','1300'),
    (15,'Филадельфия','1580'),
    (16,'Неизвестное блюдо','780'),
    (17,'Борщ × 3','0.99'),
    (18,'Борщ','0.66'),
    (19,'Чизбургер × 2','780'),
    (20,'Неизвестное блюдо','0'),
    (21,'Паста × 2','1180'),
    (22,'Паста','1770'),
    (23,'Чизбургер','780'),
    (24,'блюдо=Чизбургер; кол-во=0','780'),
    (25,'0 шт. Чизбургер','780'),
    (26,'D1; Чизбургер; x0','780'),
    (27,'Чизбургер × 2 шт.','780'),
    (28,'Чизбургер','1560')
) v(n,dish_details,amount);

INSERT INTO core.quarantine_corrections(source_record,corrected_record,administrator)
SELECT source_record,source_record || '{"dish_details":"Чизбургер","total_amount":"780"}'::jsonb,
       'quantity-test'
FROM core.raw_records WHERE raw_id=-20;

SELECT core.step_03_mark_duplicates();
SELECT core.step_04_parse_orders();
SELECT core.step_06_resolve_entities();
SELECT core.step_07_load_quarantine();
SELECT core.step_08_load_orders();

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM core.orders)=10;
    ASSERT (SELECT count(*) FROM core.quarantine)=18;
    ASSERT (SELECT count(*) FROM core.stage_orders WHERE 'dish_quantity_inferred'=ANY(warnings))=7;
    ASSERT NOT EXISTS (
        SELECT 1 FROM (VALUES (2,3),(3,1),(11,2),(18,2),(20,2),(23,2),(28,4)) v(n,quantity)
        LEFT JOIN core.stage_orders s ON s.raw_id=-v.n
        WHERE s.quantity IS DISTINCT FROM v.quantity
           OR NOT ('dish_quantity_inferred'=ANY(s.warnings))
           OR 'dish_quantity_missing_or_invalid'=ANY(s.errors)
    );
    ASSERT (SELECT array_agg(-raw_id ORDER BY -raw_id) FROM core.quarantine)=
        ARRAY[4,5,6,7,8,9,10,11,14,15,16,21,22,23,24,25,26,27]::bigint[];
    ASSERT NOT EXISTS (
        SELECT 1 FROM core.stage_orders
        WHERE raw_id IN (-4,-5,-6,-7,-8,-9,-10,-14,-15,-16,-22,-24,-25,-26,-27)
          AND (quantity IS NOT NULL OR NOT ('dish_quantity_missing_or_invalid'=ANY(errors)))
    );
    ASSERT NOT EXISTS (
        SELECT 1 FROM (VALUES (1,2),(12,1),(13,1),(17,3),(19,2),(21,2)) v(n,quantity)
        LEFT JOIN core.stage_orders s ON s.raw_id=-v.n
        WHERE s.quantity IS DISTINCT FROM v.quantity OR 'dish_quantity_inferred'=ANY(s.warnings)
    );
    ASSERT (SELECT 'customer_unresolved_or_conflicting'=ANY(reasons) FROM core.quarantine WHERE raw_id=-11);
    ASSERT (SELECT 'restaurant_unrecognized_or_conflicting'=ANY(reasons) FROM core.quarantine WHERE raw_id=-23);
    ASSERT (SELECT source_record->>'dish_details' FROM core.raw_records WHERE raw_id=-20)='Неизвестное блюдо';
    ASSERT NOT EXISTS (SELECT 1 FROM core.raw_records WHERE disposition='pending');

    DELETE FROM core.stage_orders WHERE NOT ('dish_quantity_inferred'=ANY(warnings));
    UPDATE core.stage_orders SET quantity=NULL,errors=ARRAY['dish_quantity_missing_or_invalid'],warnings='{}'
    WHERE raw_id=-28;
    PERFORM core.step_06_resolve_entities();
    ASSERT (SELECT quantity IS NULL AND 'dish_quantity_missing_or_invalid'=ANY(errors)
            FROM core.stage_orders WHERE raw_id=-28);
END $$;

ROLLBACK;
