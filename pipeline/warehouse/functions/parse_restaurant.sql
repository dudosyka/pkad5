CREATE OR REPLACE FUNCTION core.parse_restaurant(value text)
RETURNS TABLE(source_restaurant_id text, restaurant_name text, city text)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text:=btrim(value); m text[];
BEGIN
    m:=regexp_match(s,'^(R[0-9]+)[ ]*/[ ]*(.+)[ ]*/[ ]*([^/]+)$','i');
    IF m IS NOT NULL THEN source_restaurant_id:=upper(m[1]); restaurant_name:=btrim(m[2]); city:=btrim(m[3]);
    ELSE
        m:=regexp_match(s,'^(.+),[ ]*г\.[ ]*(.+)$','i');
        IF m IS NOT NULL THEN restaurant_name:=btrim(m[1]); city:=btrim(m[2]);
        ELSE
            m:=regexp_match(s,'^([^;]+);[ ]*(.+)$');
            IF m IS NOT NULL THEN city:=btrim(m[1]); restaurant_name:=btrim(m[2]);
            ELSE
                m:=regexp_match(s,'^(.+)[ ]+\((R[0-9]+)\)$','i');
                IF m IS NOT NULL THEN restaurant_name:=btrim(m[1]); source_restaurant_id:=upper(m[2]);
                ELSE restaurant_name:=s; END IF;
            END IF;
        END IF;
    END IF;
    RETURN NEXT;
END $$;
