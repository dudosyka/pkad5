\set ON_ERROR_STOP on

BEGIN;
\ir warehouse/schema.sql
\ir warehouse/corrections.sql
\ir warehouse/functions/norm_text.sql
\ir warehouse/given_names.sql
\ir warehouse/functions/given_name_gender.sql
\ir warehouse/functions/clean_family_name.sql
\ir warehouse/functions/name_key.sql
\ir warehouse/functions/is_missing.sql
\ir warehouse/functions/clean_phone.sql
\ir warehouse/functions/reference_id.sql
\ir warehouse/functions/parse_person.sql
\ir warehouse/functions/clean_order_id.sql
\ir warehouse/functions/clean_datetime.sql
\ir warehouse/functions/clean_amount.sql
\ir warehouse/functions/parse_dish.sql
\ir warehouse/functions/parse_restaurant.sql
\ir warehouse/person_lookup.sql
\ir warehouse/functions/person_name_gender.sql
\ir warehouse/functions/resolve_person.sql
\ir warehouse/marts.sql
\ir warehouse/quality_views.sql
\ir warehouse/functions/step_01_prepare.sql
\ir warehouse/functions/step_02_profile_raw.sql
\ir warehouse/functions/step_03_mark_duplicates.sql
\ir warehouse/functions/step_04_parse_orders.sql
\ir warehouse/functions/step_05_load_references.sql
\ir warehouse/functions/step_06_resolve_entities.sql
\ir warehouse/functions/step_07_load_quarantine.sql
\ir warehouse/functions/step_08_load_orders.sql
\ir warehouse/functions/step_09_build_marts.sql
\ir warehouse/functions/step_10_quality_checks.sql
\ir warehouse/functions/current_metrics.sql
\ir warehouse/functions/run_pipeline.sql
\ir warehouse/reporting_views.sql
DROP FUNCTION IF EXISTS core.step_02_load_references();
DROP FUNCTION IF EXISTS core.step_03_load_core();
DROP FUNCTION IF EXISTS core.step_04_build_marts();
DROP FUNCTION IF EXISTS core.step_05_quality_checks();
COMMENT ON FUNCTION core.run_pipeline() IS NULL;
COMMIT;
