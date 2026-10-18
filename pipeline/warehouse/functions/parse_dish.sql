CREATE OR REPLACE FUNCTION core.parse_dish(value text)
RETURNS TABLE(source_dish_id text, dish_name text, quantity integer)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text:=btrim(value); m text[];
BEGIN
    m:=regexp_match(s,'^(D[0-9]+);[ ]*(.+);[ ]*[xх×]([0-9]{1,9})$','i');
    IF m IS NOT NULL THEN
        source_dish_id:=upper(m[1]); dish_name:=btrim(m[2]); quantity:=m[3]::int;
    ELSE
        m:=regexp_match(s,'^блюдо=(.+);[ ]*кол-во=([0-9]{1,9})$','i');
        IF m IS NOT NULL THEN dish_name:=btrim(m[1]); quantity:=m[2]::int;
        ELSE
            m:=regexp_match(s,'^(.+)[ ]+[×xх][ ]*([0-9]{1,9})$','i');
            IF m IS NOT NULL THEN dish_name:=btrim(m[1]); quantity:=m[2]::int;
            ELSE
                m:=regexp_match(s,'^([0-9]{1,9})[ ]+шт\.[ ]+(.+)$','i');
                IF m IS NOT NULL THEN quantity:=m[1]::int; dish_name:=btrim(m[2]);
                ELSE dish_name:=s; END IF;
            END IF;
        END IF;
    END IF;
    IF quantity <= 0 THEN quantity:=NULL; END IF;
    RETURN NEXT;
END $$;
