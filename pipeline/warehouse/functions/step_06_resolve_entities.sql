CREATE OR REPLACE FUNCTION core.step_06_resolve_entities() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE core.stage_orders s SET
        customer_id=core.resolve_person('customer',s.customer_info),
        courier_id=CASE WHEN s.fulfillment_type='delivery'
                            AND core.norm_text(s.courier_info)<>'не назначен'
                        THEN core.resolve_person('courier',s.courier_info) END;

    UPDATE core.stage_orders s SET restaurant_id=r.restaurant_id
    FROM core.restaurants r
    WHERE core.norm_text(s.restaurant_name)=core.norm_text(r.restaurant_name)
      AND (s.restaurant_source_id IS NULL OR s.restaurant_source_id=r.restaurant_id)
      AND (s.restaurant_city IS NULL OR core.norm_text(s.restaurant_city)=core.norm_text(r.city));
    UPDATE core.stage_orders s SET dish_id=d.dish_id
    FROM core.dishes d
    WHERE core.norm_text(s.dish_name)=core.norm_text(d.dish_name)
      AND (s.dish_source_id IS NULL OR s.dish_source_id=d.dish_id);

    UPDATE core.stage_orders s SET errors=s.errors || array_remove(ARRAY[
        CASE WHEN s.customer_id IS NULL THEN 'customer_unresolved_or_conflicting' END,
        CASE WHEN s.restaurant_id IS NULL THEN 'restaurant_unrecognized_or_conflicting' END,
        CASE WHEN s.dish_id IS NULL THEN 'dish_unrecognized_or_conflicting' END,
        CASE WHEN s.fulfillment_type='delivery'
                   AND core.norm_text(s.courier_info)<>'не назначен'
                   AND s.courier_id IS NULL THEN 'courier_unresolved_or_conflicting' END
    ]::text[],NULL);

    WITH genders AS MATERIALIZED (
        SELECT raw_id,
               core.person_name_gender('customer',customer_info,customer_id) AS customer_gender,
               CASE WHEN fulfillment_type='delivery' AND core.norm_text(courier_info)<>'не назначен'
                    THEN core.person_name_gender('courier',courier_info,courier_id) END AS courier_gender
        FROM core.stage_orders
    )
    UPDATE core.stage_orders s SET errors=s.errors || array_remove(ARRAY[
        CASE WHEN g.customer_gender='ambiguous' THEN 'customer_name_gender_ambiguous'
             WHEN g.customer_gender='unknown' THEN 'customer_name_gender_unknown' END,
        CASE WHEN g.courier_gender='ambiguous' THEN 'courier_name_gender_ambiguous'
             WHEN g.courier_gender='unknown' THEN 'courier_name_gender_unknown' END
    ]::text[],NULL)
    FROM genders g WHERE g.raw_id=s.raw_id;

    WITH prices AS MATERIALIZED (
        SELECT dish_id,min(total_amount/quantity) AS unit_price
        FROM core.stage_orders
        WHERE cardinality(errors)=0 AND quantity>0 AND total_amount>0
          AND NOT (warnings && ARRAY['dish_quantity_inferred','amount_inferred'])
        GROUP BY dish_id
        HAVING min(total_amount/quantity)=max(total_amount/quantity)
    ), inferred AS (
        SELECT s.raw_id,
               CASE WHEN s.quantity IS NULL
                          AND core.norm_text(r.effective_record->>'dish_details')=core.norm_text(s.dish_name)
                          AND s.total_amount/p.unit_price BETWEEN 1 AND 2147483647
                          AND mod(s.total_amount,p.unit_price)=0
                    THEN (s.total_amount/p.unit_price)::integer END AS quantity,
               CASE WHEN s.total_amount IS NULL AND s.quantity>0
                          AND NOT ('dish_quantity_inferred'=ANY(s.warnings))
                          AND s.quantity*p.unit_price BETWEEN 0.01 AND 999999999999.99
                          AND s.quantity*p.unit_price=round(s.quantity*p.unit_price,2)
                    THEN s.quantity*p.unit_price END AS total_amount
        FROM core.stage_orders s
        JOIN prices p ON p.dish_id=s.dish_id
        JOIN core.effective_raw_records r ON r.raw_id=s.raw_id
        WHERE s.quantity IS NULL OR s.total_amount IS NULL
    )
    UPDATE core.stage_orders s SET
        quantity=coalesce(i.quantity,s.quantity),
        total_amount=coalesce(i.total_amount,s.total_amount),
        errors=CASE WHEN i.quantity IS NOT NULL
                    THEN array_remove(s.errors,'dish_quantity_missing_or_invalid')
                    ELSE array_remove(array_remove(s.errors,'amount_missing'),'amount_invalid_or_approximate') END,
        warnings=s.warnings || CASE WHEN i.quantity IS NOT NULL
                                   THEN ARRAY['dish_quantity_inferred'] ELSE ARRAY['amount_inferred'] END
    FROM inferred i
    WHERE s.raw_id=i.raw_id AND (i.quantity IS NOT NULL OR i.total_amount IS NOT NULL);
END $$;
