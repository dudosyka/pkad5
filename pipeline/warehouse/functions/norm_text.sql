CREATE OR REPLACE FUNCTION core.norm_text(value text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT lower(replace(btrim(regexp_replace(replace(value,chr(160),' '),'[[:space:]]+',' ','g')),'ё','е'))
$$;
