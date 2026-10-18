CREATE TABLE IF NOT EXISTS core.quarantine_corrections (
    correction_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_record jsonb NOT NULL,
    corrected_record jsonb NOT NULL,
    corrected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    administrator text NOT NULL,
    comment text NOT NULL DEFAULT '',
    run_id bigint REFERENCES core.pipeline_runs(run_id),
    CHECK (jsonb_typeof(source_record)='object' AND jsonb_typeof(corrected_record)='object')
);
CREATE INDEX IF NOT EXISTS quarantine_corrections_source_idx
ON core.quarantine_corrections (md5(source_record::text), correction_id DESC);

CREATE OR REPLACE VIEW core.effective_raw_records AS
SELECT r.*,coalesce(c.corrected_record,r.source_record) AS effective_record,
       c.correction_id
FROM core.raw_records r
LEFT JOIN LATERAL (
    SELECT corrected_record,correction_id FROM core.quarantine_corrections c
    WHERE md5(c.source_record::text)=md5(r.source_record::text)
      AND c.source_record=r.source_record
    ORDER BY correction_id DESC LIMIT 1
) c ON true;
