CREATE OR REPLACE FUNCTION core.step_03_mark_duplicates() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    WITH copies AS (
        SELECT raw_id,min(raw_id) OVER (PARTITION BY source_record) AS first_id
        FROM core.raw_records
    )
    UPDATE core.raw_records r SET duplicate_of=c.first_id,disposition='duplicate'
    FROM copies c WHERE r.raw_id=c.raw_id AND c.first_id<>c.raw_id;
END $$;
