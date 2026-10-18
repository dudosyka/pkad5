CREATE OR REPLACE FUNCTION core.run_pipeline() RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE id bigint;
BEGIN
    IF current_database()<>'practice_02' THEN RAISE EXCEPTION 'Wrong database'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext(current_database()),hashtext('core.run_pipeline'));
    LOCK TABLE public.raw_data_02 IN SHARE MODE;
    INSERT INTO core.pipeline_runs DEFAULT VALUES RETURNING run_id INTO id;
    PERFORM core.step_01_prepare();
    PERFORM core.step_02_profile_raw();
    PERFORM core.step_03_mark_duplicates();
    PERFORM core.step_04_parse_orders();
    PERFORM core.step_05_load_references();
    PERFORM core.step_06_resolve_entities();
    PERFORM core.step_07_load_quarantine();
    PERFORM core.step_08_load_orders();
    PERFORM core.step_09_build_marts();
    PERFORM core.step_10_quality_checks();
    UPDATE core.pipeline_runs SET finished_at=clock_timestamp(),metrics=core.current_metrics()
    WHERE run_id=id;
    RETURN id;
END $$;
