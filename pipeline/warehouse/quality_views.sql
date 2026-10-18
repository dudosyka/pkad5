CREATE OR REPLACE VIEW core.raw_processing_summary AS
SELECT count(*) AS raw_rows,
       count(*) FILTER(WHERE disposition='loaded') AS loaded,
       count(*) FILTER(WHERE disposition='quarantined') AS quarantined,
       count(*) FILTER(WHERE disposition='duplicate') AS duplicates,
       count(*) FILTER(WHERE disposition='pending') AS unaccounted
FROM core.raw_records;
CREATE OR REPLACE VIEW core.quarantine_reasons AS
SELECT reason,count(*) AS affected_raw_rows,max(c.description) AS description
FROM core.quarantine q CROSS JOIN LATERAL unnest(q.reasons) reason
LEFT JOIN core.issue_catalog c ON c.issue_code=reason
GROUP BY reason;
CREATE OR REPLACE VIEW core.quarantine_queue AS
SELECT q.*,s.warnings FROM core.quarantine q JOIN core.stage_orders s USING(raw_id);
