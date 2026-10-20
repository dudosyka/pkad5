CREATE OR REPLACE FUNCTION core.step_05_load_references() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    CREATE TEMP TABLE pipeline_people ON COMMIT DROP AS
    SELECT DISTINCT v.kind,p.*,p.source_person_id AS person_id,false AS conflicting
    FROM core.stage_orders s
    CROSS JOIN LATERAL (VALUES ('customer',s.customer_info),('courier',
        CASE WHEN s.fulfillment_type='delivery' AND core.norm_text(s.courier_info)<>'не назначен'
             THEN s.courier_info END)) v(kind,info)
    CROSS JOIN LATERAL core.parse_person(v.kind,v.info) p
    WHERE p.source_person_id IS NOT NULL OR p.family_name IS NOT NULL OR p.phone IS NOT NULL;

    WITH matches AS (
        SELECT a.ctid AS row_id,min(b.source_person_id) AS person_id,
               count(DISTINCT b.source_person_id) AS candidates
        FROM pg_temp.pipeline_people a JOIN pg_temp.pipeline_people b
          ON a.kind=b.kind AND b.source_person_id IS NOT NULL
         AND ((a.phone IS NOT NULL AND a.phone=b.phone)
              OR (a.family_name=b.family_name AND a.given_name=b.given_name
                  AND (a.patronymic IS NULL OR b.patronymic IS NULL OR a.patronymic=b.patronymic)
                  AND (a.phone IS NULL OR b.phone IS NULL OR a.phone=b.phone)))
        WHERE a.source_person_id IS NULL GROUP BY a.ctid
    )
    UPDATE pg_temp.pipeline_people p SET
        person_id=CASE WHEN m.candidates=1 THEN m.person_id END,
        conflicting=m.candidates>1
    FROM matches m WHERE p.ctid=m.row_id;

    UPDATE pg_temp.pipeline_people SET person_id=core.reference_id('U','phone:' || phone)
    WHERE kind='customer' AND person_id IS NULL AND phone IS NOT NULL AND NOT conflicting;

    WITH matches AS (
        SELECT a.ctid AS row_id,min(b.person_id) AS person_id,count(DISTINCT b.person_id) AS candidates
        FROM pg_temp.pipeline_people a JOIN pg_temp.pipeline_people b
          ON a.kind=b.kind AND a.family_name=b.family_name AND a.given_name=b.given_name
         AND (a.patronymic IS NULL OR b.patronymic IS NULL OR a.patronymic=b.patronymic)
        WHERE a.person_id IS NULL AND NOT a.conflicting AND b.person_id IS NOT NULL
        GROUP BY a.ctid
    )
    UPDATE pg_temp.pipeline_people p SET
        person_id=CASE WHEN m.candidates=1 THEN m.person_id END,
        conflicting=m.candidates>1
    FROM matches m WHERE p.ctid=m.row_id;

    WITH names AS (
        SELECT kind,family_name,given_name,min(patronymic) AS patronymic,
               count(DISTINCT patronymic) AS variants
        FROM pg_temp.pipeline_people WHERE NOT conflicting
        GROUP BY kind,family_name,given_name
    )
    UPDATE pg_temp.pipeline_people p SET patronymic=n.patronymic,conflicting=n.variants>1
    FROM names n WHERE p.person_id IS NULL AND p.patronymic IS NULL AND NOT p.conflicting
      AND p.kind=n.kind AND p.family_name=n.family_name AND p.given_name=n.given_name;

    UPDATE pg_temp.pipeline_people SET person_id=core.reference_id(
        CASE WHEN kind='customer' THEN 'U' ELSE 'C' END,
        'name:' || family_name || ':' || given_name || ':' || coalesce(patronymic,''))
    WHERE person_id IS NULL AND family_name IS NOT NULL AND NOT conflicting;

    CREATE TEMP TABLE pipeline_person_references ON COMMIT DROP AS
    SELECT kind,person_id,min(family_name) AS family_name,min(given_name) AS given_name,
           min(patronymic) AS patronymic,min(phone) AS phone
    FROM pg_temp.pipeline_people WHERE person_id IS NOT NULL AND NOT conflicting
    GROUP BY kind,person_id
    HAVING count(DISTINCT (family_name,given_name)) FILTER (WHERE family_name IS NOT NULL)=1
       AND count(DISTINCT patronymic)<=1 AND count(DISTINCT phone)<=1;

    DELETE FROM pg_temp.pipeline_person_references p USING (
        SELECT phone FROM pg_temp.pipeline_person_references
        WHERE kind='customer' AND phone IS NOT NULL GROUP BY phone HAVING count(*)>1
    ) conflicts WHERE p.kind='customer' AND p.phone=conflicts.phone;

    INSERT INTO core.customers(customer_id,family_name,given_name,patronymic,phone)
    SELECT person_id,family_name,given_name,patronymic,phone
    FROM pg_temp.pipeline_person_references WHERE kind='customer';
    INSERT INTO core.couriers(courier_id,family_name,given_name,patronymic)
    SELECT person_id,family_name,given_name,patronymic
    FROM pg_temp.pipeline_person_references WHERE kind='courier';

    WITH source AS MATERIALIZED (
        SELECT DISTINCT restaurant_source_id,restaurant_name,restaurant_city FROM core.stage_orders
    ), candidates AS (
        SELECT s.*,coalesce(restaurant_source_id,
                   (SELECT min(t.restaurant_source_id) FROM source t
                    WHERE core.norm_text(t.restaurant_name)=core.norm_text(s.restaurant_name)
                      AND (s.restaurant_city IS NULL OR t.restaurant_city IS NULL
                           OR core.norm_text(t.restaurant_city)=core.norm_text(s.restaurant_city))
                    HAVING count(DISTINCT t.restaurant_source_id)=1),
                   core.reference_id('R',core.norm_text(restaurant_name) || ':' || coalesce(
                       core.norm_text(restaurant_city),
                       (SELECT min(core.norm_text(t.restaurant_city)) FROM source t
                        WHERE core.norm_text(t.restaurant_name)=core.norm_text(s.restaurant_name)
                        HAVING count(DISTINCT core.norm_text(t.restaurant_city))=1)))) AS reference_id
        FROM source s WHERE NOT core.is_missing(restaurant_name)
    ), grouped AS (
        SELECT reference_id,min(restaurant_name) AS restaurant_name,min(restaurant_city) AS city
        FROM candidates WHERE reference_id IS NOT NULL GROUP BY reference_id
        HAVING count(DISTINCT core.norm_text(restaurant_name))=1
           AND count(DISTINCT core.norm_text(restaurant_city))=1
    )
    INSERT INTO core.restaurants(restaurant_id,restaurant_name,city)
    SELECT reference_id,restaurant_name,city FROM grouped g
    WHERE NOT EXISTS (SELECT 1 FROM grouped other WHERE other.reference_id<>g.reference_id
        AND core.norm_text(other.restaurant_name)=core.norm_text(g.restaurant_name)
        AND core.norm_text(other.city)=core.norm_text(g.city));

    WITH source AS MATERIALIZED (
        SELECT DISTINCT dish_source_id,dish_name FROM core.stage_orders WHERE quantity>0
    ), candidates AS (
        SELECT dish_name,coalesce(dish_source_id,
                   (SELECT min(t.dish_source_id) FROM source t
                    WHERE core.norm_text(t.dish_name)=core.norm_text(s.dish_name)
                    HAVING count(DISTINCT t.dish_source_id)=1),
                   core.reference_id('D',core.norm_text(dish_name))) AS reference_id
        FROM source s WHERE NOT core.is_missing(dish_name)
    ), grouped AS (
        SELECT reference_id,min(dish_name) AS dish_name
        FROM candidates GROUP BY reference_id HAVING count(DISTINCT core.norm_text(dish_name))=1
    )
    INSERT INTO core.dishes(dish_id,dish_name)
    SELECT reference_id,dish_name FROM grouped g
    WHERE NOT EXISTS (SELECT 1 FROM grouped other WHERE other.reference_id<>g.reference_id
        AND core.norm_text(other.dish_name)=core.norm_text(g.dish_name));

    INSERT INTO core.person_aliases(entity_kind,alias_key,person_id)
    SELECT DISTINCT p.entity_kind,core.name_key(a.alias),p.person_id
    FROM core.person_lookup p
    CROSS JOIN LATERAL (VALUES
        (p.family_name),
        (CASE WHEN core.given_name_gender(p.given_name)='female'
              THEN regexp_replace(p.family_name,'(ов|ев|ёв|ин|ын)а(-|$)','\1\2','gi')
              ELSE p.family_name END)
    ) f(family_name)
    CROSS JOIN LATERAL (VALUES
        (f.family_name || ' ' || p.given_name),
        (p.given_name || ' ' || f.family_name),
        (f.family_name || ' ' || p.given_name || coalesce(' ' || p.patronymic,'')),
        (p.given_name || coalesce(' ' || p.patronymic,'') || ' ' || f.family_name),
        (p.given_name || ' ' || f.family_name || coalesce(' ' || p.patronymic,'')),
        (f.family_name || ' ' || left(p.given_name,1) || left(p.patronymic,1)),
        (left(p.given_name,1) || left(p.patronymic,1) || ' ' || f.family_name),
        (f.family_name || ' ' || left(p.given_name,1)),
        (left(p.given_name,1) || ' ' || f.family_name),
        (p.given_name || ' ' || left(f.family_name,1))
    ) a(alias)
    WHERE a.alias IS NOT NULL;

    UPDATE core.customers
    SET family_name=core.clean_family_name(family_name,given_name);
    UPDATE core.couriers
    SET family_name=core.clean_family_name(family_name,given_name);
    DROP TABLE pg_temp.pipeline_person_references,pg_temp.pipeline_people;
END $$;
