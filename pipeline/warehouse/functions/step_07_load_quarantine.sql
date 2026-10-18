CREATE OR REPLACE FUNCTION core.step_07_load_quarantine() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.quarantine(raw_id,source_locator,source_record,reasons)
    SELECT r.raw_id,r.source_locator,r.source_record,s.errors
    FROM core.stage_orders s JOIN core.raw_records r USING(raw_id)
    WHERE cardinality(s.errors)>0;

    UPDATE core.raw_records r SET disposition='quarantined'
    FROM core.quarantine q WHERE q.raw_id=r.raw_id;
END $$;
