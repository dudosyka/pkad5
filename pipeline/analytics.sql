SELECT * FROM core.analytics_restaurants ORDER BY revenue DESC;

SELECT * FROM core.analytics_dishes ORDER BY units_count DESC;

SELECT * FROM core.analytics_monthly ORDER BY order_month;

SELECT * FROM core.analytics_fulfillment
ORDER BY fulfillment_type,orders_count DESC;

SELECT *,raw_rows=loaded+quarantined+duplicates+unaccounted AS reconciles
FROM core.raw_processing_summary;

SELECT * FROM core.quarantine_reasons ORDER BY affected_raw_rows DESC;
SELECT * FROM core.quarantine_queue ORDER BY raw_id LIMIT 10;

SELECT previous_run_id,run_id,same_raw,same_business_rows,same_dispositions,
       same_marts,all_metrics_equal
FROM core.idempotency_comparison ORDER BY run_id;
SELECT * FROM core.quality_results ORDER BY check_name;

SELECT * FROM core.raw_column_profile ORDER BY column_name;
SELECT * FROM core.raw_format_profile
WHERE column_name IN ('order_id','order_datetime','total_amount')
ORDER BY column_name,occurrences DESC;
SELECT * FROM core.cleaning_rules ORDER BY rule_code;
