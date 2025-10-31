-- TVF Reference Guide - Agent #3
-- Table-Valued Functions: analyze_day_patterns, analyze_time_windows, calculate_saturation_score
-- Deployment Date: 2025-10-31
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain

-- ============================================================================
-- TVF #1: ANALYZE_DAY_PATTERNS
-- ============================================================================
-- Purpose: Identify which days of the week perform best for a creator
-- Outputs statistical significance test for each day
-- Returns 7 rows (one per day of week, 1=Sunday through 7=Saturday)

-- BASIC USAGE: Find best-performing days
SELECT
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
  ROUND(avg_rpr * 1000000, 2) AS rpr_per_1m,
  ROUND(avg_conv * 100, 2) AS conversion_pct,
  ROUND(t_rpr_approx, 2) AS t_stat,
  CASE WHEN rpr_stat_sig THEN 'SIGNIFICANT' ELSE 'NOT_SIG' END AS statistical_significance
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
ORDER BY avg_rpr DESC;

-- USE CASE 1: Find days with statistically significant outperformance
-- Goal: Identify days proven to outperform the average
SELECT
  CASE day_of_week_la
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS day_name,
  n AS sample_size,
  ROUND(avg_rpr, 6) AS rpr,
  ROUND(avg_conv, 4) AS conversion_rate,
  ROUND(t_rpr_approx, 2) AS t_statistic,
  'PROVEN_PERFORMER' AS classification
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
WHERE rpr_stat_sig = true AND n >= 50;

-- USE CASE 2: Identify underperforming days to reduce volume
-- Goal: Find days with worse performance to cut back messaging
SELECT
  CASE day_of_week_la
    WHEN 1 THEN 'Sunday'
    WHEN 2 THEN 'Monday'
    WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday'
    WHEN 5 THEN 'Thursday'
    WHEN 6 THEN 'Friday'
    WHEN 7 THEN 'Saturday'
  END AS day_name,
  n AS sample_size,
  ROUND(avg_rpr, 6) AS rpr,
  ROUND(avg_conv, 4) AS conversion_rate,
  CASE
    WHEN avg_rpr > (SELECT AVG(avg_rpr) FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)) THEN 'ABOVE_AVERAGE'
    WHEN avg_rpr < (SELECT AVG(avg_rpr) FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)) THEN 'BELOW_AVERAGE'
    ELSE 'AT_AVERAGE'
  END AS performance_category
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
ORDER BY avg_rpr ASC;

-- USE CASE 3: Monitoring trend by lookback window
-- Goal: Compare recent (7 days) vs historical (90 days) performance
WITH recent AS (
  SELECT
    day_of_week_la,
    ROUND(AVG(avg_rpr), 6) AS recent_rpr
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 7)
  GROUP BY day_of_week_la
),
historical AS (
  SELECT
    day_of_week_la,
    ROUND(AVG(avg_rpr), 6) AS historical_rpr
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
  GROUP BY day_of_week_la
)
SELECT
  r.day_of_week_la,
  r.recent_rpr,
  h.historical_rpr,
  ROUND(SAFE_DIVIDE(r.recent_rpr - h.historical_rpr, NULLIF(h.historical_rpr, 0)) * 100, 2) AS trend_pct
FROM recent r
LEFT JOIN historical h USING (day_of_week_la)
ORDER BY trend_pct DESC;

-- ============================================================================
-- TVF #2: ANALYZE_TIME_WINDOWS
-- ============================================================================
-- Purpose: Identify which hours and day types (weekday/weekend) perform best
-- Combines hourly analysis with weekday/weekend patterns
-- Returns up to 48 rows (24 hours x 2 day types)
-- Confidence levels: HIGH_CONF (n >= 10), MED_CONF (n >= 5), LOW_CONF (n < 5)

-- BASIC USAGE: Find best hours to send messages
SELECT
  day_type,
  LPAD(CAST(hour_la AS STRING), 2, '0') AS hour_24,
  n AS msg_count,
  ROUND(avg_rpr * 1000000, 2) AS rpr_per_1m,
  ROUND(avg_conv * 100, 2) AS conversion_pct,
  CASE
    WHEN confidence = 'HIGH_CONF' THEN '***'
    WHEN confidence = 'MED_CONF' THEN '**'
    ELSE '*'
  END AS confidence_marker
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
ORDER BY avg_rpr DESC;

-- USE CASE 1: Identify prime sending windows by day type
-- Goal: Find optimal hours for weekday vs weekend sends
WITH ranked AS (
  SELECT
    day_type,
    hour_la,
    n,
    avg_rpr,
    avg_conv,
    confidence,
    ROW_NUMBER() OVER (PARTITION BY day_type ORDER BY avg_rpr DESC) AS rank
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
  WHERE confidence IN ('HIGH_CONF', 'MED_CONF')
)
SELECT
  day_type,
  hour_la,
  n AS sample_size,
  ROUND(avg_rpr, 6) AS rpr,
  ROUND(avg_conv, 4) AS conversion_rate,
  confidence,
  'TOP_PERFORMER' AS status
FROM ranked
WHERE rank <= 5
ORDER BY day_type, rank;

-- USE CASE 2: Avoid low-performance hours
-- Goal: Find hours with poor performance that should be minimized
SELECT
  day_type,
  LPAD(CAST(hour_la AS STRING), 2, '0') AS hour,
  n,
  ROUND(avg_rpr, 6) AS rpr,
  ROUND(avg_conv, 4) AS conversion_rate,
  confidence,
  CASE
    WHEN confidence = 'LOW_CONF' THEN 'INSUFFICIENT_DATA'
    WHEN avg_rpr < 0.0001 THEN 'POOR_PERFORMER'
    ELSE 'MONITOR'
  END AS action
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
WHERE n >= 5
ORDER BY avg_rpr ASC;

-- USE CASE 3: Confidence-weighted recommendations
-- Goal: Only recommend high-confidence sending windows
SELECT
  day_type,
  LPAD(CAST(hour_la AS STRING), 2, '0') AS hour_24,
  n AS sample_size,
  ROUND(avg_rpr, 6) AS rpr,
  confidence,
  CASE
    WHEN confidence = 'HIGH_CONF' AND avg_rpr > 0.0003 THEN 'RECOMMENDED'
    WHEN confidence = 'HIGH_CONF' THEN 'MONITOR'
    WHEN confidence = 'MED_CONF' THEN 'TENTATIVE'
    ELSE 'INSUFFICIENT_DATA'
  END AS recommendation
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
WHERE n >= 5
ORDER BY
  CASE recommendation
    WHEN 'RECOMMENDED' THEN 1
    WHEN 'MONITOR' THEN 2
    WHEN 'TENTATIVE' THEN 3
    ELSE 4
  END,
  avg_rpr DESC;

-- ============================================================================
-- TVF #3: CALCULATE_SATURATION_SCORE
-- ============================================================================
-- Purpose: Assess account-level messaging saturation risk
-- Looks at 90-day performance trends to detect audience fatigue
-- Returns 1 row with comprehensive saturation assessment
-- Accounts for: unlock rate deviation, RPR deviation, consecutive underperformance, platform headwinds
-- Account Tiers: XL (0.30 unlock weight), LARGE (0.25), MEDIUM (0.20), SMALL (0.15)

-- BASIC USAGE: Check current saturation status
SELECT
  saturation_score,
  risk_level,
  recommended_action,
  ROUND(unlock_rate_deviation * 100, 2) AS unlock_deviation_pct,
  ROUND(emv_deviation * 100, 2) AS emv_deviation_pct,
  consecutive_underperform_days AS consec_bad_days,
  volume_adjustment_factor AS recommended_volume_multiplier,
  CASE
    WHEN exclusion_reason IS NOT NULL THEN 'EXCLUDE_FROM_ANALYSIS: ' || exclusion_reason
    ELSE 'NORMAL_CONDITIONS'
  END AS environment_status
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- USE CASE 1: Volume reduction recommendations
-- Goal: Get actionable volume adjustment advice
SELECT
  'VOLUME_ADJUSTMENT_PLAN' AS plan_type,
  saturation_score,
  risk_level,
  recommended_action,
  CASE
    WHEN saturation_score >= 0.6 THEN CONCAT('Reduce messaging by 30%. Score: ', CAST(ROUND(saturation_score, 2) AS STRING), ' (HIGH RISK)')
    WHEN saturation_score >= 0.3 THEN CONCAT('Reduce messaging by 15%. Score: ', CAST(ROUND(saturation_score, 2) AS STRING), ' (MEDIUM RISK)')
    ELSE CONCAT('No change needed. Score: ', CAST(ROUND(saturation_score, 2) AS STRING), ' (LOW RISK)')
  END AS detailed_action,
  volume_adjustment_factor,
  confidence_score
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- USE CASE 2: Compare saturation across account tiers
-- Goal: Understand how tier affects saturation assessment
SELECT
  'TIER_COMPARISON' AS analysis,
  tier,
  ROUND(saturation_score, 3) AS saturation,
  risk_level,
  recommended_action,
  volume_adjustment_factor
FROM (
  SELECT 'XL' AS tier, saturation_score, risk_level, recommended_action, volume_adjustment_factor
  FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'XL')
  UNION ALL
  SELECT 'LARGE' AS tier, saturation_score, risk_level, recommended_action, volume_adjustment_factor
  FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
  UNION ALL
  SELECT 'MEDIUM' AS tier, saturation_score, risk_level, recommended_action, volume_adjustment_factor
  FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'MEDIUM')
  UNION ALL
  SELECT 'SMALL' AS tier, saturation_score, risk_level, recommended_action, volume_adjustment_factor
  FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'SMALL')
)
ORDER BY saturation_score DESC;

-- USE CASE 3: Diagnostic - understand saturation components
-- Goal: Break down which factors contribute to saturation
SELECT
  saturation_score,
  ROUND(unlock_rate_deviation * 100, 2) AS unlock_rate_deviation_pct,
  ROUND(emv_deviation * 100, 2) AS emv_deviation_pct,
  consecutive_underperform_days,
  confidence_score,
  CASE
    WHEN emv_deviation < -0.20 THEN 'EMV_DEGRADATION'
    WHEN unlock_rate_deviation < -0.15 THEN 'UNLOCK_DECLINE'
    WHEN consecutive_underperform_days >= 3 THEN 'SUSTAINED_UNDERPERFORMANCE'
    ELSE 'HEALTHY_METRICS'
  END AS primary_concern,
  exclusion_reason
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE');

-- ============================================================================
-- CROSS-TVF INTEGRATION PATTERNS
-- ============================================================================

-- PATTERN 1: Optimal Scheduling Matrix
-- Combine day patterns with time windows for comprehensive scheduling
-- Goal: Find the best day-hour combinations
WITH day_perf AS (
  SELECT
    day_of_week_la,
    CASE day_of_week_la WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday'
      WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' ELSE 'Saturday' END AS day_name,
    ROUND(avg_rpr, 6) AS day_rpr,
    rpr_stat_sig
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
),
hour_perf AS (
  SELECT
    CASE WHEN day_of_week_la IN (1, 7) THEN day_of_week_la ELSE NULL END AS weekend_dow,
    CASE WHEN day_of_week_la NOT IN (1, 7) THEN day_of_week_la ELSE NULL END AS weekday_dow,
    day_type,
    hour_la,
    ROUND(avg_rpr, 6) AS hour_rpr,
    confidence
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
)
SELECT
  d.day_name,
  h.hour_la,
  ROUND(d.day_rpr + h.hour_rpr, 6) AS combined_expected_rpr,
  d.rpr_stat_sig AS day_significance,
  h.confidence AS hour_confidence,
  CASE
    WHEN d.rpr_stat_sig AND h.confidence = 'HIGH_CONF' THEN 'PRIME_SLOT'
    WHEN h.confidence = 'HIGH_CONF' THEN 'GOOD_SLOT'
    ELSE 'MONITOR'
  END AS recommendation
FROM day_perf d
CROSS JOIN hour_perf h
WHERE (h.weekend_dow = d.day_of_week_la OR h.weekday_dow = d.day_of_week_la)
ORDER BY combined_expected_rpr DESC
LIMIT 20;

-- PATTERN 2: Saturation-Aware Scheduling
-- Adjust message volume based on saturation while maintaining optimal timing
-- Goal: Smart volume and timing strategy combined
WITH saturation_data AS (
  SELECT
    saturation_score,
    risk_level,
    volume_adjustment_factor,
    CASE
      WHEN saturation_score >= 0.6 THEN '30% REDUCTION'
      WHEN saturation_score >= 0.3 THEN '15% REDUCTION'
      ELSE 'MAINTAIN'
    END AS volume_action
  FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
),
optimal_windows AS (
  SELECT
    CASE day_of_week_la WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday'
      WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' ELSE 'Saturday' END AS day_name,
    day_of_week_la,
    ROUND(avg_rpr, 6) AS day_rpr,
    rpr_stat_sig
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
  WHERE rpr_stat_sig = true
)
SELECT
  s.risk_level,
  s.volume_action,
  s.volume_adjustment_factor,
  o.day_name,
  o.day_rpr,
  CONCAT(
    'Send on ',
    o.day_name,
    ' with ',
    CAST(ROUND(s.volume_adjustment_factor * 100, 0) AS STRING),
    '% of normal volume'
  ) AS strategy
FROM saturation_data s
CROSS JOIN optimal_windows o
LIMIT 7;

-- ============================================================================
-- MONITORING & ALERTING QUERIES
-- ============================================================================

-- Alert: Saturation threshold exceeded
SELECT
  'SATURATION_ALERT' AS alert_type,
  saturation_score,
  risk_level,
  CASE
    WHEN saturation_score >= 0.6 THEN 'CRITICAL'
    WHEN saturation_score >= 0.4 THEN 'WARNING'
    ELSE 'INFO'
  END AS severity,
  recommended_action,
  CONCAT('Account saturation is ', risk_level, '. Recommended: ', recommended_action) AS alert_message
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
WHERE saturation_score >= 0.3;

-- Diagnostic: Day pattern significance
SELECT
  'DAY_PATTERN_SUMMARY' AS analysis,
  COUNTIF(rpr_stat_sig = true) AS significant_days,
  COUNT(*) AS total_days,
  ROUND(AVG(avg_rpr), 6) AS overall_avg_rpr,
  MAX(avg_rpr) AS best_day_rpr,
  MIN(avg_rpr) AS worst_day_rpr
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90);

-- Diagnostic: Optimal hours summary
SELECT
  'TIME_WINDOW_SUMMARY' AS analysis,
  COUNTIF(confidence = 'HIGH_CONF') AS high_conf_windows,
  COUNTIF(confidence = 'MED_CONF') AS med_conf_windows,
  COUNTIF(confidence = 'LOW_CONF') AS low_conf_windows,
  ROUND(AVG(CASE WHEN confidence = 'HIGH_CONF' THEN avg_rpr END), 6) AS high_conf_avg_rpr,
  MAX(avg_rpr) AS best_hour_rpr
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90);
