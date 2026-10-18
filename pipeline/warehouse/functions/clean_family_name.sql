CREATE OR REPLACE FUNCTION core.clean_family_name(value text, given_name text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT initcap(CASE WHEN core.given_name_gender(given_name)='female'
        THEN regexp_replace(btrim(value),'(ов|ев|ёв|ин|ын)(-|$)','\1а\2','gi')
        ELSE btrim(value)
    END)
$$;
