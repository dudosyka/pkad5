CREATE OR REPLACE FUNCTION core.parse_person(kind text, value text)
RETURNS TABLE(source_person_id text, family_name text, given_name text, patronymic text, phone text)
LANGUAGE plpgsql STABLE AS $$
DECLARE raw_name text; words text[]; first_is_name boolean; second_is_name boolean;
BEGIN
    IF kind NOT IN ('customer','courier') OR core.is_missing(value)
       OR (kind='customer' AND cardinality(string_to_array(value,'/'))>2)
       OR (kind='courier' AND strpos(value,'/')>0) THEN RETURN NEXT; RETURN; END IF;
    raw_name:=split_part(value,'/',1);
    IF kind='customer' THEN
        phone:=core.clean_phone(split_part(value,'/',2));
        IF NOT core.is_missing(split_part(value,'/',2)) AND phone IS NULL THEN RETURN NEXT; RETURN; END IF;
    END IF;
    IF regexp_count(upper(raw_name),'\m[UC][0-9]{3,}\M')>1 THEN phone:=NULL; RETURN NEXT; RETURN; END IF;
    source_person_id:=substring(upper(raw_name) FROM '\m([UC][0-9]{3,})\M');
    IF source_person_id IS NOT NULL AND left(source_person_id,1)<>(CASE WHEN kind='customer' THEN 'U' ELSE 'C' END)
    THEN source_person_id:=NULL; phone:=NULL; RETURN NEXT; RETURN; END IF;
    raw_name:=regexp_replace(raw_name,'\m[UC][0-9]{3,}\M','','gi');
    IF core.is_missing(raw_name) THEN RETURN NEXT; RETURN; END IF;
    words:=regexp_split_to_array(btrim(regexp_replace(replace(core.norm_text(raw_name),'0','о'),
                                                     '[^а-яёa-z0-9-]+',' ','g')),' +');
    IF cardinality(words) NOT IN (2,3) THEN RETURN NEXT; RETURN; END IF;
    first_is_name:=core.given_name_gender(words[1])<>'unknown';
    second_is_name:=core.given_name_gender(words[2])<>'unknown';
    IF first_is_name=second_is_name THEN RETURN NEXT; RETURN; END IF;
    IF second_is_name THEN
        family_name:=words[1]; given_name:=words[2]; patronymic:=words[3];
    ELSE
        given_name:=words[1];
        IF cardinality(words)=3 AND words[2] ~ '(ич|на|оглы|кызы)$' THEN
            patronymic:=words[2]; family_name:=words[3];
        ELSE family_name:=words[2]; patronymic:=words[3]; END IF;
    END IF;
    IF length(family_name)<2 OR length(given_name)<2 OR length(patronymic)<2
       OR family_name !~ '^[а-яёa-z]+(-[а-яёa-z]+)*$'
       OR (patronymic IS NOT NULL AND patronymic !~ '^[а-яёa-z]+(-[а-яёa-z]+)*$') THEN
        family_name:=NULL; given_name:=NULL; patronymic:=NULL;
    ELSE
        given_name:=initcap(given_name); patronymic:=initcap(patronymic);
        family_name:=core.clean_family_name(family_name,given_name);
    END IF;
    RETURN NEXT;
END $$;
