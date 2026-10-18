CREATE OR REPLACE FUNCTION core.name_key(value text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT regexp_replace(replace(core.norm_text(value),'0','о'),'[^а-яa-z]','','g')
$$;
