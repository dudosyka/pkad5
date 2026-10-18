CREATE OR REPLACE FUNCTION core.clean_phone(value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text; digits text;
BEGIN
    IF core.is_missing(value) THEN RETURN NULL; END IF;
    s := regexp_replace(core.norm_text(value),'^тел\.[ ]*','','i');
    s := regexp_replace(s,'[ ]+доб\.[ ]*[0-9]+$','','i');
    IF s !~ '^\+?[0-9() -]+$' THEN RETURN NULL; END IF;
    digits := regexp_replace(s,'[^0-9]','','g');
    IF digits ~ '^9[0-9]{9}$' THEN digits := '7' || digits;
    ELSIF digits ~ '^8[0-9]{10}$' THEN digits := '7' || substr(digits,2);
    END IF;
    IF digits !~ '^7[0-9]{10}$' THEN RETURN NULL; END IF;
    RETURN '+' || digits;
END $$;
