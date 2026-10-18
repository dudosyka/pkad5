CREATE OR REPLACE FUNCTION core.is_missing(value text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT coalesce(core.norm_text(value) IN ('','null','-','не указан','не указано','неизвестно','нет','см. карточку'),true)
$$;
