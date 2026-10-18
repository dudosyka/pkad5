CREATE OR REPLACE FUNCTION core.step_02_profile_raw() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.raw_column_profile
    SELECT f.key,count(*),count(*) FILTER(WHERE f.value IS NULL),
           count(*) FILTER(WHERE btrim(f.value)=''),
           count(*) FILTER(WHERE f.value IS NOT NULL AND btrim(f.value)<>'' AND core.is_missing(f.value)),
           count(*) FILTER(WHERE f.value<>btrim(f.value)),
           count(DISTINCT f.value),min(length(f.value)),max(length(f.value))
    FROM core.raw_records r
    CROSS JOIN LATERAL jsonb_each_text(r.source_record) f(key,value)
    GROUP BY f.key;
    INSERT INTO core.raw_format_profile
    SELECT f.key,coalesce(regexp_replace(f.value,'[0-9]','9','g'),'<SQL NULL>'),count(*)
    FROM core.raw_records r
    CROSS JOIN LATERAL jsonb_each_text(r.source_record) f(key,value)
    GROUP BY 1,2;
END $$;
