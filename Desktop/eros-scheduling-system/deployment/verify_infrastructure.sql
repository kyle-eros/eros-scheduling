-- =============================================================================
-- EROS SCHEDULING SYSTEM - INFRASTRUCTURE VERIFICATION SUITE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Comprehensive verification of all deployed infrastructure
-- =============================================================================

-- =============================================================================
-- SECTION 1: OBJECT INVENTORY
-- =============================================================================

-- Check 1.1: UDF Inventory
WITH expected_udfs AS (
  SELECT name FROM UNNEST([
    'caption_key_v2',
    'caption_key',
    'wilson_score_bounds',
    'wilson_sample'
  ]) AS name
)
SELECT
  'UDF_INVENTORY' AS check_type,
  e.name AS expected_object,
  CASE WHEN r.routine_name IS NOT NULL THEN 'FOUND' ELSE 'MISSING' END AS status,
  r.routine_type,
  r.created AS created_timestamp
FROM expected_udfs e
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES` r
  ON e.name = r.routine_name AND r.routine_type = 'SCALAR_FUNCTION'
ORDER BY e.name;
-- EXPECTED: 4 FOUND, 0 MISSING

-- Check 1.2: Table Inventory
WITH expected_tables AS (
  SELECT name FROM UNNEST([
    'caption_bandit_stats',
    'holiday_calendar',
    'schedule_export_log'
  ]) AS name
)
SELECT
  'TABLE_INVENTORY' AS check_type,
  e.name AS expected_object,
  CASE WHEN t.table_name IS NOT NULL THEN 'FOUND' ELSE 'MISSING' END AS status,
  t.table_type,
  t.creation_time
FROM expected_tables e
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES` t
  ON e.name = t.table_name
ORDER BY e.name;
-- EXPECTED: 3 FOUND, 0 MISSING

-- Check 1.3: View Inventory
WITH expected_views AS (
  SELECT name FROM UNNEST([
    'schedule_recommendations_messages'
  ]) AS name
)
SELECT
  'VIEW_INVENTORY' AS check_type,
  e.name AS expected_object,
  CASE WHEN t.table_name IS NOT NULL THEN 'FOUND' ELSE 'MISSING' END AS status,
  t.table_type,
  t.creation_time
FROM expected_views e
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES` t
  ON e.name = t.table_name AND t.table_type = 'VIEW'
ORDER BY e.name;
-- EXPECTED: 1 FOUND, 0 MISSING

-- Check 1.4: Stored Procedure Inventory
WITH expected_procedures AS (
  SELECT name FROM UNNEST([
    'update_caption_performance',
    'select_captions_for_creator',
    'run_daily_automation',
    'sweep_expired_caption_locks'
  ]) AS name
)
SELECT
  'PROCEDURE_INVENTORY' AS check_type,
  e.name AS expected_object,
  CASE WHEN r.routine_name IS NOT NULL THEN 'FOUND' ELSE 'MISSING' END AS status,
  r.routine_type,
  r.created AS created_timestamp
FROM expected_procedures e
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES` r
  ON e.name = r.routine_name AND r.routine_type = 'PROCEDURE'
ORDER BY e.name;
-- EXPECTED: 4 FOUND, 0 MISSING

-- =============================================================================
-- SECTION 2: SCHEMA VALIDATION
-- =============================================================================

-- Check 2.1: caption_bandit_stats schema
SELECT
  'SCHEMA_caption_bandit_stats' AS check_type,
  column_name,
  data_type,
  is_nullable,
  is_partitioning_column,
  clustering_ordinal_position
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
ORDER BY ordinal_position;
-- EXPECTED: 15 columns (caption_id, page_name, successes, failures, etc.)

-- Check 2.2: holiday_calendar schema
SELECT
  'SCHEMA_holiday_calendar' AS check_type,
  column_name,
  data_type,
  is_nullable
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'holiday_calendar'
ORDER BY ordinal_position;
-- EXPECTED: 6 columns (holiday_date, holiday_name, holiday_type, etc.)

-- Check 2.3: schedule_export_log schema
SELECT
  'SCHEMA_schedule_export_log' AS check_type,
  column_name,
  data_type,
  is_nullable
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'schedule_export_log'
ORDER BY ordinal_position;
-- EXPECTED: 9 columns (schedule_id, page_name, export_timestamp, etc.)

-- =============================================================================
-- SECTION 3: FUNCTIONAL TESTS
-- =============================================================================

-- Test 3.1: caption_key UDF - Consistency check
WITH test_messages AS (
  SELECT message FROM UNNEST([
    'Test message 123',
    'Test message 123!',
    'test MESSAGE 123',
    'Test   message   123'
  ]) AS message
)
SELECT
  'TEST_caption_key_consistency' AS test_name,
  COUNT(DISTINCT `of-scheduler-proj.eros_scheduling_brain.caption_key`(message)) AS unique_keys,
  CASE WHEN COUNT(DISTINCT `of-scheduler-proj.eros_scheduling_brain.caption_key`(message)) = 1
    THEN 'PASS' ELSE 'FAIL'
  END AS test_result
FROM test_messages;
-- EXPECTED: 1 unique_key (all variations produce same key), PASS

-- Test 3.2: wilson_score_bounds UDF - Boundary conditions
WITH test_cases AS (
  SELECT * FROM UNNEST([
    STRUCT(0 AS successes, 0 AS failures, 'zero_observations'),
    STRUCT(100 AS successes, 100 AS failures, 'balanced_high'),
    STRUCT(1 AS successes, 1 AS failures, 'balanced_low'),
    STRUCT(90 AS successes, 10 AS failures, 'skewed_success'),
    STRUCT(10 AS successes, 90 AS failures, 'skewed_failure')
  ])
),
bounds_results AS (
  SELECT
    tc.successes,
    tc.failures,
    tc.failures AS test_label,
    bounds.lower_bound,
    bounds.upper_bound,
    bounds.exploration_bonus
  FROM test_cases tc
  CROSS JOIN UNNEST([
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(tc.successes, tc.failures)
  ]) bounds
)
SELECT
  'TEST_wilson_score_bounds' AS test_name,
  test_label,
  successes,
  failures,
  ROUND(lower_bound, 4) AS lower_bound,
  ROUND(upper_bound, 4) AS upper_bound,
  ROUND(exploration_bonus, 4) AS exploration_bonus,
  CASE
    WHEN lower_bound >= 0 AND upper_bound <= 1 AND lower_bound <= upper_bound
    THEN 'PASS' ELSE 'FAIL'
  END AS bounds_validity
FROM bounds_results
ORDER BY successes, failures;
-- EXPECTED: All PASS (bounds between 0 and 1, lower <= upper)

-- Test 3.3: wilson_sample UDF - Distribution check
WITH sample_results AS (
  SELECT
    `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) AS sample
  FROM UNNEST(GENERATE_ARRAY(1, 100))
)
SELECT
  'TEST_wilson_sample_distribution' AS test_name,
  COUNT(*) AS sample_count,
  ROUND(MIN(sample), 4) AS min_sample,
  ROUND(MAX(sample), 4) AS max_sample,
  ROUND(AVG(sample), 4) AS avg_sample,
  ROUND(STDDEV(sample), 4) AS stddev_sample,
  CASE
    WHEN MIN(sample) >= 0 AND MAX(sample) <= 1
    THEN 'PASS' ELSE 'FAIL'
  END AS bounds_check
FROM sample_results;
-- EXPECTED: 100 samples, all between 0 and 1, avg ~0.5

-- =============================================================================
-- SECTION 4: DATA VALIDATION
-- =============================================================================

-- Check 4.1: holiday_calendar data
SELECT
  'DATA_holiday_calendar' AS check_type,
  COUNT(*) AS total_holidays,
  COUNT(DISTINCT EXTRACT(YEAR FROM holiday_date)) AS years_covered,
  MIN(holiday_date) AS earliest_holiday,
  MAX(holiday_date) AS latest_holiday,
  COUNT(CASE WHEN is_major_holiday THEN 1 END) AS major_holidays,
  CASE WHEN COUNT(*) >= 20 THEN 'PASS' ELSE 'FAIL' END AS data_check
FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`;
-- EXPECTED: 20+ holidays, 1 year (2025), PASS

-- Check 4.2: caption_bandit_stats initial state
SELECT
  'DATA_caption_bandit_stats' AS check_type,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT page_name) AS unique_pages,
  COUNT(DISTINCT caption_id) AS unique_captions,
  CASE WHEN COUNT(*) = 0 THEN 'EMPTY_EXPECTED' ELSE 'HAS_DATA' END AS state
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
-- EXPECTED: EMPTY_EXPECTED (no data until first update_caption_performance run)

-- Check 4.3: schedule_export_log initial state
SELECT
  'DATA_schedule_export_log' AS check_type,
  COUNT(*) AS total_rows,
  CASE WHEN COUNT(*) = 0 THEN 'EMPTY_EXPECTED' ELSE 'HAS_DATA' END AS state
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`;
-- EXPECTED: EMPTY_EXPECTED (no data until first export)

-- =============================================================================
-- SECTION 5: PARTITION AND CLUSTERING VALIDATION
-- =============================================================================

-- Check 5.1: Verify partitioning and clustering on caption_bandit_stats
SELECT
  'PARTITION_CLUSTER_caption_bandit_stats' AS check_type,
  column_name,
  is_partitioning_column,
  clustering_ordinal_position
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
  AND (is_partitioning_column = 'YES' OR clustering_ordinal_position IS NOT NULL)
ORDER BY clustering_ordinal_position;
-- EXPECTED: 1 partition column (last_updated), 3 clustering columns (page_name, caption_id, last_used)

-- Check 5.2: Verify partitioning on schedule_export_log
SELECT
  'PARTITION_schedule_export_log' AS check_type,
  column_name,
  is_partitioning_column
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'schedule_export_log'
  AND is_partitioning_column = 'YES';
-- EXPECTED: 1 partition column (export_timestamp)

-- =============================================================================
-- SECTION 6: DEPENDENCY VALIDATION
-- =============================================================================

-- Check 6.1: Verify UDF dependencies for stored procedures
WITH procedure_deps AS (
  SELECT DISTINCT
    routine_name,
    REGEXP_EXTRACT_ALL(routine_definition, r'`of-scheduler-proj\.eros_scheduling_brain\.([a-z_]+)`') AS referenced_objects
  FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_type = 'PROCEDURE'
)
SELECT
  'DEPENDENCY_CHECK' AS check_type,
  routine_name,
  referenced_object,
  CASE WHEN EXISTS (
    SELECT 1
    FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES` r
    WHERE r.routine_name = referenced_object
  ) THEN 'FOUND' ELSE 'CHECK_MANUAL' END AS dependency_status
FROM procedure_deps
CROSS JOIN UNNEST(referenced_objects) AS referenced_object
WHERE referenced_object IN ('wilson_score_bounds', 'wilson_sample', 'caption_key')
ORDER BY routine_name, referenced_object;
-- EXPECTED: All dependencies FOUND

-- =============================================================================
-- SECTION 7: PERFORMANCE BASELINE
-- =============================================================================

-- Perf 7.1: UDF Performance - caption_key
WITH perf_test AS (
  SELECT
    `of-scheduler-proj.eros_scheduling_brain.caption_key`(message) AS key,
    CURRENT_TIMESTAMP() AS ts
  FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS n
  CROSS JOIN UNNEST(['Test message for performance testing']) AS message
)
SELECT
  'PERF_caption_key' AS test_name,
  COUNT(*) AS iterations,
  '< 1s for 1000 calls expected' AS expectation
FROM perf_test;

-- Perf 7.2: UDF Performance - wilson_score_bounds
WITH perf_test AS (
  SELECT
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50) AS bounds
  FROM UNNEST(GENERATE_ARRAY(1, 1000))
)
SELECT
  'PERF_wilson_score_bounds' AS test_name,
  COUNT(*) AS iterations,
  '< 1s for 1000 calls expected' AS expectation
FROM perf_test;

-- =============================================================================
-- SECTION 8: COMPREHENSIVE SUMMARY
-- =============================================================================

WITH validation_summary AS (
  -- UDF Count
  SELECT 'UDFs' AS object_type, COUNT(*) AS count_found, 4 AS count_expected
  FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_type = 'SCALAR_FUNCTION'
    AND routine_name IN ('caption_key_v2', 'caption_key', 'wilson_score_bounds', 'wilson_sample')

  UNION ALL

  -- Procedure Count
  SELECT 'Procedures', COUNT(*), 4
  FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_type = 'PROCEDURE'
    AND routine_name IN ('update_caption_performance', 'select_captions_for_creator',
                         'run_daily_automation', 'sweep_expired_caption_locks')

  UNION ALL

  -- Table Count
  SELECT 'Tables', COUNT(*), 3
  FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
  WHERE table_name IN ('caption_bandit_stats', 'holiday_calendar', 'schedule_export_log')
    AND table_type = 'BASE TABLE'

  UNION ALL

  -- View Count
  SELECT 'Views', COUNT(*), 1
  FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
  WHERE table_name IN ('schedule_recommendations_messages')
    AND table_type = 'VIEW'

  UNION ALL

  -- Holiday Data
  SELECT 'Holiday Records', COUNT(*), 20
  FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
)
SELECT
  'DEPLOYMENT_SUMMARY' AS summary_type,
  object_type,
  count_found,
  count_expected,
  CASE WHEN count_found = count_expected THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM validation_summary
ORDER BY
  CASE object_type
    WHEN 'UDFs' THEN 1
    WHEN 'Procedures' THEN 2
    WHEN 'Tables' THEN 3
    WHEN 'Views' THEN 4
    WHEN 'Holiday Records' THEN 5
  END;

-- =============================================================================
-- VERIFICATION COMPLETE
-- =============================================================================
-- Run all queries in sequence to verify infrastructure deployment.
-- All checks should show PASS or FOUND status.
-- =============================================================================
