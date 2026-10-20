CREATE OR REPLACE FUNCTION core.person_name_gender(kind text, value text, resolved_person_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE given text; genders text[];
BEGIN
    IF resolved_person_id IS NOT NULL THEN
        SELECT p.given_name INTO given FROM core.person_lookup p
        WHERE p.entity_kind=kind AND p.person_id=resolved_person_id;
        RETURN core.given_name_gender(given);
    END IF;

    SELECT array_agg(DISTINCT n.gender) INTO genders
    FROM regexp_split_to_table(
        regexp_replace(core.norm_text(split_part(value,'/',1)),
                       '\m[uc][0-9]{3,}\M','','g'),
        '[^а-я-]+'
    ) AS token(name)
    JOIN core.given_names n ON n.given_name=token.name;
    RETURN CASE coalesce(cardinality(genders),0)
        WHEN 0 THEN 'unknown'
        WHEN 1 THEN genders[1]
        ELSE 'ambiguous'
    END;
END $$;
