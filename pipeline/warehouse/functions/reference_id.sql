CREATE OR REPLACE FUNCTION core.reference_id(prefix text, identity_key text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
    SELECT prefix || lpad(id,greatest(3,length(id)),'0')
    FROM (SELECT (('x' || substr(md5(identity_key),1,15))::bit(60)::bigint)::text AS id) n
$$;
