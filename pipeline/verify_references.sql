BEGIN;
SELECT pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'));
LOCK TABLE public.raw_data_02 IN SHARE ROW EXCLUSIVE MODE;
DELETE FROM public.raw_data_02;

INSERT INTO public.raw_data_02(order_id,order_datetime,customer_info,restaurant_info,
                               dish_details,courier_info,total_amount)
SELECT 'FD-' || n,'2026-01-01 12:00',
       'U' || (700+n) || ' Тестов' || chr(1071+n) || ' Алексей Иванович / +7999300' || lpad(n::text,4,'0'),
       'R' || (700+n) || ' / Ресторан ' || n || ' / Казань',
       'D' || (700+n) || '; Блюдо ' || n || '; x2',
       'C' || (700+n) || ' Курьеров' || chr(1071+n) || ' Иван Сергеевич','200'
FROM generate_series(1,25) n;

INSERT INTO public.raw_data_02(order_id,order_datetime,customer_info,restaurant_info,
                               dish_details,courier_info,total_amount)
SELECT 'FD-' || n,'2026-01-02 12:00',customer,restaurant,dish,courier,amount
FROM (VALUES
    (101,'Автоматов Анна Сергеевна / +79994000001','Казань; Новое кафе','Новый суп × 2','Новый Иван Иванович','200'),
    (102,'Анна Сергеевна Автоматова / 8 9994000001','Казань; Новое кафе','Новый суп × 1','Новый И.И.','100'),
    (103,'Автоматова Анна','Новое кафе','Новый суп','самовывоз','300'),
    (104,'Безкодова Мария','Казань; Новое кафе','Новый суп × 2','самовывоз',NULL),
    (105,'Одинаков Алексей / +79994000002','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (106,'Одинаков Алексей / +79994000003','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (107,'Одинаков Алексей','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (108,'U990 Конфликтов Алексей / +79994000004','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (109,'U990 Другов Иван / +79994000005','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (110,'U991 Общий Алексей / +79994000006','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (111,'U992 Иной Иван / +79994000006','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (112,'Безкодова Мария','Москва; Тёзка','Новый суп × 1','самовывоз','100'),
    (113,'Безкодова Мария','Казань; Тёзка','Новый суп × 1','самовывоз','100'),
    (114,'Безкодова Мария','Тёзка','Новый суп × 1','самовывоз','100'),
    (115,'Неполный А.С.','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (116,'Исправим Алексей','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (117,'Безкодова Мария','R990 / Первое кафе / Казань','Новый суп × 1','самовывоз','100'),
    (118,'Безкодова Мария','R990 / Второе кафе / Казань','Новый суп × 1','самовывоз','100'),
    (119,'Безкодова Мария','Казань; Новое кафе','D990; Первое блюдо; x1','самовывоз','100'),
    (120,'Безкодова Мария','Казань; Новое кафе','D990; Второе блюдо; x1','самовывоз','100'),
    (121,'Однофамилец Алексей Иванович','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (122,'Однофамилец Алексей Сергеевич','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (123,'Однофамилец Алексей','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (124,'U800 Связанов Алексей / +79994000010','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (125,'Связанов Алексей / +79994000010','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (126,'U801 Кодов Иван Иванович','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (127,'Кодов Иван Иванович / +79994000011','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (128,'U802 Новов Сергей / +79994000012','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (129,'U803 Новов Сергей / +79994000013','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (130,'Новов Сергей','Казань; Новое кафе','Новый суп × 1','самовывоз','100'),
    (131,'U801','Казань; Новое кафе','Новый суп × 1','самовывоз','100')
) v(n,customer,restaurant,dish,courier,amount);

INSERT INTO public.raw_data_02 SELECT * FROM public.raw_data_02 WHERE order_id='FD-101';

INSERT INTO core.quarantine_corrections(source_record,corrected_record,administrator)
SELECT to_jsonb(r),to_jsonb(r) || '{"customer_info":"Исправленов Иван / +79994000007"}'::jsonb,
       'reference-test'
FROM public.raw_data_02 r WHERE order_id='FD-116';

SELECT core.run_pipeline();

DO $$
DECLARE person text; metrics jsonb; parsed record;
BEGIN
    ASSERT (SELECT count(*) FROM core.customers)>20;
    ASSERT (SELECT count(*) FROM core.couriers)=26;
    ASSERT (SELECT count(*) FROM core.restaurants)=28;
    ASSERT (SELECT count(*) FROM core.dishes)=26;
    ASSERT (SELECT count(*) FROM core.orders WHERE order_id IN ('FD-101','FD-102','FD-103','FD-104','FD-105','FD-106','FD-112','FD-113','FD-116'))=9;
    ASSERT NOT EXISTS (
        SELECT n FROM generate_series(1,25) n
        LEFT JOIN core.orders o ON o.order_id='FD-' || n
        WHERE o.customer_id IS DISTINCT FROM 'U' || (700+n)
           OR o.courier_id IS DISTINCT FROM 'C' || (700+n)
           OR o.restaurant_id IS DISTINCT FROM 'R' || (700+n)
    );
    SELECT customer_id INTO person FROM core.orders WHERE order_id='FD-101';
    ASSERT (SELECT count(DISTINCT customer_id) FROM core.orders WHERE order_id IN ('FD-101','FD-102','FD-103'))=1;
    ASSERT person=core.reference_id('U','phone:+79994000001');
    ASSERT (SELECT family_name='Автоматова' AND given_name='Анна' AND patronymic='Сергеевна'
            FROM core.customers WHERE customer_id=person);
    ASSERT (SELECT courier_id FROM core.orders WHERE order_id='FD-101')=
           (SELECT courier_id FROM core.orders WHERE order_id='FD-102');
    ASSERT (SELECT quantity=3 AND 'dish_quantity_inferred'=ANY(s.warnings)
            FROM core.orders o JOIN core.stage_orders s ON s.raw_id=o.source_raw_id
            WHERE o.order_id='FD-103');
    ASSERT (SELECT total_amount=200 FROM core.orders WHERE order_id='FD-104');
    ASSERT (SELECT count(*) FROM core.customers WHERE family_name='Одинаков')=2;
    ASSERT NOT EXISTS (SELECT 1 FROM core.customers WHERE customer_id IN ('U990','U991','U992'));
    ASSERT (SELECT count(*) FROM core.quarantine q JOIN core.stage_orders s USING(raw_id)
            WHERE s.order_id IN ('FD-107','FD-108','FD-109','FD-110','FD-111','FD-114','FD-115'))=7;
    ASSERT (SELECT 'restaurant_unrecognized_or_conflicting'=ANY(q.reasons)
            FROM core.quarantine q JOIN core.stage_orders s USING(raw_id) WHERE s.order_id='FD-114');
    ASSERT (SELECT given_name='Иван' FROM core.orders o JOIN core.customers c USING(customer_id)
            WHERE o.order_id='FD-116');
    ASSERT NOT EXISTS (SELECT 1 FROM core.customers WHERE family_name='Исправим');
    ASSERT (SELECT count(*) FROM core.customers WHERE family_name='Однофамилец')=2;
    ASSERT (SELECT count(DISTINCT customer_id) FROM core.orders WHERE order_id IN ('FD-124','FD-125'))=1;
    ASSERT (SELECT customer_id='U801' FROM core.orders WHERE order_id='FD-127');
    ASSERT (SELECT phone='+79994000011' FROM core.customers WHERE customer_id='U801');
    ASSERT EXISTS (SELECT 1 FROM core.orders WHERE order_id='FD-131');
    ASSERT (SELECT count(*) FROM core.quarantine q JOIN core.stage_orders s USING(raw_id)
            WHERE s.order_id IN ('FD-117','FD-118','FD-119','FD-120','FD-123','FD-130'))=6;
    ASSERT (SELECT count(*) FROM core.raw_records WHERE disposition='duplicate')=1;
    ASSERT NOT EXISTS (SELECT 1 FROM core.raw_records WHERE disposition='pending');
    ASSERT (SELECT bool_and(passed) FROM core.quality_results);

    SELECT * INTO parsed FROM core.parse_person('customer','U1001 Алексей Иванович Новиков / +79994000008');
    ASSERT parsed.source_person_id='U1001' AND parsed.family_name='Новиков'
           AND parsed.given_name='Алексей' AND parsed.patronymic='Иванович';
    SELECT * INTO parsed FROM core.parse_person('customer','К0зл0в Роман / +79994000009');
    ASSERT parsed.family_name='Козлов' AND parsed.given_name='Роман';
    SELECT * INTO parsed FROM core.parse_person('courier','U701 Тестов Алексей');
    ASSERT parsed.source_person_id IS NULL AND parsed.family_name IS NULL;

    metrics:=core.current_metrics();
    PERFORM core.run_pipeline();
    ASSERT core.current_metrics()=metrics,'Repeated run changes automatically discovered references';

    INSERT INTO public.raw_data_02 VALUES ('FD-201','2026-01-03 12:00','Добавленов Сергей',
        'Казань; Ещё одно кафе','Ещё одно блюдо × 1','Добавленов Сергей Сергеевич','150');
    INSERT INTO public.raw_data_02 VALUES ('FD-202','2026-01-03 12:00','U1001 Дополненов Иван',
        'Казань; Ещё одно кафе','Ещё одно блюдо × 1','C1001 Дополненов Иван','150');
    PERFORM core.run_pipeline();
    ASSERT (SELECT customer_id FROM core.orders WHERE order_id='FD-101')=person;
    ASSERT EXISTS (SELECT 1 FROM core.orders WHERE order_id='FD-201');
    ASSERT (SELECT customer_id='U1001' AND courier_id='C1001' FROM core.orders WHERE order_id='FD-202');
END $$;

ROLLBACK;
