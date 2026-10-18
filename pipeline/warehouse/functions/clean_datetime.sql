CREATE OR REPLACE FUNCTION core.clean_datetime(value text) RETURNS timestamp without time zone
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE s text; m text[]; y int; mon int; d int; h int; mi int; sec int := 0;
BEGIN
    IF core.is_missing(value) THEN RETURN NULL; END IF;
    s := btrim(regexp_replace(replace(value,' в ',' '),'[[:space:]]+',' ','g'));
    m := regexp_match(replace(s,'/','-'),'^([0-9]{4})-([0-9]{2})-([0-9]{2})[ T]([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?$');
    IF m IS NOT NULL THEN
        y:=m[1]::int; mon:=m[2]::int; d:=m[3]::int;
        h:=m[4]::int; mi:=m[5]::int; sec:=coalesce(m[6]::int,0);
    ELSE
        m:=regexp_match(s,'^([0-9]{2})[./]([0-9]{2})[./]([0-9]{4}|[0-9]{2}) ([0-9]{2}):([0-9]{2})(?: (AM|PM))?$','i');
        IF m IS NOT NULL THEN
            d:=m[1]::int; mon:=m[2]::int; y:=m[3]::int;
            IF length(m[3])=2 THEN y:=2000+y; END IF;
            h:=m[4]::int; mi:=m[5]::int;
            IF m[6] IS NOT NULL THEN
                IF h NOT BETWEEN 1 AND 12 THEN RETURN NULL; END IF;
                h:=(h % 12) + CASE WHEN upper(m[6])='PM' THEN 12 ELSE 0 END;
            END IF;
        ELSE
            m:=regexp_match(s,'^([0-9]{2}) ([a-z]{3}) ([0-9]{4}) ([0-9]{2}):([0-9]{2})$','i');
            IF m IS NOT NULL THEN
                d:=m[1]::int; mon:=array_position(ARRAY['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'],lower(m[2]));
                y:=m[3]::int; h:=m[4]::int; mi:=m[5]::int;
                IF mon IS NULL THEN RETURN NULL; END IF;
            ELSE
                m:=regexp_match(s,'^([0-9]{4})([0-9]{2})([0-9]{2}) ([0-9]{2})([0-9]{2})$');
                IF m IS NULL THEN RETURN NULL; END IF;
                y:=m[1]::int; mon:=m[2]::int; d:=m[3]::int; h:=m[4]::int; mi:=m[5]::int;
            END IF;
        END IF;
    END IF;
    IF h NOT BETWEEN 0 AND 23 OR mi NOT BETWEEN 0 AND 59 OR sec NOT BETWEEN 0 AND 59 THEN RETURN NULL; END IF;
    RETURN make_timestamp(y,mon,d,h,mi,sec);
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format OR numeric_value_out_of_range THEN
    RETURN NULL;
END $$;
