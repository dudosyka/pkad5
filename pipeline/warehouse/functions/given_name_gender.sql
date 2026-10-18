CREATE OR REPLACE FUNCTION core.given_name_gender(value text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE count(*)
        WHEN 0 THEN 'unknown'
        WHEN 1 THEN min(gender)
        ELSE 'ambiguous'
    END
    FROM core.given_names
    WHERE given_name=core.norm_text(value)
$$;
