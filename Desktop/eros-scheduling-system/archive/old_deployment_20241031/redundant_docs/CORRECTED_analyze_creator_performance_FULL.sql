-- =============================================================================
-- CORRECTED DEPLOYMENT: ANALYZE_CREATOR_PERFORMANCE - COMPLETE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Complete creator performance analysis with ALL TVFs and timezone fixes
-- Created: October 31, 2025
-- Status: PRODUCTION-READY (pending testing)
-- =============================================================================
--
-- CHANGES FROM ORIGINAL:
-- 1. All 7 TVFs consolidated into single file
-- 2. Timezone consistency: All CURRENT_TIMESTAMP() → CURRENT_TIMESTAMP('America/Los_Angeles')
-- 3. Added dependency validation queries
-- 4. Added comprehensive comments
-- =============================================================================

-- =============================================================================
-- PRE-DEPLOYMENT VALIDATION
-- =============================================================================

-- Validate required UDFs exist
SELECT
  'DEPENDENCY_CHECK_UDFS' AS validation_step,
  COUNT(*) AS udf_count,
  CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('wilson_score_bounds', 'caption_key')
  AND routine_type = 'SCALAR_FUNCTION';
-- EXPECTED: 2 UDFs (wilson_score_bounds, caption_key)

-- Validate required tables exist
SELECT
  'DEPENDENCY_CHECK_TABLES' AS validation_step,
  COUNT(*) AS table_count,
  CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN (
  'mass_messages',
  'caption_bank_enriched',
  'creator_content_inventory',
  'holiday_calendar',
  'etl_job_runs'
);
-- EXPECTED: 5 tables

-- =============================================================================
-- TVF #1: CLASSIFY_ACCOUNT_SIZE
-- =============================================================================
-- Purpose: Classify creator accounts into size tiers with metrics
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Account size tier classification with audience and revenue metrics
-- Performance Goal: < 100ms
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.classify_account_size(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH page_stats AS (
    SELECT
      page_name,
      COUNT(DISTINCT DATE(sending_time, 'America/Los_Angeles')) AS active_days,
      COUNT(*) AS total_messages,
      SUM(viewed_count) AS total_views,
      AVG(viewed_count) AS avg_views_per_msg,
      APPROX_QUANTILES(viewed_count, 100)[OFFSET(50)] AS median_views,
      SUM(earnings) AS total_revenue,
      SUM(purchased_count) AS total_purchases,
      SAFE_DIVIDE(SUM(purchased_count), NULLIF(SUM(viewed_count), 0)) AS overall_conversion
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE page_name = p_page_name
      -- FIXED: Use LA timezone for consistent lookback
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
      AND viewed_count > 0
    GROUP BY page_name
  ),
  with_tiers AS (
    SELECT
      page_name,
      total_revenue,
      SAFE_DIVIDE(total_revenue, NULLIF(active_days, 0)) AS daily_revenue_avg,
      CAST(AVG(avg_views_per_msg) AS INT64) AS daily_ppv_target_min,
      CAST(SAFE_DIVIDE(avg_views_per_msg * 1.5, 1) AS INT64) AS daily_ppv_target_max,
      CAST(SAFE_DIVIDE(median_views * 0.8, 1) AS INT64) AS daily_bump_target,
      CASE
        WHEN total_revenue < 5000 THEN 'MICRO'
        WHEN total_revenue < 25000 THEN 'SMALL'
        WHEN total_revenue < 100000 THEN 'MEDIUM'
        WHEN total_revenue < 500000 THEN 'LARGE'
        ELSE 'MEGA'
      END AS size_tier,
      CAST(AVG(median_views) AS INT64) AS avg_audience,
      total_revenue AS total_revenue_period,
      CAST(GREATEST(5, SAFE_DIVIDE(median_views, 12)) AS INT64) AS min_ppv_gap_minutes,
      CASE
        WHEN total_revenue < 25000 THEN 0.15
        WHEN total_revenue < 100000 THEN 0.20
        WHEN total_revenue < 500000 THEN 0.25
        ELSE 0.30
      END AS saturation_tolerance
    FROM page_stats
  )
  SELECT
    STRUCT(
      size_tier,
      avg_audience,
      total_revenue_period,
      daily_ppv_target_min,
      daily_ppv_target_max,
      daily_bump_target,
      min_ppv_gap_minutes,
      saturation_tolerance
    ) AS account_size_classification
  FROM with_tiers
);

-- =============================================================================
-- TVF #2: ANALYZE_BEHAVIORAL_SEGMENTS
-- =============================================================================
-- Purpose: Analyze creator behavioral segments with performance metrics
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Segment classification with RPR and conversion analytics
-- Performance Goal: < 100ms
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_behavioral_segments(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH enriched_messages AS (
    SELECT
      page_name,
      SAFE_DIVIDE(earnings, NULLIF(sent_count, 0)) AS rpr,
      SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0)) AS conversion,
      price,
      sent_count,
      viewed_count,
      purchased_count,
      earnings
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE page_name = p_page_name
      -- FIXED: Use LA timezone for consistent lookback
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
      AND viewed_count > 0 AND sent_count > 0
  ),
  segment_stats AS (
    SELECT
      COUNT(*) AS msg_count,
      COUNT(DISTINCT SAFE_DIVIDE(CAST(EXTRACT(DAY FROM CURRENT_TIMESTAMP('America/Los_Angeles')) AS INT64), 7)) AS cohort_size,
      AVG(rpr) AS avg_rpr,
      AVG(conversion) AS avg_conv,
      STDDEV(rpr) AS sd_rpr,
      STDDEV(conversion) AS sd_conv,
      CORR(price, rpr) AS rpr_price_slope,
      CORR(price, conversion) AS price_elasticity,
      ABS(CORR(price, conversion)) AS price_conv_correlation,
      APPROX_QUANTILES(conversion, 100)[OFFSET(50)] AS median_conversion,
      -LOG10(SAFE_DIVIDE(MAX(CASE WHEN conversion > 0 THEN conversion ELSE NULL END),
                         NULLIF(MIN(CASE WHEN conversion > 0 THEN conversion ELSE NULL END), 0)) + 0.00001) AS category_entropy,
      SAFE_DIVIDE(SUM(viewed_count), NULLIF(SUM(sent_count), 0)) AS segment_view_rate
    FROM enriched_messages
  ),
  final_segment AS (
    SELECT
      CASE
        WHEN msg_count < 20 THEN 'EXPLORATORY'
        WHEN avg_rpr < 0.5 THEN 'BUDGET'
        WHEN avg_rpr < 2.0 THEN 'STANDARD'
        WHEN avg_rpr < 5.0 THEN 'PREMIUM'
        ELSE 'LUXURY'
      END AS segment_label,
      avg_rpr,
      avg_conv,
      rpr_price_slope,
      COALESCE(price_conv_correlation, 0.0) AS rpr_price_corr,
      price_elasticity AS conv_price_elasticity_proxy,
      COALESCE(category_entropy, 0.0) AS category_entropy,
      msg_count AS sample_size
    FROM segment_stats
  )
  SELECT
    segment_label,
    ROUND(avg_rpr, 6) AS avg_rpr,
    ROUND(avg_conv, 4) AS avg_conv,
    ROUND(COALESCE(rpr_price_slope, 0.0), 6) AS rpr_price_slope,
    ROUND(COALESCE(rpr_price_corr, 0.0), 4) AS rpr_price_corr,
    ROUND(COALESCE(conv_price_elasticity_proxy, 0.0), 4) AS conv_price_elasticity_proxy,
    ROUND(category_entropy, 4) AS category_entropy,
    sample_size
  FROM final_segment
);

-- =============================================================================
-- TVF #3: ANALYZE_TRIGGER_PERFORMANCE
-- =============================================================================
-- Purpose: Analyze psychological triggers for message performance
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Trigger analysis with statistical significance testing
-- Performance Goal: < 100ms
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH enriched AS (
    SELECT
      cb.psychological_trigger,
      SAFE_DIVIDE(mm.earnings, NULLIF(mm.sent_count,0)) AS rpr,
      SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) AS conv,
      mm.purchased_count AS successes,
      mm.viewed_count    AS trials
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
    JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank_enriched` cb
      ON `of-scheduler-proj.eros_scheduling_brain`.caption_key(mm.message) = cb.caption_key
    WHERE mm.page_name = p_page_name
      -- FIXED: Use LA timezone for consistent lookback
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
      AND mm.viewed_count > 0 AND mm.sent_count > 0
  ),
  per_trig AS (
    SELECT
      psychological_trigger,
      COUNT(*) AS msg_count,
      SUM(successes) AS succ,
      SUM(trials)    AS tot,
      AVG(rpr)  AS avg_rpr,
      STDDEV(rpr) AS sd_rpr,
      AVG(conv) AS avg_conv
    FROM enriched
    GROUP BY psychological_trigger
  ),
  baseline AS (
    SELECT
      COUNT(*) AS n,
      SUM(successes) AS succ,
      SUM(trials)    AS tot,
      AVG(rpr) AS avg_rpr,
      STDDEV(rpr) AS sd_rpr,
      AVG(conv) AS avg_conv
    FROM enriched
  ),
  lifted AS (
    SELECT
      t.psychological_trigger,
      t.msg_count,
      t.avg_rpr,
      t.avg_conv,
      SAFE_DIVIDE(t.avg_rpr - b.avg_rpr, NULLIF(b.avg_rpr,0)) AS rpr_lift,
      SAFE_DIVIDE(t.avg_conv - b.avg_conv, NULLIF(b.avg_conv,0)) AS conv_lift,
      SAFE_DIVIDE( (SAFE_DIVIDE(t.succ,t.tot) - SAFE_DIVIDE(b.succ,b.tot)),
                   SQRT(SAFE_DIVIDE(SAFE_DIVIDE(b.succ+b.succ, (b.tot+b.tot)) * (1 - SAFE_DIVIDE(b.succ+b.succ, (b.tot+b.tot))),1)
                        * (1/NULLIF(t.tot,0) + 1/NULLIF(b.tot,0)) ) ) AS z_conv_approx,
      SAFE_DIVIDE( (t.avg_rpr - b.avg_rpr),
                   SQRT(SAFE_DIVIDE(POW(t.sd_rpr,2), NULLIF(t.msg_count,0)) + SAFE_DIVIDE(POW(b.sd_rpr,2), NULLIF(b.n,0))) ) AS t_rpr_approx,
      (`of-scheduler-proj.eros_scheduling_brain`.wilson_score_bounds(CAST(t.succ AS INT64), CAST(t.tot AS INT64))).lower_bound AS conv_ci_lower,
      (`of-scheduler-proj.eros_scheduling_brain`.wilson_score_bounds(CAST(t.succ AS INT64), CAST(t.tot AS INT64))).upper_bound AS conv_ci_upper
    FROM per_trig t CROSS JOIN baseline b
  )
  SELECT
    psychological_trigger,
    msg_count,
    ROUND(avg_rpr, 4) AS avg_rpr,
    ROUND(avg_conv,4) AS avg_conv,
    ROUND(rpr_lift * 100, 2)  AS rpr_lift_pct,
    ROUND(conv_lift * 100, 2) AS conv_lift_pct,
    (ABS(z_conv_approx) >= 1.96) AS conv_stat_sig,
    (ABS(t_rpr_approx)  >= 1.96) AS rpr_stat_sig,
    STRUCT(ROUND(conv_ci_lower,4) AS lower, ROUND(conv_ci_upper,4) AS upper) AS conv_ci
  FROM lifted
  ORDER BY rpr_lift_pct DESC
);

-- =============================================================================
-- TVF #4: ANALYZE_CONTENT_CATEGORIES
-- =============================================================================
-- Purpose: Analyze content category performance across price tiers
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Category performance metrics with trend analysis
-- Performance Goal: < 100ms
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH enriched AS (
    SELECT
      cb.content_category,
      cb.price_tier,
      SAFE_DIVIDE(mm.earnings, NULLIF(mm.sent_count,0)) AS rpr,
      SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) AS conv,
      mm.price AS price,
      mm.sending_time
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
    JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank_enriched` cb
      ON `of-scheduler-proj.eros_scheduling_brain`.caption_key(mm.message) = cb.caption_key
    WHERE mm.page_name = p_page_name
      -- FIXED: Use LA timezone for consistent lookback
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
      AND mm.viewed_count > 0 AND mm.sent_count > 0
  ),
  perf AS (
    SELECT
      content_category,
      price_tier,
      COUNT(*) AS msg_count,
      AVG(rpr) AS avg_rpr,
      AVG(conv) AS avg_conv,
      SUM(rpr) AS total_rpr,
      -- FIXED: Use LA timezone for trend windows
      AVG(CASE WHEN sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 30 DAY) THEN rpr END)  AS rpr_last_30,
      AVG(CASE WHEN sending_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 60 DAY)
                               AND     TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 30 DAY) THEN rpr END) AS rpr_prev_30,
      CORR(price, conv) AS price_sensitivity_corr
    FROM enriched
    GROUP BY content_category, price_tier
  ),
  ranked AS (
    SELECT
      content_category,
      price_tier,
      msg_count,
      ROUND(avg_rpr,4) AS avg_rpr,
      ROUND(avg_conv,4) AS avg_conv,
      ROUND( SAFE_DIVIDE(rpr_last_30 - rpr_prev_30, NULLIF(rpr_prev_30,0)) * 100, 1) AS trend_pct,
      CASE
        WHEN SAFE_DIVIDE(rpr_last_30 - rpr_prev_30, NULLIF(rpr_prev_30,0)) > 0.10 THEN 'RISING'
        WHEN SAFE_DIVIDE(rpr_last_30 - rpr_prev_30, NULLIF(rpr_prev_30,0)) < -0.10 THEN 'DECLINING'
        ELSE 'STABLE'
      END AS trend_direction,
      ROUND(price_sensitivity_corr,4) AS price_sensitivity_corr
    FROM perf
  ),
  best_tier AS (
    SELECT content_category,
           ARRAY_AGG(STRUCT(price_tier, avg_rpr) ORDER BY avg_rpr DESC LIMIT 1)[OFFSET(0)].price_tier AS best_price_tier
    FROM ranked GROUP BY content_category
  )
  SELECT r.*, bt.best_price_tier
  FROM ranked r JOIN best_tier bt USING (content_category)
  ORDER BY avg_rpr DESC
);

-- =============================================================================
-- TVF #5: ANALYZE_DAY_PATTERNS
-- =============================================================================
-- Purpose: Analyze message performance by day of week with statistical significance
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Day-of-week performance metrics with t-test approximation
-- Performance Goal: < 100ms
-- =============================================================================

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
      -- FIXED: Use LA timezone for consistent lookback
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
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

-- =============================================================================
-- TVF #6: ANALYZE_TIME_WINDOWS
-- =============================================================================
-- Purpose: Analyze message performance by hour and weekday/weekend type
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Hourly performance metrics with confidence scoring
-- Performance Goal: < 100ms
-- =============================================================================

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
      -- FIXED: Use LA timezone for consistent lookback
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL p_lookback_days DAY)
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

-- =============================================================================
-- TVF #7: CALCULATE_SATURATION_SCORE
-- =============================================================================
-- Purpose: Calculate saturation score based on 90-day performance trends
-- Input: page_name (STRING), account_size_tier (STRING)
-- Output: Saturation risk assessment with recommended actions
-- Performance Goal: < 200ms (high computational complexity)
-- =============================================================================

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
      -- FIXED: Use LA timezone for consistent lookback (90 days)
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 90 DAY)
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
    -- FIXED: Use LA timezone for platform baseline (90 days)
    WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP('America/Los_Angeles'), INTERVAL 90 DAY)
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

-- =============================================================================
-- MAIN PROCEDURE: ANALYZE_CREATOR_PERFORMANCE
-- =============================================================================
-- Purpose: Comprehensive creator performance analysis integrating all TVFs
-- Input: p_page_name (STRING) - creator's page name
-- Output: performance_report (STRING) - comprehensive JSON report
-- Performance Goal: < 10 seconds total execution time
-- =============================================================================

CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
  IN  p_page_name STRING,
  OUT performance_report STRING
)
BEGIN
  DECLARE account_size STRUCT<
    size_tier STRING, avg_audience INT64, total_revenue_period FLOAT64,
    daily_ppv_target_min INT64, daily_ppv_target_max INT64, daily_bump_target INT64,
    min_ppv_gap_minutes INT64, saturation_tolerance FLOAT64
  >;

  DECLARE segment STRUCT<
    segment_label STRING, avg_rpr FLOAT64, avg_conv FLOAT64,
    rpr_price_slope FLOAT64, rpr_price_corr FLOAT64,
    conv_price_elasticity_proxy FLOAT64, category_entropy FLOAT64, sample_size INT64
  >;

  DECLARE sat STRUCT<
    saturation_score FLOAT64, risk_level STRING, unlock_rate_deviation FLOAT64, emv_deviation FLOAT64,
    consecutive_underperform_days INT64, recommended_action STRING, volume_adjustment_factor FLOAT64,
    confidence_score FLOAT64, exclusion_reason STRING
  >;

  DECLARE last_etl TIMESTAMP;
  DECLARE analysis_ts TIMESTAMP;

  -- FIXED: Initialize timestamp with LA timezone
  SET analysis_ts = CURRENT_TIMESTAMP('America/Los_Angeles');

  -- Ingest 90d account classification
  SET account_size = (
    SELECT account_size_classification
    FROM `of-scheduler-proj.eros_scheduling_brain`.classify_account_size(p_page_name, 90)
    LIMIT 1
  );

  -- Analyze behavioral segments
  SET segment = (
    SELECT AS STRUCT segment_label, avg_rpr, avg_conv, rpr_price_slope, rpr_price_corr,
            conv_price_elasticity_proxy, category_entropy, sample_size
    FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_behavioral_segments(p_page_name, 90)
    LIMIT 1
  );

  -- Calculate saturation metrics
  SET sat = (
    SELECT AS STRUCT *
    FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score(
      p_page_name,
      COALESCE(account_size.size_tier, 'MEDIUM')
    )
    LIMIT 1
  );

  -- Get data freshness
  SET last_etl = (
    SELECT MAX(run_timestamp)
    FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
  );

  -- Build comprehensive performance report
  SET performance_report = TO_JSON_STRING(STRUCT(
    p_page_name                                 AS creator_name,
    analysis_ts                                 AS analysis_timestamp,
    last_etl                                    AS data_freshness,

    account_size                                AS account_classification,
    segment                                     AS behavioral_segment,
    sat                                         AS saturation,

    -- Psychological trigger analysis
    (SELECT ARRAY_AGG(STRUCT(
        psychological_trigger,
        msg_count,
        avg_rpr,
        avg_conv,
        rpr_lift_pct,
        conv_lift_pct,
        conv_stat_sig,
        rpr_stat_sig
      ) ORDER BY rpr_lift_pct DESC LIMIT 10)
     FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance(p_page_name, 90)
    ) AS psychological_trigger_analysis,

    -- Content category performance
    (SELECT ARRAY_AGG(STRUCT(
        content_category,
        price_tier,
        msg_count,
        avg_rpr,
        avg_conv,
        trend_direction,
        trend_pct,
        price_sensitivity_corr,
        best_price_tier
      ) ORDER BY avg_rpr DESC LIMIT 15)
     FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories(p_page_name, 90)
    ) AS content_category_performance,

    -- Day of week patterns
    (SELECT ARRAY_AGG(STRUCT(
        day_of_week_la,
        n AS msg_count,
        avg_rpr,
        avg_conv,
        t_rpr_approx AS t_statistic,
        rpr_stat_sig
      ) ORDER BY avg_rpr DESC)
     FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns(p_page_name, 90)
    ) AS day_of_week_patterns,

    -- Time window optimization
    (SELECT ARRAY_AGG(STRUCT(
        day_type,
        hour_la AS hour_24,
        n AS msg_count,
        avg_rpr,
        avg_conv,
        confidence
      ) ORDER BY avg_rpr DESC LIMIT 20)
     FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows(p_page_name, 90)
    ) AS time_window_optimization,

    -- Available content categories
    (SELECT ARRAY_AGG(DISTINCT content_category)
     FROM `of-scheduler-proj.eros_scheduling_brain.creator_content_inventory`
     WHERE page_name = p_page_name
    ) AS available_categories
  ));

  -- Log execution
  INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs` (
    job_name, run_timestamp, status, records_processed, records_failed
  ) VALUES (
    'analyze_creator_performance',
    analysis_ts,
    'SUCCESS',
    1,
    0
  );

END;

-- =============================================================================
-- POST-DEPLOYMENT VALIDATION
-- =============================================================================

-- Verify all functions deployed successfully
SELECT
  'POST_DEPLOYMENT_CHECK' AS validation_step,
  routine_name,
  routine_type,
  CASE
    WHEN routine_name = 'analyze_creator_performance' AND routine_type = 'PROCEDURE' THEN 'PASS'
    WHEN routine_type = 'TABLE_VALUED_FUNCTION' THEN 'PASS'
    ELSE 'FAIL'
  END AS status
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
-- EXPECTED: 8 rows with status='PASS'

-- =============================================================================
-- END OF DEPLOYMENT
-- =============================================================================
