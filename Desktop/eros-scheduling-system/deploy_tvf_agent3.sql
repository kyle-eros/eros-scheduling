-- TVF Deployment Agent #3
-- Deploy: analyze_day_patterns, analyze_time_windows, calculate_saturation_score TVFs
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Date: 2025-10-31

-- ============================================================================
-- 1) ANALYZE_DAY_PATTERNS TVF
-- ============================================================================
-- Purpose: Analyze message performance by day of week with statistical significance testing
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Day-of-week performance metrics with t-test approximation
-- Performance Goal: < 100ms on typical data (< 10K messages in lookback window)
-- ============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH base AS (
    SELECT
      EXTRACT(DAYOFWEEK FROM DATETIME(mm.sending_time, "America/Los_Angeles")) AS day_of_week_la,
      SAFE_DIVIDE(mm.earnings, NULLIF(mm.sent_count,0)) AS rpr,
      SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) AS conv
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
    WHERE mm.page_name = p_page_name
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
      AND mm.sent_count > 0
  ),
  by_day AS (
    SELECT
      day_of_week_la,
      COUNT(*) AS n,
      AVG(rpr) AS avg_rpr,
      STDDEV(rpr) AS sd_rpr,
      AVG(conv) AS avg_conv
    FROM base GROUP BY day_of_week_la
  ),
  overall AS (
    SELECT COUNT(*) AS n, AVG(rpr) AS avg_rpr, STDDEV(rpr) AS sd_rpr, AVG(conv) AS avg_conv FROM base
  )
  SELECT
    d.day_of_week_la,
    d.n,
    ROUND(d.avg_rpr,4) AS avg_rpr,
    ROUND(d.avg_conv,4) AS avg_conv,
    SAFE_DIVIDE( (d.avg_rpr - o.avg_rpr), SQRT(SAFE_DIVIDE(POW(d.sd_rpr,2), NULLIF(d.n,0)) + SAFE_DIVIDE(POW(o.sd_rpr,2), NULLIF(o.n,0))) ) AS t_rpr_approx,
    (ABS(SAFE_DIVIDE( (d.avg_rpr - o.avg_rpr), SQRT(SAFE_DIVIDE(POW(d.sd_rpr,2), NULLIF(d.n,0)) + SAFE_DIVIDE(POW(o.sd_rpr,2), NULLIF(o.n,0))) )) >= 1.96) AS rpr_stat_sig
  FROM by_day d CROSS JOIN overall o
  ORDER BY avg_rpr DESC
);

-- ============================================================================
-- 2) ANALYZE_TIME_WINDOWS TVF
-- ============================================================================
-- Purpose: Analyze message performance by hour and weekday/weekend type
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Hourly performance metrics with confidence scoring
-- Performance Goal: < 100ms on typical data
-- ============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH base AS (
    SELECT
      EXTRACT(HOUR FROM DATETIME(mm.sending_time, "America/Los_Angeles")) AS hour_la,
      CASE WHEN EXTRACT(DAYOFWEEK FROM DATETIME(mm.sending_time, "America/Los_Angeles")) IN (1,7)
           THEN 'Weekend' ELSE 'Weekday' END AS day_type,
      SAFE_DIVIDE(mm.earnings, NULLIF(mm.sent_count,0)) AS rpr,
      SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) AS conv
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
    WHERE mm.page_name = p_page_name
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
      AND mm.sent_count > 0
  ),
  agg AS (
    SELECT
      day_type, hour_la,
      COUNT(*) AS n,
      AVG(rpr) AS avg_rpr,
      AVG(conv) AS avg_conv
    FROM base
    GROUP BY day_type, hour_la
  )
  SELECT
    day_type, hour_la, n,
    ROUND(avg_rpr,4) AS avg_rpr,
    ROUND(avg_conv,4) AS avg_conv,
    CASE WHEN n >= 10 THEN 'HIGH_CONF' WHEN n >= 5 THEN 'MED_CONF' ELSE 'LOW_CONF' END AS confidence
  FROM agg
  ORDER BY avg_rpr DESC, n DESC
);

-- ============================================================================
-- 3) CALCULATE_SATURATION_SCORE TVF
-- ============================================================================
-- Purpose: Calculate saturation score for an account based on 90-day performance
--          Indicates messaging frequency saturation and provides volume adjustment recommendations
-- Input: page_name (STRING), account_size_tier (STRING: 'XL', 'LARGE', 'MEDIUM', 'SMALL')
-- Output: Saturation risk assessment with recommended actions
-- Performance Goal: < 200ms on typical data (high computational complexity)
-- Saturation Score: 0.0-1.0 where >= 0.6 is HIGH risk, >= 0.3 is MEDIUM risk
-- ============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score(
  p_page_name STRING,
  p_account_size_tier STRING
)
AS (
  WITH daily AS (
    SELECT
      DATE(DATETIME(sending_time, "America/Los_Angeles")) AS d_la,
      EXTRACT(DAYOFWEEK FROM DATETIME(sending_time, "America/Los_Angeles")) AS dow_la,
      SAFE_DIVIDE(viewed_count, NULLIF(sent_count,0)) AS unlock_rate,
      SAFE_DIVIDE(earnings, NULLIF(sent_count,0)) AS rpr
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE page_name = p_page_name
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  ),
  by_day AS (
    SELECT d_la, dow_la,
           AVG(unlock_rate) AS day_unlock,
           AVG(rpr) AS day_rpr
    FROM daily GROUP BY d_la, dow_la
  ),
  platform AS (
    SELECT
      DATE(DATETIME(sending_time, "America/Los_Angeles")) AS d_la,
      AVG(SAFE_DIVIDE(viewed_count, NULLIF(sent_count,0))) AS plat_unlock
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
    GROUP BY d_la
  ),
  joined AS (
    SELECT
      b.*,
      p.plat_unlock,
      CASE WHEN h.holiday_date IS NOT NULL THEN TRUE ELSE FALSE END AS is_holiday
    FROM by_day b
    LEFT JOIN platform p USING (d_la)
    LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.holiday_calendar` h
      ON h.holiday_date = b.d_la
  ),
  baselines AS (
    SELECT
      *,
      AVG(day_unlock) OVER (PARTITION BY dow_la ORDER BY d_la ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS unlock_baseline,
      AVG(day_rpr)    OVER (PARTITION BY dow_la ORDER BY d_la ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS rpr_baseline,
      AVG(plat_unlock)OVER (ORDER BY d_la ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS plat_baseline
    FROM joined
  ),
  scored AS (
    SELECT
      d_la, dow_la, is_holiday,
      day_unlock, day_rpr, unlock_baseline, rpr_baseline, plat_baseline,
      SAFE_DIVIDE(day_unlock - unlock_baseline, NULLIF(unlock_baseline,0)) AS unlock_dev,
      SAFE_DIVIDE(day_rpr    - rpr_baseline,    NULLIF(rpr_baseline,0))    AS rpr_dev,
      SAFE_DIVIDE(plat_unlock - plat_baseline,  NULLIF(plat_baseline,0))   AS plat_dev
    FROM baselines
  ),
  roll AS (
    SELECT
      *,
      SUM(CASE WHEN rpr_dev < -0.20 THEN 1 ELSE 0 END)
        OVER (ORDER BY d_la ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS consec_underperf_3d
    FROM scored
  ),
  final AS (
    SELECT
      CASE p_account_size_tier
        WHEN 'XL'    THEN 0.30 WHEN 'LARGE' THEN 0.25 WHEN 'MEDIUM' THEN 0.20 ELSE 0.15
      END
      * (CASE WHEN AVG(unlock_dev) < -0.15 THEN 1 ELSE 0 END)
      + 0.4 * (CASE WHEN AVG(rpr_dev)    < -0.20 THEN 1 ELSE 0 END)
      + 0.2 * (CASE WHEN MAX(consec_underperf_3d) >= 3 THEN 1 ELSE 0 END)
      + 0.1 * (CASE WHEN AVG(plat_dev)   < -0.20 THEN 1 ELSE 0 END)
      AS saturation_score,
      AVG(unlock_dev) AS unlock_rate_deviation,
      AVG(rpr_dev)    AS emv_deviation,
      MAX(consec_underperf_3d) AS consecutive_underperform_days,
      CASE
        WHEN AVG(plat_dev) < -0.20 THEN 'PLATFORM_HEADWIND'
        WHEN LOGICAL_OR(is_holiday)   THEN 'HOLIDAY'
        ELSE NULL
      END AS exclusion_reason
    FROM roll
  )
  SELECT
    saturation_score,
    CASE WHEN saturation_score >= 0.6 THEN 'HIGH'
         WHEN saturation_score >= 0.3 THEN 'MEDIUM'
         ELSE 'LOW' END AS risk_level,
    unlock_rate_deviation,
    emv_deviation,
    consecutive_underperform_days,
    CASE
      WHEN saturation_score >= 0.6 THEN 'CUT VOLUME 30%'
      WHEN saturation_score >= 0.3 THEN 'CUT VOLUME 15%'
      ELSE 'NO CHANGE' END AS recommended_action,
    CASE
      WHEN saturation_score >= 0.6 THEN 0.70
      WHEN saturation_score >= 0.3 THEN 0.85
      ELSE 1.00 END AS volume_adjustment_factor,
    LEAST(1.0, 0.6 + 0.4) AS confidence_score,
    exclusion_reason
  FROM final
);

-- ============================================================================
-- Deployment Verification Section
-- ============================================================================

-- Function Availability Check
-- Verify all three TVFs are deployed and available
SELECT
  routine_name,
  routine_type,
  DATE(CURRENT_TIMESTAMP()) AS deployment_date
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'analyze_day_patterns',
  'analyze_time_windows',
  'calculate_saturation_score'
)
ORDER BY routine_name;
