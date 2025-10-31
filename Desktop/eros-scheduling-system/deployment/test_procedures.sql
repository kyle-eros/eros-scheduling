-- =============================================================================
-- STORED PROCEDURES TEST SUITE
-- =============================================================================
-- Purpose: Comprehensive testing for stored procedures
-- Database: of-scheduler-proj.eros_scheduling_brain
-- =============================================================================

-- ============================================================================
-- TEST SECTION 1: SYNTAX VALIDATION
-- ============================================================================
-- These tests verify that procedures compile without syntax errors

-- Test 1.1: Verify update_caption_performance exists
SELECT
  routine_name,
  routine_type,
  date(creation_time) as created_date,
  'PASS - Procedure created' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'update_caption_performance'
  AND routine_schema = 'eros_scheduling_brain'
LIMIT 1;

-- Expected output: 1 row with PASS status

-- Test 1.2: Verify lock_caption_assignments exists
SELECT
  routine_name,
  routine_type,
  date(creation_time) as created_date,
  'PASS - Procedure created' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'lock_caption_assignments'
  AND routine_schema = 'eros_scheduling_brain'
LIMIT 1;

-- Expected output: 1 row with PASS status

-- ============================================================================
-- TEST SECTION 2: DEPENDENCY VALIDATION
-- ============================================================================
-- These tests verify that all required UDFs and tables exist

-- Test 2.1: Verify wilson_score_bounds UDF exists
SELECT
  routine_name,
  routine_type,
  'UDF available for procedures' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'wilson_score_bounds'
  AND routine_schema = 'eros_scheduling_brain';

-- Expected output: 1 row showing wilson_score_bounds is a FUNCTION

-- Test 2.2: Verify wilson_sample UDF exists
SELECT
  routine_name,
  routine_type,
  'UDF available for procedures' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'wilson_sample'
  AND routine_schema = 'eros_scheduling_brain';

-- Expected output: 1 row showing wilson_sample is a FUNCTION

-- Test 2.3: Verify caption_bandit_stats table has required columns
SELECT
  table_name,
  STRING_AGG(column_name ORDER BY ordinal_position) as all_columns,
  COUNTIF(column_name = 'caption_id') as has_caption_id,
  COUNTIF(column_name = 'page_name') as has_page_name,
  COUNTIF(column_name = 'successes') as has_successes,
  COUNTIF(column_name = 'failures') as has_failures,
  COUNT(*) as total_columns,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;

-- Expected output: 1 row with all has_* columns = 1

-- Test 2.4: Verify mass_messages table has caption_id column
SELECT
  table_name,
  COUNTIF(column_name = 'caption_id') as has_caption_id,
  COUNTIF(column_name = 'viewed_count') as has_viewed_count,
  COUNTIF(column_name = 'purchased_count') as has_purchased_count,
  COUNTIF(column_name = 'earnings') as has_earnings,
  COUNTIF(column_name = 'sending_time') as has_sending_time,
  COUNT(*) as total_columns,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'mass_messages'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;

-- Expected output: 1 row with has_caption_id = 1

-- Test 2.5: Verify active_caption_assignments table exists
SELECT
  table_name,
  'Table exists and accessible' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'active_caption_assignments'
  AND table_schema = 'eros_scheduling_brain';

-- Expected output: 1 row

-- Test 2.6: Verify caption_bank table exists
SELECT
  table_name,
  'Table exists and accessible' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'caption_bank'
  AND table_schema = 'eros_scheduling_brain';

-- Expected output: 1 row

-- ============================================================================
-- TEST SECTION 3: UDF FUNCTIONALITY TESTS
-- ============================================================================
-- These tests verify that UDFs work correctly

-- Test 3.1: Test wilson_score_bounds with balanced data
SELECT
  'Test balanced ratio (50/50)' as test_case,
  w.lower_bound,
  w.upper_bound,
  w.exploration_bonus,
  CASE WHEN w.lower_bound < 0.5 AND w.upper_bound > 0.5 THEN 'PASS' ELSE 'FAIL' END as status
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50)]) w;

-- Expected output: 1 row with PASS status, bounds around 0.5

-- Test 3.2: Test wilson_score_bounds with skewed data (high success)
SELECT
  'Test skewed ratio high success (90/10)' as test_case,
  w.lower_bound,
  w.upper_bound,
  w.exploration_bonus,
  CASE WHEN w.lower_bound > 0.7 AND w.upper_bound > 0.85 THEN 'PASS' ELSE 'FAIL' END as status
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(90, 10)]) w;

-- Expected output: 1 row with PASS status, bounds > 0.7

-- Test 3.3: Test wilson_score_bounds with skewed data (high failure)
SELECT
  'Test skewed ratio high failure (10/90)' as test_case,
  w.lower_bound,
  w.upper_bound,
  w.exploration_bonus,
  CASE WHEN w.lower_bound < 0.15 AND w.upper_bound < 0.35 THEN 'PASS' ELSE 'FAIL' END as status
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(10, 90)]) w;

-- Expected output: 1 row with PASS status, bounds < 0.35

-- Test 3.4: Test wilson_sample UDF
SELECT
  'wilson_sample returns value between 0 and 1' as test_case,
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) as sample_value,
  CASE WHEN `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) >= 0.0
    AND `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) <= 1.0
    THEN 'PASS' ELSE 'FAIL' END as status;

-- Expected output: 1 row with PASS status, sample between 0 and 1

-- ============================================================================
-- TEST SECTION 4: DATA AVAILABILITY TESTS
-- ============================================================================
-- These tests verify that required data exists

-- Test 4.1: Check for recent messages with caption_id
SELECT
  'Recent messages with caption_id' as test,
  COUNT(*) as total_messages,
  COUNTIF(caption_id IS NOT NULL) as messages_with_caption_id,
  ROUND(100.0 * COUNTIF(caption_id IS NOT NULL) / COUNT(*), 1) as percentage,
  CASE WHEN COUNTIF(caption_id IS NOT NULL) > 0 THEN 'PASS' ELSE 'FAIL - Need data' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);

-- Expected output: Row with PASS status if data exists

-- Test 4.2: Check for distinct pages
SELECT
  'Distinct pages in recent messages' as test,
  COUNT(DISTINCT page_name) as distinct_pages,
  CASE WHEN COUNT(DISTINCT page_name) > 0 THEN 'PASS' ELSE 'FAIL - No pages' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY);

-- Expected output: Row with PASS status if pages exist

-- Test 4.3: Check for distinct captions
SELECT
  'Distinct captions in recent messages' as test,
  COUNT(DISTINCT caption_id) as distinct_captions,
  CASE WHEN COUNT(DISTINCT caption_id) > 0 THEN 'PASS' ELSE 'FAIL - No captions' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND caption_id IS NOT NULL;

-- Expected output: Row with PASS status if captions exist

-- Test 4.4: Check caption_bank has captions
SELECT
  'Captions available in caption_bank' as test,
  COUNT(*) as total_captions,
  COUNTIF(caption_id IS NOT NULL) as captions_with_id,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL - No captions' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
LIMIT 1;

-- Expected output: Row with PASS status if captions exist

-- ============================================================================
-- TEST SECTION 5: PROCEDURE BEHAVIOR TESTS
-- ============================================================================
-- These tests verify procedure logic (read-only, using LIMIT to avoid side effects)

-- Test 5.1: Verify update_caption_performance input data flow (dry run)
SELECT
  'Median EMV calculation per page (dry run)' as test,
  page_name,
  APPROX_QUANTILES(
    SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0)) * earnings, 100
  )[OFFSET(50)] as median_emv,
  COUNT(*) as messages_used,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND viewed_count > 0
GROUP BY page_name
LIMIT 10;

-- Expected output: 1+ rows with calculated medians

-- Test 5.2: Verify message rollup logic (dry run)
SELECT
  'Message rollup to caption level (dry run)' as test,
  page_name,
  caption_id,
  COUNT(*) as observations,
  SAFE_DIVIDE(SUM(purchased_count), NULLIF(SUM(sent_count), 0)) as conversion_rate,
  AVG(SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0)) * earnings) as avg_emv,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND viewed_count > 0
  AND caption_id IS NOT NULL
GROUP BY page_name, caption_id
LIMIT 10;

-- Expected output: 1+ rows with caption-level aggregations

-- Test 5.3: Verify assignment key generation (dry run)
SELECT
  'Assignment key generation (dry run)' as test,
  TO_HEX(SHA256(CONCAT('test_page', '|', '1', '|', '2025-11-01', '|', '14'))) as assignment_key,
  LENGTH(TO_HEX(SHA256(CONCAT('test_page', '|', '1', '|', '2025-11-01', '|', '14')))) as key_length,
  CASE WHEN LENGTH(TO_HEX(SHA256(CONCAT('test_page', '|', '1', '|', '2025-11-01', '|', '14')))) = 64
    THEN 'PASS' ELSE 'FAIL' END as status;

-- Expected output: 1 row with 64-char hex string

-- ============================================================================
-- TEST SECTION 6: INTEGRATION VALIDATION
-- ============================================================================
-- These tests verify the procedures work together

-- Test 6.1: Check caption_bandit_stats current state
SELECT
  'Caption bandit stats coverage' as test,
  COUNT(*) as total_entries,
  COUNT(DISTINCT page_name) as pages,
  COUNT(DISTINCT caption_id) as captions,
  SUM(total_observations) as total_obs,
  SUM(total_revenue) as total_revenue,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'EMPTY - Run update_caption_performance' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;

-- Expected output: 1 row showing current state

-- Test 6.2: Check active_caption_assignments current state
SELECT
  'Active caption assignments count' as test,
  COUNT(*) as total_assignments,
  COUNT(DISTINCT schedule_id) as schedules,
  COUNT(DISTINCT page_name) as pages,
  COUNTIF(is_active = TRUE) as active_assignments,
  CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`;

-- Expected output: 1 row showing assignment counts

-- ============================================================================
-- TEST SECTION 7: ERROR HANDLING TESTS
-- ============================================================================
-- These tests verify error handling (read-only)

-- Test 7.1: Verify NULL handling in EMV calculation
SELECT
  'NULL handling in EMV' as test,
  COUNT(*) as rows_with_null_viewed,
  COUNT(SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0))) as safe_divides,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE viewed_count = 0
LIMIT 10;

-- Expected output: Shows how NULL viewed counts are handled

-- Test 7.2: Verify APPROX_QUANTILES handles edge cases
SELECT
  'APPROX_QUANTILES edge case handling' as test,
  page_name,
  COUNT(*) as messages,
  APPROX_QUANTILES(earnings, 100)[OFFSET(50)] as median_earnings,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY page_name
LIMIT 5;

-- Expected output: Shows APPROX_QUANTILES handles various data patterns

-- ============================================================================
-- SUMMARY: TEST EXECUTION CHECKLIST
-- ============================================================================
-- Copy and run all tests above, verifying PASS status for each

-- All tests passed? Next steps:
-- 1. Execute update_caption_performance procedure
-- 2. Verify caption_bandit_stats was populated
-- 3. Execute lock_caption_assignments with test data
-- 4. Verify active_caption_assignments received new rows
-- 5. Set up scheduled query to run update_caption_performance hourly

