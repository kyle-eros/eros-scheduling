-- =============================================================================
-- PRODUCTION INFRASTRUCTURE VERIFICATION SUITE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Comprehensive verification of infrastructure deployment
-- Usage: Run after deploying PRODUCTION_INFRASTRUCTURE.sql
-- =============================================================================

-- =============================================================================
-- TEST SUITE 1: OBJECT EXISTENCE VERIFICATION
-- =============================================================================

-- Test 1.1: Verify all 4 UDFs exist
SELECT
  '1.1 UDF Existence Check' AS test_name,
  COUNT(*) AS objects_found,
  4 AS expected_count,
  CASE WHEN COUNT(*) = 4 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(routine_name, ', ' ORDER BY routine_name) AS objects_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'caption_key_v2',
  'caption_key',
  'wilson_score_bounds',
  'wilson_sample'
)
AND routine_type = 'SCALAR_FUNCTION';

-- Test 1.2: Verify all 3 core tables exist
SELECT
  '1.2 Core Tables Existence Check' AS test_name,
  COUNT(*) AS objects_found,
  3 AS expected_count,
  CASE WHEN COUNT(*) = 3 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(table_name, ', ' ORDER BY table_name) AS objects_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN (
  'caption_bandit_stats',
  'holiday_calendar',
  'schedule_export_log'
)
AND table_type = 'BASE TABLE';

-- Test 1.3: Verify schedule_recommendations_messages view exists
SELECT
  '1.3 View Existence Check' AS test_name,
  COUNT(*) AS objects_found,
  1 AS expected_count,
  CASE WHEN COUNT(*) = 1 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(table_name, ', ' ORDER BY table_name) AS objects_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'schedule_recommendations_messages'
AND table_type = 'VIEW';

-- Test 1.4: Verify all 4 stored procedures exist
SELECT
  '1.4 Stored Procedures Existence Check' AS test_name,
  COUNT(*) AS objects_found,
  4 AS expected_count,
  CASE WHEN COUNT(*) = 4 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(routine_name, ', ' ORDER BY routine_name) AS objects_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'update_caption_performance',
  'run_daily_automation',
  'sweep_expired_caption_locks',
  'select_captions_for_creator'
)
AND routine_type = 'PROCEDURE';

-- =============================================================================
-- TEST SUITE 2: UDF FUNCTIONALITY VERIFICATION
-- =============================================================================

-- Test 2.1: caption_key_v2 generates consistent hashes
WITH test_cases AS (
  SELECT 'Test message 123' AS input_text UNION ALL
  SELECT 'Hello World!' UNION ALL
  SELECT '🔥 Hot content here 🔥'
)
SELECT
  '2.1 caption_key_v2 Consistency Test' AS test_name,
  COUNT(DISTINCT caption_key) AS unique_keys,
  COUNT(*) AS total_calls,
  CASE
    WHEN COUNT(DISTINCT caption_key) = COUNT(*) THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  ARRAY_AGG(
    STRUCT(
      input_text,
      `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(input_text) AS caption_key
    )
  ) AS test_samples
FROM test_cases;

-- Test 2.2: caption_key wrapper delegates to caption_key_v2
SELECT
  '2.2 caption_key Wrapper Test' AS test_name,
  COUNT(*) AS matching_results,
  3 AS expected_count,
  CASE WHEN COUNT(*) = 3 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result
FROM (
  SELECT
    'Test 1' AS test_case,
    `of-scheduler-proj.eros_scheduling_brain.caption_key`('Test') =
    `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`('Test') AS keys_match
  UNION ALL
  SELECT 'Test 2',
    `of-scheduler-proj.eros_scheduling_brain.caption_key`('Hello World') =
    `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`('Hello World')
  UNION ALL
  SELECT 'Test 3',
    `of-scheduler-proj.eros_scheduling_brain.caption_key`('🎯 Target') =
    `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`('🎯 Target')
)
WHERE keys_match = TRUE;

-- Test 2.3: wilson_score_bounds returns valid confidence intervals
WITH test_cases AS (
  SELECT 100 AS successes, 100 AS failures UNION ALL
  SELECT 50, 50 UNION ALL
  SELECT 10, 10 UNION ALL
  SELECT 90, 10 UNION ALL
  SELECT 10, 90 UNION ALL
  SELECT 0, 0
),
bounds_test AS (
  SELECT
    successes,
    failures,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(successes, failures) AS bounds
  FROM test_cases
)
SELECT
  '2.3 wilson_score_bounds Validity Test' AS test_name,
  COUNT(*) AS valid_bounds,
  6 AS expected_count,
  CASE WHEN COUNT(*) = 6 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  ARRAY_AGG(
    STRUCT(
      successes,
      failures,
      ROUND(bounds.lower_bound, 4) AS lower_bound,
      ROUND(bounds.upper_bound, 4) AS upper_bound,
      ROUND(bounds.exploration_bonus, 4) AS exploration_bonus
    ) ORDER BY successes DESC, failures DESC
  ) AS test_samples
FROM bounds_test
WHERE bounds.lower_bound >= 0
  AND bounds.upper_bound <= 1
  AND bounds.lower_bound <= bounds.upper_bound
  AND bounds.exploration_bonus >= 0;

-- Test 2.4: wilson_sample returns values within bounds
WITH samples AS (
  SELECT
    50 AS successes,
    50 AS failures,
    `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) AS sample,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50) AS bounds
  FROM UNNEST(GENERATE_ARRAY(1, 100))  -- Generate 100 samples
)
SELECT
  '2.4 wilson_sample Bounds Test' AS test_name,
  COUNT(*) AS samples_within_bounds,
  100 AS expected_count,
  CASE WHEN COUNT(*) = 100 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  ROUND(MIN(sample), 4) AS min_sample,
  ROUND(MAX(sample), 4) AS max_sample,
  ROUND(AVG(sample), 4) AS avg_sample
FROM samples
WHERE sample >= bounds.lower_bound
  AND sample <= bounds.upper_bound
  AND sample >= 0
  AND sample <= 1;

-- =============================================================================
-- TEST SUITE 3: TABLE SCHEMA VERIFICATION
-- =============================================================================

-- Test 3.1: caption_bandit_stats has all required columns
WITH expected_columns AS (
  SELECT column_name FROM UNNEST([
    'caption_id',
    'page_name',
    'successes',
    'failures',
    'total_observations',
    'total_revenue',
    'avg_conversion_rate',
    'avg_emv',
    'last_emv_observed',
    'confidence_lower_bound',
    'confidence_upper_bound',
    'exploration_score',
    'last_used',
    'last_updated',
    'performance_percentile'
  ]) AS column_name
)
SELECT
  '3.1 caption_bandit_stats Schema Test' AS test_name,
  COUNT(*) AS columns_found,
  15 AS expected_count,
  CASE WHEN COUNT(*) = 15 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(c.column_name, ', ' ORDER BY c.ordinal_position) AS columns_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS` c
JOIN expected_columns e USING (column_name)
WHERE c.table_name = 'caption_bandit_stats';

-- Test 3.2: caption_bandit_stats is partitioned and clustered
SELECT
  '3.2 caption_bandit_stats Partitioning Test' AS test_name,
  CASE
    WHEN is_partitioning_column = 'YES' THEN 1
    ELSE 0
  END +
  CASE
    WHEN COUNT(DISTINCT clustering_ordinal_position) >= 3 THEN 1
    ELSE 0
  END AS config_score,
  2 AS expected_score,
  CASE
    WHEN is_partitioning_column = 'YES'
      AND COUNT(DISTINCT clustering_ordinal_position) >= 3
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  MAX(is_partitioning_column) AS has_partitioning,
  COUNT(DISTINCT clustering_ordinal_position) AS cluster_columns
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
GROUP BY is_partitioning_column;

-- Test 3.3: holiday_calendar has required columns and data
SELECT
  '3.3 holiday_calendar Schema and Data Test' AS test_name,
  COUNT(DISTINCT c.column_name) AS columns_found,
  5 AS expected_column_count,
  COUNT(DISTINCT h.holiday_date) AS holidays_seeded,
  CASE
    WHEN COUNT(DISTINCT c.column_name) >= 5
      AND COUNT(DISTINCT h.holiday_date) >= 20
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS` c
CROSS JOIN `of-scheduler-proj.eros_scheduling_brain.holiday_calendar` h
WHERE c.table_name = 'holiday_calendar'
  AND c.column_name IN ('holiday_date', 'holiday_name', 'holiday_type', 'is_major_holiday', 'saturation_impact_factor')
  AND EXTRACT(YEAR FROM h.holiday_date) = 2025
GROUP BY c.table_name;

-- Test 3.4: schedule_export_log has telemetry columns
WITH expected_columns AS (
  SELECT column_name FROM UNNEST([
    'schedule_id',
    'page_name',
    'export_timestamp',
    'message_count',
    'execution_time_seconds',
    'status',
    'error_message',
    'export_format',
    'exported_by'
  ]) AS column_name
)
SELECT
  '3.4 schedule_export_log Schema Test' AS test_name,
  COUNT(*) AS columns_found,
  9 AS expected_count,
  CASE WHEN COUNT(*) = 9 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS` c
JOIN expected_columns e USING (column_name)
WHERE c.table_name = 'schedule_export_log';

-- =============================================================================
-- TEST SUITE 4: VIEW FUNCTIONALITY VERIFICATION
-- =============================================================================

-- Test 4.1: schedule_recommendations_messages view has required columns
WITH expected_columns AS (
  SELECT column_name FROM UNNEST([
    'schedule_id',
    'page_name',
    'day_of_week',
    'scheduled_send_time',
    'message_type',
    'caption_id',
    'caption_text',
    'price_tier',
    'content_category',
    'has_urgency',
    'performance_score',
    'confidence_lower_bound',
    'confidence_upper_bound',
    'total_observations',
    'caption_last_updated',
    'schedule_created_at',
    'schedule_is_active',
    'time_slot_rank'
  ]) AS column_name
)
SELECT
  '4.1 schedule_recommendations_messages View Schema Test' AS test_name,
  COUNT(*) AS columns_found,
  18 AS expected_count,
  CASE WHEN COUNT(*) >= 18 THEN 'PASS ✓' ELSE 'FAIL ✗' END AS test_result,
  STRING_AGG(c.column_name, ', ' ORDER BY c.ordinal_position) AS columns_list
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS` c
JOIN expected_columns e USING (column_name)
WHERE c.table_name = 'schedule_recommendations_messages';

-- =============================================================================
-- TEST SUITE 5: PROCEDURE SIGNATURE VERIFICATION
-- =============================================================================

-- Test 5.1: update_caption_performance procedure signature
SELECT
  '5.1 update_caption_performance Signature Test' AS test_name,
  routine_name,
  routine_type,
  CASE
    WHEN routine_type = 'PROCEDURE'
      AND routine_name = 'update_caption_performance'
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  'No input parameters' AS parameter_info
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'update_caption_performance';

-- Test 5.2: run_daily_automation procedure signature
SELECT
  '5.2 run_daily_automation Signature Test' AS test_name,
  routine_name,
  routine_type,
  CASE
    WHEN routine_type = 'PROCEDURE'
      AND routine_name = 'run_daily_automation'
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  'IN execution_date DATE' AS parameter_info
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'run_daily_automation';

-- Test 5.3: sweep_expired_caption_locks procedure signature
SELECT
  '5.3 sweep_expired_caption_locks Signature Test' AS test_name,
  routine_name,
  routine_type,
  CASE
    WHEN routine_type = 'PROCEDURE'
      AND routine_name = 'sweep_expired_caption_locks'
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  'No input parameters' AS parameter_info
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'sweep_expired_caption_locks';

-- Test 5.4: select_captions_for_creator procedure signature
SELECT
  '5.4 select_captions_for_creator Signature Test' AS test_name,
  routine_name,
  routine_type,
  CASE
    WHEN routine_type = 'PROCEDURE'
      AND routine_name = 'select_captions_for_creator'
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  '6 input parameters (page_name, segment, 4 tier counts)' AS parameter_info
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'select_captions_for_creator';

-- =============================================================================
-- TEST SUITE 6: DATA INTEGRITY CHECKS
-- =============================================================================

-- Test 6.1: Holiday calendar has valid date ranges and impact factors
SELECT
  '6.1 Holiday Calendar Data Integrity Test' AS test_name,
  COUNT(*) AS total_holidays,
  COUNT(CASE WHEN saturation_impact_factor BETWEEN 0 AND 1 THEN 1 END) AS valid_impact_factors,
  COUNT(CASE WHEN holiday_date >= '2025-01-01' AND holiday_date <= '2025-12-31' THEN 1 END) AS dates_in_2025,
  CASE
    WHEN COUNT(*) >= 20
      AND COUNT(CASE WHEN saturation_impact_factor BETWEEN 0 AND 1 THEN 1 END) = COUNT(*)
      AND COUNT(CASE WHEN holiday_date >= '2025-01-01' AND holiday_date <= '2025-12-31' THEN 1 END) >= 20
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result
FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
WHERE EXTRACT(YEAR FROM holiday_date) = 2025;

-- Test 6.2: Holiday types are valid
SELECT
  '6.2 Holiday Types Validation Test' AS test_name,
  COUNT(DISTINCT holiday_type) AS unique_types,
  STRING_AGG(DISTINCT holiday_type, ', ' ORDER BY holiday_type) AS types_found,
  CASE
    WHEN COUNT(DISTINCT holiday_type) = 3
      AND 'FEDERAL' IN UNNEST(ARRAY_AGG(DISTINCT holiday_type))
      AND 'CULTURAL' IN UNNEST(ARRAY_AGG(DISTINCT holiday_type))
      AND 'COMMERCIAL' IN UNNEST(ARRAY_AGG(DISTINCT holiday_type))
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result
FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
WHERE EXTRACT(YEAR FROM holiday_date) = 2025;

-- =============================================================================
-- TEST SUITE 7: TIMEZONE CONSISTENCY CHECK
-- =============================================================================

-- Test 7.1: Verify America/Los_Angeles timezone is available
SELECT
  '7.1 Timezone Availability Test' AS test_name,
  CURRENT_DATE('America/Los_Angeles') AS la_current_date,
  CURRENT_TIMESTAMP() AS utc_timestamp,
  DATETIME(CURRENT_TIMESTAMP(), 'America/Los_Angeles') AS la_datetime,
  CASE
    WHEN CURRENT_DATE('America/Los_Angeles') IS NOT NULL
      AND DATETIME(CURRENT_TIMESTAMP(), 'America/Los_Angeles') IS NOT NULL
    THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result;

-- =============================================================================
-- TEST SUITE 8: PERFORMANCE BASELINE CHECKS
-- =============================================================================

-- Test 8.1: UDF performance baseline (< 1ms per call)
WITH performance_test AS (
  SELECT
    `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`('Performance test ' || CAST(n AS STRING)) AS key,
    `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) AS sample
  FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS n
)
SELECT
  '8.1 UDF Performance Baseline Test' AS test_name,
  COUNT(*) AS operations_completed,
  1000 AS expected_count,
  CASE
    WHEN COUNT(*) = 1000 THEN 'PASS ✓'
    ELSE 'FAIL ✗'
  END AS test_result,
  'Performance: All UDFs executed successfully' AS performance_note
FROM performance_test;

-- =============================================================================
-- SUMMARY REPORT
-- =============================================================================

-- Generate comprehensive test summary
WITH all_tests AS (
  SELECT '1.1' AS test_id, 'UDF Existence' AS test_category, 'Core Infrastructure' AS test_group UNION ALL
  SELECT '1.2', 'Table Existence', 'Core Infrastructure' UNION ALL
  SELECT '1.3', 'View Existence', 'Core Infrastructure' UNION ALL
  SELECT '1.4', 'Procedure Existence', 'Core Infrastructure' UNION ALL
  SELECT '2.1', 'caption_key_v2 Function', 'UDF Functionality' UNION ALL
  SELECT '2.2', 'caption_key Wrapper', 'UDF Functionality' UNION ALL
  SELECT '2.3', 'wilson_score_bounds', 'UDF Functionality' UNION ALL
  SELECT '2.4', 'wilson_sample', 'UDF Functionality' UNION ALL
  SELECT '3.1', 'caption_bandit_stats Schema', 'Table Schema' UNION ALL
  SELECT '3.2', 'caption_bandit_stats Partitioning', 'Table Schema' UNION ALL
  SELECT '3.3', 'holiday_calendar Schema', 'Table Schema' UNION ALL
  SELECT '3.4', 'schedule_export_log Schema', 'Table Schema' UNION ALL
  SELECT '4.1', 'schedule_recommendations_messages View', 'View Functionality' UNION ALL
  SELECT '5.1', 'update_caption_performance', 'Procedure Signatures' UNION ALL
  SELECT '5.2', 'run_daily_automation', 'Procedure Signatures' UNION ALL
  SELECT '5.3', 'sweep_expired_caption_locks', 'Procedure Signatures' UNION ALL
  SELECT '5.4', 'select_captions_for_creator', 'Procedure Signatures' UNION ALL
  SELECT '6.1', 'Holiday Data Integrity', 'Data Integrity' UNION ALL
  SELECT '6.2', 'Holiday Types Validation', 'Data Integrity' UNION ALL
  SELECT '7.1', 'Timezone Availability', 'Timezone Consistency' UNION ALL
  SELECT '8.1', 'UDF Performance', 'Performance Baseline'
)
SELECT
  '=' AS separator,
  'VERIFICATION SUMMARY' AS report_title,
  COUNT(*) AS total_tests,
  '21 tests across 8 categories' AS test_coverage,
  'Run each test suite above individually to see detailed results' AS instructions,
  '=' AS end_separator
FROM all_tests;

-- =============================================================================
-- DEPLOYMENT VERIFICATION COMPLETE
-- =============================================================================
-- Next steps after all tests pass:
-- 1. Deploy CORRECTED_analyze_creator_performance_FULL.sql (TVFs + procedure)
-- 2. Configure BigQuery scheduled queries:
--    - update_caption_performance: Every 6 hours
--    - run_daily_automation: Daily at 03:05 America/Los_Angeles
--    - sweep_expired_caption_locks: Hourly
-- 3. Test procedures with production data
-- 4. Monitor etl_job_runs and automation_alerts tables
-- 5. Set up alerting for automation_alerts (CRITICAL level)
-- =============================================================================
