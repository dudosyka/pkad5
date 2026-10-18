BEGIN;
SELECT core.run_pipeline() AS first_run;
COMMIT;
BEGIN;
SELECT core.run_pipeline() AS second_run;
COMMIT;

DO $$
DECLARE result record; parsed record;
BEGIN
    ASSERT current_database()='practice_02';
    ASSERT (
        SELECT array_agg(substring(p.proname FROM 6 FOR 2) ORDER BY p.proname)
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='core' AND p.proname ~ '^step_[0-9]{2}_'
    ) = ARRAY['01','02','03','04','05','06','07','08','09','10'];
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='core' AND p.prokind='f'
          AND obj_description(p.oid,'pg_proc') IS NOT NULL
    );
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='core' AND p.prokind='f'
          AND (strpos(p.prosrc,'--')>0 OR strpos(p.prosrc,'/*')>0)
    );
    ASSERT core.clean_order_id('№FD 50002')='FD-50002';
    ASSERT core.clean_order_id('') IS NULL;
    ASSERT core.clean_order_id('garbage 50002') IS NULL;
    ASSERT core.clean_datetime('2026-05-24T10:15:55')=timestamp '2026-05-24 10:15:55';
    ASSERT core.clean_datetime('2026/01/01 04:21')=timestamp '2026-01-01 04:21';
    ASSERT core.clean_datetime('26.01.26 22:37')=timestamp '2026-01-26 22:37';
    ASSERT core.clean_datetime('23/03/2026 07:53')=timestamp '2026-03-23 07:53';
    ASSERT core.clean_datetime('05.03.2026 02:12 PM')=timestamp '2026-03-05 14:12';
    ASSERT core.clean_datetime('05.03.2026 12:12 AM')=timestamp '2026-03-05 00:12';
    ASSERT core.clean_datetime('05.03.2026 00:12 AM') IS NULL;
    ASSERT core.clean_datetime('27 Apr 2026 08:05')=timestamp '2026-04-27 08:05';
    ASSERT core.clean_datetime('20260516 0947')=timestamp '2026-05-16 09:47';
    ASSERT core.clean_datetime('15.06.2026 в 19:09')=timestamp '2026-06-15 19:09';
    ASSERT core.clean_datetime('31.02.2026 12:00') IS NULL;
    ASSERT core.clean_datetime('15.03.2026 25:61') IS NULL;
    ASSERT core.clean_datetime('сегодня утром') IS NULL;
    ASSERT core.clean_amount('2,360.00')=2360;
    ASSERT core.clean_amount('1.280,50')=1280.50;
    ASSERT core.clean_amount('1 280,50 р')=1280.50;
    ASSERT core.clean_amount('1280 рублей 25 коп.')=1280.25;
    ASSERT core.clean_amount('₽ 960')=960;
    ASSERT core.clean_amount('780 руб.')=780;
    ASSERT core.clean_amount('около 1000') IS NULL;
    ASSERT core.clean_amount('1,280') IS NULL;
    ASSERT core.clean_amount('-1') IS NULL;
    ASSERT core.clean_amount('0') IS NULL;
    ASSERT core.clean_phone('+7 (999) 100-00-20')='+79991000020';
    ASSERT core.clean_phone('8 9991000014')='+79991000014';
    ASSERT core.clean_phone('9991000014')='+79991000014';
    ASSERT core.clean_phone('+79991000014 доб. 12')='+79991000014';
    ASSERT core.clean_phone('12') IS NULL;
    ASSERT core.clean_phone('++79991000014') IS NULL;
    ASSERT core.clean_phone('799+91000014') IS NULL;
    ASSERT core.resolve_person('customer','К0зл0в Роман')='U010';
    ASSERT core.resolve_person('customer','не указан / тел. +79991000004')='U004';
    ASSERT core.resolve_person('customer','[U015] Наталья Зайцев')='U015';
    ASSERT core.resolve_person('customer','U001 Иванов Алексей / +79991000002') IS NULL;
    ASSERT core.resolve_person('customer','Петров Сергей / +79991000001') IS NULL;
    ASSERT core.resolve_person('customer','U001 Петров Сергей') IS NULL;
    ASSERT core.resolve_person('customer','U001 U002 Иванов Алексей') IS NULL;
    ASSERT core.resolve_person('customer','Иванов Алексей / +79991000001 / +79991000002') IS NULL;
    ASSERT core.resolve_person('courier','Иванов Алексей / ignored') IS NULL;
    ASSERT core.resolve_person('courier','Морозов') IS NULL;
    ASSERT core.resolve_person('courier','Морозов А.С.')='C012';
    ASSERT core.given_name_gender('Анна')='female';
    ASSERT core.given_name_gender('ИВАН')='male';
    ASSERT core.given_name_gender('Мина')='ambiguous';
    ASSERT core.given_name_gender('Илия')='ambiguous';
    ASSERT core.given_name_gender('Саша')='unknown';
    ASSERT core.given_name_gender(NULL)='unknown';
    ASSERT core.clean_family_name('Морозов','Анна')='Морозова';
    ASSERT core.clean_family_name('Морозова','Анна')='Морозова';
    ASSERT core.clean_family_name('Иванов','Иван')='Иванов';
    ASSERT core.clean_family_name('Иванов','Мина')='Иванов';
    ASSERT core.clean_family_name('Ким','Анна')='Ким';
    ASSERT core.clean_family_name('Шевченко','Анна')='Шевченко';
    ASSERT core.clean_family_name('Иванов-Петров','Анна')='Иванова-Петрова';
    ASSERT core.resolve_person('customer','Морозова Анна')='U012';
    ASSERT core.resolve_person('customer','Морозов Анна')='U012';
    ASSERT core.resolve_person('customer','Морозов / +79991000012')='U012';
    ASSERT core.resolve_person('customer','U012 Морозова')='U012';
    ASSERT core.resolve_person('courier','Морозова А.С.')='C012';
    ASSERT core.person_name_gender('customer','U001 Иванов Мина',NULL)='ambiguous';
    ASSERT core.person_name_gender('courier','Илия Иванов',NULL)='ambiguous';
    ASSERT core.person_name_gender('customer','Иванов Саша',NULL)='unknown';
    ASSERT core.person_name_gender('courier','Морозов А.С.','C012')='female';
    ASSERT (SELECT family_name FROM core.customers WHERE customer_id='U012')='Морозова';
    ASSERT (SELECT family_name FROM core.couriers WHERE courier_id='C012')='Морозова';
    SELECT * INTO parsed FROM core.parse_dish('D4; Борщ; x3');
    ASSERT parsed.source_dish_id='D4' AND parsed.dish_name='Борщ' AND parsed.quantity=3;
    SELECT * INTO parsed FROM core.parse_dish('2 шт. Картофель фри');
    ASSERT parsed.dish_name='Картофель фри' AND parsed.quantity=2;
    SELECT * INTO parsed FROM core.parse_dish('блюдо=Том Ям; кол-во=4');
    ASSERT parsed.dish_name='Том Ям' AND parsed.quantity=4;
    SELECT * INTO parsed FROM core.parse_dish('Чизбургер × 2');
    ASSERT parsed.dish_name='Чизбургер' AND parsed.quantity=2;
    SELECT * INTO parsed FROM core.parse_dish('Чизбургер');
    ASSERT parsed.dish_name='Чизбургер' AND parsed.quantity IS NULL;
    SELECT * INTO parsed FROM core.parse_restaurant('Москва; Wok City');
    ASSERT parsed.restaurant_name='Wok City' AND parsed.city='Москва';

    SELECT * INTO result FROM core.idempotency_comparison ORDER BY run_id DESC LIMIT 1;
    ASSERT result.previous_run_id IS NOT NULL;
    ASSERT result.same_raw AND result.same_business_rows AND result.same_dispositions
           AND result.same_marts AND result.all_metrics_equal,
           'Two consecutive runs differ';
    ASSERT (SELECT bool_and(passed) FROM core.quality_results);
END $$;

SELECT run_id,started_at,finished_at,metrics FROM core.pipeline_runs ORDER BY run_id DESC LIMIT 2;
SELECT previous_run_id,run_id,same_raw,same_business_rows,same_dispositions,same_marts,all_metrics_equal
FROM core.idempotency_comparison ORDER BY run_id DESC LIMIT 1;
SELECT * FROM core.quality_results ORDER BY check_name;
SELECT * FROM core.quarantine_reasons ORDER BY affected_raw_rows DESC;
