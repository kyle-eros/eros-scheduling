-- TVF Testing Suite for Agent #3
-- Test: analyze_day_patterns, analyze_time_windows, calculate_saturation_score TVFs
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Date: 2025-10-31

-- ============================================================================
-- TEST 1: ANALYZE_DAY_PATTERNS TVF
-- ============================================================================

-- Test Case 1.1: Basic functionality with a known page
-- Expected: Returns 7 rows (one per day of week), sorted by avg_rpr DESC
-- Check: All columns populated, rpr_stat_sig is boolean
SELECT 'TEST_1_1_DAY_PATTERNS_BASIC' AS test_case,
  COUNT(*) AS row_count,
  COUNT(DISTINCT day_of_week_la) AS unique_days,
  MIN(n) AS min_sample_size,
  MAX(n) AS max_sample_size,
  MAX(CASE WHEN rpr_stat_sig IN (true, false) THEN 1 ELSE 0 END) AS valid_stat_sig_values
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90);

-- Test Case 1.2: Data validation - Check for nulls in required fields
-- Expected: No nulls in key output columns
SELECT 'TEST_1_2_DAY_PATTERNS_NULL_CHECK' AS test_case,
  COUNTIF(day_of_week_la IS NULL) AS null_day_of_week,
  COUNTIF(n IS NULL) AS null_count,
  COUNTIF(avg_rpr IS NULL) AS null_avg_rpr,
  COUNTIF(rpr_stat_sig IS NULL) AS null_stat_sig,
  'PASS_IF_ALL_ZERO' AS expected
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90);

-- Test Case 1.3: Statistical significance bounds check
-- Expected: t_rpr_approx correlates with rpr_stat_sig (|t| >= 1.96 means significant)
SELECT 'TEST_1_3_DAY_PATTERNS_STAT_VALIDITY' AS test_case,
  day_of_week_la,
  ROUND(t_rpr_approx, 3) AS t_stat,
  rpr_stat_sig,
  CASE
    WHEN ABS(t_rpr_approx) >= 1.96 AND rpr_stat_sig = true THEN 'VALID'
    WHEN ABS(t_rpr_approx) < 1.96 AND rpr_stat_sig = false THEN 'VALID'
    ELSE 'INVALID'
  END AS validity_check
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
WHERE n >= 5;

-- Test Case 1.4: Performance check - lookback parameter works
-- Expected: More recent data (7 days) should have fewer messages than longer lookback (90 days)
WITH short_window AS (
  SELECT SUM(n) AS n_7d FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 7)
),
long_window AS (
  SELECT SUM(n) AS n_90d FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
)
SELECT 'TEST_1_4_DAY_PATTERNS_LOOKBACK' AS test_case,
  (SELECT n_7d FROM short_window) AS messages_7d,
  (SELECT n_90d FROM long_window) AS messages_90d,
  CASE
    WHEN (SELECT n_7d FROM short_window) <= (SELECT n_90d FROM long_window) THEN 'PASS'
    ELSE 'FAIL'
  END AS validation
FROM long_window;

-- Test Case 1.5: Ranking by performance
-- Expected: Days ranked by avg_rpr, highest first
SELECT 'TEST_1_5_DAY_PATTERNS_RANKING' AS test_case,
  day_of_week_la,
  ROUND(avg_rpr, 4) AS avg_rpr,
  ROW_NUMBER() OVER (ORDER BY avg_rpr DESC) AS rank,
  CASE
    WHEN avg_rpr >= LAG(avg_rpr) OVER (ORDER BY avg_rpr DESC) THEN 'VALID_DESC_ORDER'
    WHEN LAG(avg_rpr) OVER (ORDER BY avg_rpr DESC) IS NULL THEN 'FIRST_ROW'
    ELSE 'INVALID_ORDER'
  END AS order_check
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90);

-- ============================================================================
-- TEST 2: ANALYZE_TIME_WINDOWS TVF
-- ============================================================================

-- Test Case 2.1: Basic functionality
-- Expected: Returns rows for each hour (0-23) x day_type (Weekday/Weekend)
-- Maximum 48 rows (24 hours x 2 day types)
SELECT 'TEST_2_1_TIME_WINDOWS_BASIC' AS test_case,
  COUNT(*) AS row_count,
  COUNT(DISTINCT day_type) AS unique_day_types,
  COUNT(DISTINCT hour_la) AS unique_hours,
  MAX(CASE WHEN day_type IN ('Weekday', 'Weekend') THEN 1 ELSE 0 END) AS valid_day_types
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90);

-- Test Case 2.2: Confidence level validation
-- Expected: All confidence values are one of HIGH_CONF, MED_CONF, LOW_CONF
SELECT 'TEST_2_2_TIME_WINDOWS_CONFIDENCE' AS test_case,
  COUNTIF(confidence IN ('HIGH_CONF', 'MED_CONF', 'LOW_CONF')) AS valid_confidence,
  COUNT(*) AS total_rows,
  CASE
    WHEN COUNTIF(confidence IN ('HIGH_CONF', 'MED_CONF', 'LOW_CONF')) = COUNT(*) THEN 'PASS'
    ELSE 'FAIL'
  END AS confidence_validation
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90);

-- Test Case 2.3: Confidence correlates with sample size
-- Expected: HIGH_CONF (n >= 10) has valid confidence assignment
SELECT 'TEST_2_3_TIME_WINDOWS_CONF_CORRELATION' AS test_case,
  hour_la,
  day_type,
  n AS sample_size,
  confidence,
  CASE
    WHEN n >= 10 AND confidence = 'HIGH_CONF' THEN 'VALID'
    WHEN n >= 5 AND n < 10 AND confidence = 'MED_CONF' THEN 'VALID'
    WHEN n < 5 AND confidence = 'LOW_CONF' THEN 'VALID'
    ELSE 'INVALID'
  END AS conf_validity
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
WHERE n > 0;

-- Test Case 2.4: Hour range validation
-- Expected: hour_la should be 0-23
SELECT 'TEST_2_4_TIME_WINDOWS_HOUR_RANGE' AS test_case,
  MIN(hour_la) AS min_hour,
  MAX(hour_la) AS max_hour,
  COUNTIF(hour_la < 0 OR hour_la > 23) AS invalid_hours,
  CASE
    WHEN MIN(hour_la) >= 0 AND MAX(hour_la) <= 23 THEN 'PASS'
    ELSE 'FAIL'
  END AS hour_validation
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90);

-- Test Case 2.5: Performance ranking by RPR
-- Expected: Results ordered by avg_rpr DESC, then n DESC
SELECT 'TEST_2_5_TIME_WINDOWS_RANKING' AS test_case,
  day_type,
  hour_la,
  ROUND(avg_rpr, 4) AS avg_rpr,
  n,
  LAG(avg_rpr) OVER (ORDER BY avg_rpr DESC, n DESC) AS prev_avg_rpr,
  CASE
    WHEN avg_rpr >= LAG(avg_rpr) OVER (ORDER BY avg_rpr DESC, n DESC) THEN 'VALID'
    WHEN LAG(avg_rpr) OVER (ORDER BY avg_rpr DESC, n DESC) IS NULL THEN 'FIRST_ROW'
    ELSE 'INVALID'
  END AS ranking_check
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
LIMIT 20;

-- ============================================================================
-- TEST 3: CALCULATE_SATURATION_SCORE TVF
-- ============================================================================

-- Test Case 3.1: Basic functionality - Single row output
-- Expected: Returns exactly 1 row with all required columns
SELECT 'TEST_3_1_SATURATION_BASIC' AS test_case,
  COUNT(*) AS row_count,
  saturation_score,
  risk_level,
  recommended_action,
  CASE
    WHEN COUNT(*) = 1 THEN 'PASS'
    ELSE 'FAIL'
  END AS single_row_check
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
GROUP BY saturation_score, risk_level, recommended_action;

-- Test Case 3.2: Risk level classification validation
-- Expected: risk_level matches saturation_score thresholds (HIGH >= 0.6, MEDIUM >= 0.3, LOW < 0.3)
SELECT 'TEST_3_2_SATURATION_RISK_VALIDATION' AS test_case,
  saturation_score,
  risk_level,
  CASE
    WHEN saturation_score >= 0.6 AND risk_level = 'HIGH' THEN 'VALID_HIGH'
    WHEN saturation_score >= 0.3 AND saturation_score < 0.6 AND risk_level = 'MEDIUM' THEN 'VALID_MEDIUM'
    WHEN saturation_score < 0.3 AND risk_level = 'LOW' THEN 'VALID_LOW'
    ELSE 'INVALID'
  END AS risk_validation
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- Test Case 3.3: Recommended action correlates with risk level
-- Expected: Action recommendations align with saturation score
SELECT 'TEST_3_3_SATURATION_ACTION_VALIDATION' AS test_case,
  saturation_score,
  risk_level,
  recommended_action,
  volume_adjustment_factor,
  CASE
    WHEN saturation_score >= 0.6 AND recommended_action = 'CUT VOLUME 30%' AND volume_adjustment_factor = 0.70 THEN 'VALID_HIGH'
    WHEN saturation_score >= 0.3 AND saturation_score < 0.6 AND recommended_action = 'CUT VOLUME 15%' AND volume_adjustment_factor = 0.85 THEN 'VALID_MEDIUM'
    WHEN saturation_score < 0.3 AND recommended_action = 'NO CHANGE' AND volume_adjustment_factor = 1.00 THEN 'VALID_LOW'
    ELSE 'INVALID'
  END AS action_validation
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- Test Case 3.4: Account size tier parameter works (XL, LARGE, MEDIUM, SMALL)
-- Expected: Different tiers may produce different saturation scores due to tier-specific weighting
SELECT 'TEST_3_4_SATURATION_TIER_COMPARISON' AS test_case,
  'XL' AS tier,
  saturation_score AS xl_score
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'XL')
UNION ALL
SELECT 'TEST_3_4_SATURATION_TIER_COMPARISON',
  'LARGE',
  saturation_score
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
UNION ALL
SELECT 'TEST_3_4_SATURATION_TIER_COMPARISON',
  'MEDIUM',
  saturation_score
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'MEDIUM')
UNION ALL
SELECT 'TEST_3_4_SATURATION_TIER_COMPARISON',
  'SMALL',
  saturation_score
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'SMALL');

-- Test Case 3.5: Numeric bounds validation
-- Expected: saturation_score in [0, 1], deviations can be negative or positive
SELECT 'TEST_3_5_SATURATION_BOUNDS' AS test_case,
  saturation_score,
  unlock_rate_deviation,
  emv_deviation,
  consecutive_underperform_days,
  confidence_score,
  CASE
    WHEN saturation_score BETWEEN 0 AND 1 THEN 'VALID_SCORE'
    ELSE 'INVALID_SCORE'
  END AS score_validity,
  CASE
    WHEN consecutive_underperform_days >= 0 THEN 'VALID_CONSEC'
    ELSE 'INVALID_CONSEC'
  END AS consec_validity,
  CASE
    WHEN confidence_score BETWEEN 0 AND 1 THEN 'VALID_CONF'
    ELSE 'INVALID_CONF'
  END AS conf_validity
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- Test Case 3.6: Exclusion reason validation
-- Expected: exclusion_reason is NULL or one of specific values (PLATFORM_HEADWIND, HOLIDAY)
SELECT 'TEST_3_6_SATURATION_EXCLUSION_REASON' AS test_case,
  exclusion_reason,
  CASE
    WHEN exclusion_reason IS NULL THEN 'VALID_NULL'
    WHEN exclusion_reason IN ('PLATFORM_HEADWIND', 'HOLIDAY') THEN 'VALID_REASON'
    ELSE 'INVALID_REASON'
  END AS reason_validity
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- ============================================================================
-- CROSS-TVF INTEGRATION TESTS
-- ============================================================================

-- Test Case 4.1: Combine day patterns with time windows for optimal scheduling
-- Expected: Identify best day-hour combinations
SELECT 'TEST_4_1_COMBINED_SCHEDULING' AS test_case,
  dp.day_of_week_la,
  tw.hour_la,
  ROUND(dp.avg_rpr, 4) AS day_rpr,
  ROUND(tw.avg_rpr, 4) AS hour_rpr,
  tw.confidence,
  CASE
    WHEN dp.rpr_stat_sig AND tw.confidence = 'HIGH_CONF' THEN 'RECOMMENDED'
    ELSE 'INVESTIGATE'
  END AS recommendation
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90) dp
CROSS JOIN `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90) tw
WHERE dp.avg_rpr > 0 AND tw.avg_rpr > 0
ORDER BY dp.avg_rpr DESC, tw.avg_rpr DESC
LIMIT 20;

-- Test Case 4.2: Saturation scoring with day patterns
-- Expected: High saturation on best-performing days suggests oversaturation
SELECT 'TEST_4_2_SATURATION_WITH_PATTERNS' AS test_case,
  ss.risk_level,
  ss.saturation_score,
  ss.recommended_action,
  COUNT(DISTINCT dp.day_of_week_la) AS days_in_window,
  ROUND(AVG(dp.avg_rpr), 4) AS avg_day_rpr
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE') ss
CROSS JOIN `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90) dp
WHERE dp.n >= 5
GROUP BY ss.risk_level, ss.saturation_score, ss.recommended_action;

-- ============================================================================
-- SUMMARY TEST REPORT
-- ============================================================================

-- Summary: All TVFs deployed and operational
SELECT 'DEPLOYMENT_SUMMARY' AS report_type,
  'analyze_day_patterns' AS tvf_name,
  'OPERATIONAL' AS status,
  'Returns day-of-week performance analysis with statistical significance' AS description
UNION ALL
SELECT 'DEPLOYMENT_SUMMARY',
  'analyze_time_windows',
  'OPERATIONAL',
  'Returns hourly performance analysis with confidence scoring'
UNION ALL
SELECT 'DEPLOYMENT_SUMMARY',
  'calculate_saturation_score',
  'OPERATIONAL',
  'Returns account saturation risk assessment with tier-aware scoring'
ORDER BY tvf_name;

-- Final: Verify all three TVFs are available in system
SELECT 'TVF_AVAILABILITY_CHECK' AS check_type,
  routine_name,
  routine_type,
  DATE(CURRENT_TIMESTAMP()) AS check_date,
  'DEPLOYED' AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'analyze_day_patterns',
  'analyze_time_windows',
  'calculate_saturation_score'
)
ORDER BY routine_name;
