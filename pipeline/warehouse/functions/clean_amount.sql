CREATE OR REPLACE FUNCTION core.clean_amount(value text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text; m text[]; result numeric;
BEGIN
    IF core.is_missing(value) THEN RETURN NULL; END IF;
    s:=core.norm_text(value);
    m:=regexp_match(s,'^([0-9]+) рублей ([0-9]{2}) коп\.$');
    IF m IS NOT NULL THEN
        result:=m[1]::numeric + m[2]::numeric/100;
    ELSE
        s:=btrim(regexp_replace(s,'^(rub|₽)[ ]*','','i'));
        s:=btrim(regexp_replace(s,'[ ]*(руб\.|рублей|р|₽)$','','i'));
        IF s ~ '^[0-9]+([.,][0-9]{1,2})?$' THEN
            result:=replace(s,',','.')::numeric;
        ELSIF s ~ '^[0-9]{1,3}(,[0-9]{3})+\.[0-9]{1,2}$' THEN
            result:=replace(s,',','')::numeric;
        ELSIF s ~ '^[0-9]{1,3}(\.[0-9]{3})+,[0-9]{1,2}$' THEN
            result:=replace(replace(s,'.',''),',','.')::numeric;
        ELSIF s ~ '^[0-9]{1,3}( [0-9]{3})+([.,][0-9]{1,2})?$' THEN
            result:=replace(replace(s,' ',''),',','.')::numeric;
        ELSE RETURN NULL;
        END IF;
    END IF;
    IF result <= 0 OR result > 999999999999.99 THEN RETURN NULL; END IF;
    RETURN result;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN NULL;
END $$;
