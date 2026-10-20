CREATE OR REPLACE FUNCTION core.resolve_person(kind text, value text) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE raw_name text; raw_phone text; code text; clean_name text; key text;
        candidate text; by_phone text; matches text[]; family text; given text;
BEGIN
    IF kind='customer' AND cardinality(string_to_array(value,'/'))>2 THEN RETURN NULL; END IF;
    IF kind='courier' AND strpos(value,'/')>0 THEN RETURN NULL; END IF;
    raw_name:=split_part(value,'/',1);
    IF kind='customer' AND strpos(value,'/')>0 THEN raw_phone:=split_part(value,'/',2); END IF;
    IF NOT core.is_missing(raw_phone) AND core.clean_phone(raw_phone) IS NULL THEN RETURN NULL; END IF;
    IF regexp_count(upper(raw_name),'\m[UC][0-9]{3,}\M')>1 THEN RETURN NULL; END IF;
    code:=substring(upper(raw_name) from '\m([UC][0-9]{3,})\M');
    clean_name:=regexp_replace(raw_name,'\m[UC][0-9]{3,}\M','','gi');
    key:=core.name_key(clean_name);
    IF code IS NOT NULL THEN
        SELECT p.person_id INTO candidate FROM core.person_lookup p
        WHERE p.entity_kind=kind AND p.person_id=code;
        IF candidate IS NULL THEN RETURN NULL; END IF;
    END IF;
    IF kind='customer' AND core.clean_phone(raw_phone) IS NOT NULL THEN
        SELECT p.person_id INTO by_phone FROM core.person_lookup p
        WHERE p.entity_kind=kind AND p.phone=core.clean_phone(raw_phone);
        IF by_phone IS NULL THEN RETURN NULL; END IF;
        IF candidate IS NOT NULL AND candidate<>by_phone THEN RETURN NULL; END IF;
        candidate:=by_phone;
    END IF;
    IF NOT core.is_missing(clean_name) AND key<>'' THEN
        SELECT array_agg(a.person_id ORDER BY a.person_id) INTO matches
        FROM core.person_aliases a WHERE a.entity_kind=kind AND a.alias_key=key;
        IF candidate IS NULL THEN
            IF cardinality(matches)<>1 OR matches IS NULL THEN RETURN NULL; END IF;
            candidate:=matches[1];
        ELSIF matches IS NOT NULL THEN
            IF NOT (candidate=ANY(matches)) THEN RETURN NULL; END IF;
        ELSE
            SELECT core.name_key(p.family_name),p.given_name INTO family,given FROM core.person_lookup p
            WHERE p.entity_kind=kind AND p.person_id=candidate;
            IF key<>family AND core.name_key(core.clean_family_name(clean_name,given))<>family THEN RETURN NULL; END IF;
        END IF;
    END IF;
    RETURN candidate;
END $$;
