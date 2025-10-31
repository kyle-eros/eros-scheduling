-- =============================================================================
-- PERFORMANCE ANALYZER VALIDATION TEST SUITE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Comprehensive testing of all TVFs and main procedure
-- Test Page: jadebri
-- Generated: 2025-10-31
-- =============================================================================

-- =============================================================================
-- SECTION 1: DEPLOYMENT VERIFICATION
-- =============================================================================

-- Test 1.1: Verify all 7 TVFs and 1 procedure are deployed
SELECT
  'DEPLOYMENT_CHECK' AS test_name,
  routine_name,
  routine_type,
  CASE routine_type
    WHEN 'TABLE_VALUED_FUNCTION' THEN 'TVF'
    WHEN 'PROCEDURE' THEN 'PROC'
    ELSE routine_type
  END AS type_short,
  routine_definition IS NOT NULL AS has_definition
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'classify_account_size',
  'analyze_behavioral_segments',
  'analyze_trigger_performance',
  'analyze_content_categories',
  'analyze_day_patterns',
  'analyze_time_windows',
  'calculate_saturation_score',
  'analyze_creator_performance'
)
ORDER BY routine_name;
-- EXPECTED: 8 rows (7 TVFs + 1 PROCEDURE)

-- Test 1.2: Check for required UDF dependencies
SELECT
  'DEPENDENCY_CHECK_UDFS' AS test_name,
  routine_name,
  routine_type
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('wilson_score_bounds', 'caption_key')
  AND routine_type = 'SCALAR_FUNCTION'
ORDER BY routine_name;
-- EXPECTED: 2 rows

-- Test 1.3: Check for required table dependencies
SELECT
  'DEPENDENCY_CHECK_TABLES' AS test_name,
  table_name,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), TIMESTAMP(CAST(TIMESTAMP_MILLIS(creation_time) AS TIMESTAMP)), DAY) AS days_since_creation
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN (
  'mass_messages',
  'caption_bank_enriched',
  'creator_content_inventory',
  'holiday_calendar',
  'etl_job_runs'
)
ORDER BY table_name;
-- EXPECTED: 5 rows

-- =============================================================================
-- SECTION 2: INDIVIDUAL TVF TESTING
-- =============================================================================

-- Test 2.1: classify_account_size
SELECT
  'TEST_TVF_1_classify_account_size' AS test_name,
  account_size_classification.size_tier,
  account_size_classification.avg_audience,
  ROUND(account_size_classification.total_revenue_period, 2) AS total_revenue,
  account_size_classification.daily_ppv_target_min,
  account_size_classification.daily_ppv_target_max,
  account_size_classification.daily_bump_target,
  account_size_classification.min_ppv_gap_minutes,
  ROUND(account_size_classification.saturation_tolerance, 2) AS saturation_tolerance
FROM `of-scheduler-proj.eros_scheduling_brain`.classify_account_size('jadebri', 90);
-- EXPECTED: 1 row with size_tier in (MICRO, SMALL, MEDIUM, LARGE, MEGA)

-- Test 2.2: analyze_behavioral_segments
SELECT
  'TEST_TVF_2_analyze_behavioral_segments' AS test_name,
  segment_label,
  ROUND(avg_rpr, 6) AS avg_rpr,
  ROUND(avg_conv, 4) AS avg_conv,
  ROUND(rpr_price_slope, 6) AS rpr_price_slope,
  ROUND(rpr_price_corr, 4) AS rpr_price_corr,
  ROUND(conv_price_elasticity_proxy, 4) AS conv_price_elasticity,
  ROUND(category_entropy, 4) AS category_entropy,
  sample_size
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_behavioral_segments('jadebri', 90);
-- EXPECTED: 1 row with segment_label in (EXPLORATORY, BUDGET, STANDARD, PREMIUM, LUXURY)

-- Test 2.3: analyze_trigger_performance (top 10)
SELECT
  'TEST_TVF_3_analyze_trigger_performance' AS test_name,
  psychological_trigger,
  msg_count,
  ROUND(avg_rpr, 4) AS avg_rpr,
  ROUND(avg_conv, 4) AS avg_conv,
  ROUND(rpr_lift_pct, 2) AS rpr_lift_pct,
  ROUND(conv_lift_pct, 2) AS conv_lift_pct,
  conv_stat_sig,
  rpr_stat_sig
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('jadebri', 90)
ORDER BY rpr_lift_pct DESC
LIMIT 10;
-- EXPECTED: Up to 10 rows, each with a psychological_trigger

-- Test 2.4: analyze_content_categories (top 10)
SELECT
  'TEST_TVF_4_analyze_content_categories' AS test_name,
  content_category,
  price_tier,
  msg_count,
  ROUND(avg_rpr, 4) AS avg_rpr,
  ROUND(avg_conv, 4) AS avg_conv,
  trend_direction,
  ROUND(trend_pct, 1) AS trend_pct,
  ROUND(price_sensitivity_corr, 4) AS price_sensitivity_corr,
  best_price_tier
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('jadebri', 90)
ORDER BY avg_rpr DESC
LIMIT 10;
-- EXPECTED: Up to 10 rows, trend_direction in (RISING, DECLINING, STABLE)

-- Test 2.5: analyze_day_patterns (all 7 days)
SELECT
  'TEST_TVF_5_analyze_day_patterns' AS test_name,
  day_of_week_la,
  CASE day_of_week_la
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS day_name,
  n AS msg_count,
  ROUND(avg_rpr, 4) AS avg_rpr,
  ROUND(avg_conv, 4) AS avg_conv,
  ROUND(t_rpr_approx, 2) AS t_statistic,
  rpr_stat_sig
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('jadebri', 90)
ORDER BY avg_rpr DESC;
-- EXPECTED: Up to 7 rows (one per day of week)

-- Test 2.6: analyze_time_windows (top 20)
SELECT
  'TEST_TVF_6_analyze_time_windows' AS test_name,
  day_type,
  hour_la,
  n AS msg_count,
  ROUND(avg_rpr, 4) AS avg_rpr,
  ROUND(avg_conv, 4) AS avg_conv,
  confidence
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('jadebri', 90)
ORDER BY avg_rpr DESC
LIMIT 20;
-- EXPECTED: Up to 20 rows, day_type in (Weekday, Weekend), confidence in (LOW_CONF, MED_CONF, HIGH_CONF)

-- Test 2.7: calculate_saturation_score
SELECT
  'TEST_TVF_7_calculate_saturation_score' AS test_name,
  ROUND(saturation_score, 4) AS saturation_score,
  risk_level,
  ROUND(unlock_rate_deviation, 4) AS unlock_rate_deviation,
  ROUND(emv_deviation, 4) AS emv_deviation,
  consecutive_underperform_days,
  recommended_action,
  ROUND(volume_adjustment_factor, 2) AS volume_adjustment_factor,
  ROUND(confidence_score, 2) AS confidence_score,
  exclusion_reason
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('jadebri', 'MEDIUM');
-- EXPECTED: 1 row, risk_level in (LOW, MEDIUM, HIGH), saturation_score between 0.0 and 1.0

-- =============================================================================
-- SECTION 3: MAIN PROCEDURE TESTING
-- =============================================================================

-- Test 3.1: Execute main procedure and capture output
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

-- Display raw JSON output
SELECT
  'TEST_MAIN_PROCEDURE_RAW_OUTPUT' AS test_name,
  performance_output,
  LENGTH(performance_output) AS output_size_bytes,
  ROUND(LENGTH(performance_output) / 1024.0, 2) AS output_size_kb;
-- EXPECTED: 1 row with valid JSON string, size > 1 KB

-- =============================================================================
-- SECTION 4: JSON PARSING AND VALIDATION
-- =============================================================================

-- Test 4.1: Extract and validate account classification
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_ACCOUNT_CLASSIFICATION' AS test_name,
  JSON_EXTRACT_SCALAR(performance_output, '$.creator_name') AS creator_name,
  JSON_EXTRACT_SCALAR(performance_output, '$.analysis_timestamp') AS analysis_timestamp,
  JSON_EXTRACT_SCALAR(performance_output, '$.account_classification.size_tier') AS size_tier,
  CAST(JSON_EXTRACT_SCALAR(performance_output, '$.account_classification.avg_audience') AS INT64) AS avg_audience,
  CAST(JSON_EXTRACT_SCALAR(performance_output, '$.account_classification.total_revenue_period') AS FLOAT64) AS total_revenue,
  JSON_EXTRACT_SCALAR(performance_output, '$.behavioral_segment.segment_label') AS segment_label,
  CAST(JSON_EXTRACT_SCALAR(performance_output, '$.behavioral_segment.avg_rpr') AS FLOAT64) AS avg_rpr,
  JSON_EXTRACT_SCALAR(performance_output, '$.saturation.risk_level') AS saturation_risk,
  JSON_EXTRACT_SCALAR(performance_output, '$.saturation.recommended_action') AS recommended_action;
-- EXPECTED: 1 row, creator_name='jadebri', size_tier not null, segment_label not null

-- Test 4.2: Extract and validate psychological triggers (top 5)
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_PSYCHOLOGICAL_TRIGGERS' AS test_name,
  JSON_EXTRACT_SCALAR(trigger, '$.psychological_trigger') AS trigger_name,
  CAST(JSON_EXTRACT_SCALAR(trigger, '$.msg_count') AS INT64) AS msg_count,
  CAST(JSON_EXTRACT_SCALAR(trigger, '$.avg_rpr') AS FLOAT64) AS avg_rpr,
  CAST(JSON_EXTRACT_SCALAR(trigger, '$.rpr_lift_pct') AS FLOAT64) AS rpr_lift_pct,
  CAST(JSON_EXTRACT_SCALAR(trigger, '$.rpr_stat_sig') AS BOOLEAN) AS is_significant
FROM UNNEST(JSON_EXTRACT_ARRAY(performance_output, '$.psychological_trigger_analysis')) AS trigger
WITH OFFSET AS pos
WHERE pos < 5
ORDER BY pos;
-- EXPECTED: Up to 5 rows with valid trigger data

-- Test 4.3: Extract and validate content categories (top 5)
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_CONTENT_CATEGORIES' AS test_name,
  JSON_EXTRACT_SCALAR(category, '$.content_category') AS content_category,
  JSON_EXTRACT_SCALAR(category, '$.price_tier') AS price_tier,
  CAST(JSON_EXTRACT_SCALAR(category, '$.msg_count') AS INT64) AS msg_count,
  CAST(JSON_EXTRACT_SCALAR(category, '$.avg_rpr') AS FLOAT64) AS avg_rpr,
  JSON_EXTRACT_SCALAR(category, '$.trend_direction') AS trend_direction,
  JSON_EXTRACT_SCALAR(category, '$.best_price_tier') AS best_price_tier
FROM UNNEST(JSON_EXTRACT_ARRAY(performance_output, '$.content_category_performance')) AS category
WITH OFFSET AS pos
WHERE pos < 5
ORDER BY pos;
-- EXPECTED: Up to 5 rows with valid category data

-- Test 4.4: Extract and validate day patterns (all days)
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_DAY_PATTERNS' AS test_name,
  CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.day_of_week_la') AS INT64) AS day_of_week,
  CASE CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.day_of_week_la') AS INT64)
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS day_name,
  CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.msg_count') AS INT64) AS msg_count,
  CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.avg_rpr') AS FLOAT64) AS avg_rpr,
  CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.rpr_stat_sig') AS BOOLEAN) AS is_significant
FROM UNNEST(JSON_EXTRACT_ARRAY(performance_output, '$.day_of_week_patterns')) AS day_pattern
ORDER BY CAST(JSON_EXTRACT_SCALAR(day_pattern, '$.avg_rpr') AS FLOAT64) DESC;
-- EXPECTED: Up to 7 rows (one per day)

-- Test 4.5: Extract and validate time windows (top 10)
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_TIME_WINDOWS' AS test_name,
  JSON_EXTRACT_SCALAR(time_window, '$.day_type') AS day_type,
  CAST(JSON_EXTRACT_SCALAR(time_window, '$.hour_24') AS INT64) AS hour_24,
  CAST(JSON_EXTRACT_SCALAR(time_window, '$.msg_count') AS INT64) AS msg_count,
  CAST(JSON_EXTRACT_SCALAR(time_window, '$.avg_rpr') AS FLOAT64) AS avg_rpr,
  JSON_EXTRACT_SCALAR(time_window, '$.confidence') AS confidence_level
FROM UNNEST(JSON_EXTRACT_ARRAY(performance_output, '$.time_window_optimization')) AS time_window
WITH OFFSET AS pos
WHERE pos < 10
ORDER BY pos;
-- EXPECTED: Up to 10 rows with time window data

-- Test 4.6: Extract and validate available categories
DECLARE performance_output STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SELECT
  'TEST_JSON_AVAILABLE_CATEGORIES' AS test_name,
  category,
  ROW_NUMBER() OVER (ORDER BY category) AS category_rank
FROM UNNEST(JSON_EXTRACT_ARRAY(performance_output, '$.available_categories')) AS category
ORDER BY category;
-- EXPECTED: Multiple rows with distinct category values

-- =============================================================================
-- SECTION 5: PERFORMANCE BENCHMARKING
-- =============================================================================

-- Test 5.1: Measure total execution time
DECLARE start_time TIMESTAMP;
DECLARE end_time TIMESTAMP;
DECLARE execution_time_ms INT64;
DECLARE performance_output STRING;

SET start_time = CURRENT_TIMESTAMP();

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'jadebri',
  performance_output
);

SET end_time = CURRENT_TIMESTAMP();
SET execution_time_ms = TIMESTAMP_DIFF(end_time, start_time, MILLISECOND);

SELECT
  'TEST_PERFORMANCE_BENCHMARK' AS test_name,
  'jadebri' AS test_page_name,
  execution_time_ms AS execution_time_ms,
  ROUND(execution_time_ms / 1000.0, 2) AS execution_time_seconds,
  CASE
    WHEN execution_time_ms < 1000 THEN 'EXCELLENT (< 1s)'
    WHEN execution_time_ms < 3000 THEN 'GOOD (< 3s)'
    WHEN execution_time_ms < 10000 THEN 'ACCEPTABLE (< 10s)'
    ELSE 'SLOW (>= 10s)'
  END AS performance_rating,
  LENGTH(performance_output) AS output_size_bytes,
  ROUND(LENGTH(performance_output) / 1024.0, 2) AS output_size_kb,
  CASE
    WHEN execution_time_ms < 10000 THEN 'PASS'
    ELSE 'FAIL'
  END AS benchmark_result;
-- EXPECTED: execution_time_ms < 10000 (10 seconds), benchmark_result = 'PASS'

-- =============================================================================
-- SECTION 6: ERROR HANDLING TESTS
-- =============================================================================

-- Test 6.1: Non-existent page name
DECLARE output1 STRING;

CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  'NONEXISTENT_PAGE_12345',
  output1
);

SELECT
  'TEST_ERROR_HANDLING_NONEXISTENT_PAGE' AS test_name,
  output1 IS NOT NULL AS output_generated,
  LENGTH(output1) AS output_size,
  JSON_EXTRACT_SCALAR(output1, '$.creator_name') AS creator_name,
  JSON_EXTRACT_SCALAR(output1, '$.account_classification.size_tier') AS size_tier;
-- EXPECTED: output generated (not null), but may have NULL/empty values for analytics

-- Test 6.2: Zero lookback days (direct TVF test)
SELECT
  'TEST_ERROR_HANDLING_ZERO_LOOKBACK' AS test_name,
  account_size_classification.size_tier
FROM `of-scheduler-proj.eros_scheduling_brain`.classify_account_size('jadebri', 0);
-- EXPECTED: Empty result or NULL values

-- Test 6.3: Negative lookback days (direct TVF test)
SELECT
  'TEST_ERROR_HANDLING_NEGATIVE_LOOKBACK' AS test_name,
  COUNT(*) AS result_count
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('jadebri', -30);
-- EXPECTED: result_count = 0

-- =============================================================================
-- SECTION 7: DATA QUALITY CHECKS
-- =============================================================================

-- Test 7.1: Verify mass_messages has recent data
SELECT
  'TEST_DATA_QUALITY_MASS_MESSAGES' AS test_name,
  COUNT(*) AS total_records,
  COUNT(DISTINCT page_name) AS unique_pages,
  MIN(sending_time) AS earliest_date,
  MAX(sending_time) AS latest_date,
  DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(MAX(sending_time), 'America/Los_Angeles'), DAY) AS days_since_latest,
  CASE
    WHEN DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(MAX(sending_time), 'America/Los_Angeles'), DAY) <= 7 THEN 'PASS'
    ELSE 'FAIL'
  END AS freshness_check
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE page_name = 'jadebri'
  AND viewed_count > 0;
-- EXPECTED: freshness_check = 'PASS' (data within last 7 days)

-- Test 7.2: Verify caption_bank_enriched coverage
SELECT
  'TEST_DATA_QUALITY_CAPTION_ENRICHMENT' AS test_name,
  COUNT(DISTINCT mm.message) AS total_messages,
  COUNT(DISTINCT CASE WHEN cb.caption_key IS NOT NULL THEN mm.message END) AS enriched_messages,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN cb.caption_key IS NOT NULL THEN mm.message END) / NULLIF(COUNT(DISTINCT mm.message), 0), 2) AS coverage_pct,
  CASE
    WHEN 100.0 * COUNT(DISTINCT CASE WHEN cb.caption_key IS NOT NULL THEN mm.message END) / NULLIF(COUNT(DISTINCT mm.message), 0) >= 80 THEN 'PASS'
    ELSE 'FAIL'
  END AS coverage_check
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank_enriched` cb
  ON `of-scheduler-proj.eros_scheduling_brain`.caption_key(mm.message) = cb.caption_key
WHERE mm.page_name = 'jadebri'
  AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 90 DAY);
-- EXPECTED: coverage_pct >= 80%, coverage_check = 'PASS'

-- Test 7.3: Verify creator has sufficient message history
SELECT
  'TEST_DATA_QUALITY_MESSAGE_HISTORY' AS test_name,
  COUNT(*) AS total_messages,
  COUNT(DISTINCT DATE(sending_time, 'America/Los_Angeles')) AS active_days,
  MIN(sending_time) AS first_message,
  MAX(sending_time) AS last_message,
  DATE_DIFF(DATE(MAX(sending_time), 'America/Los_Angeles'), DATE(MIN(sending_time), 'America/Los_Angeles'), DAY) AS history_span_days,
  CASE
    WHEN COUNT(*) >= 100 AND DATE_DIFF(DATE(MAX(sending_time), 'America/Los_Angeles'), DATE(MIN(sending_time), 'America/Los_Angeles'), DAY) >= 30 THEN 'PASS'
    ELSE 'FAIL'
  END AS history_check
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE page_name = 'jadebri'
  AND viewed_count > 0;
-- EXPECTED: history_check = 'PASS' (100+ messages over 30+ days)

-- =============================================================================
-- SECTION 8: FINAL SUMMARY REPORT
-- =============================================================================

-- Generate comprehensive test summary
SELECT
  'FINAL_TEST_SUMMARY' AS report_name,
  CURRENT_TIMESTAMP('America/Los_Angeles') AS report_timestamp,
  'jadebri' AS test_page,
  '90 days' AS lookback_window,
  'All TVFs and Main Procedure' AS components_tested,
  '8 functions (7 TVFs + 1 PROC)' AS deployment_target,
  'Verify output manually for PASS/FAIL' AS result_status;

-- =============================================================================
-- END OF TEST SUITE
-- =============================================================================
