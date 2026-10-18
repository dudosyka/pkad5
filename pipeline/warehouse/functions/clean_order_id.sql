CREATE OR REPLACE FUNCTION core.clean_order_id(value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE m text[];
BEGIN
    m := regexp_match(upper(btrim(value)),'^(?:№[ ]*)?FD[- ]+([0-9]{1,12})$');
    IF m IS NULL THEN RETURN NULL; END IF;
    RETURN 'FD-' || (m[1]::bigint)::text;
END $$;
