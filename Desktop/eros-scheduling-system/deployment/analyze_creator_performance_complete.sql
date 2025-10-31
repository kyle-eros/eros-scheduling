-- =============================================================================
-- FINAL PROCEDURE DEPLOYMENT: ANALYZE_CREATOR_PERFORMANCE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Complete creator performance analysis using all TVFs
-- Created: October 31, 2025
-- =============================================================================

-- =============================================================================
-- PREREQUISITE TVF #1: CLASSIFY_ACCOUNT_SIZE
-- =============================================================================
-- Purpose: Classify creator accounts into size tiers with metrics
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Account size tier classification with audience and revenue metrics
-- =============================================================================

CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.classify_account_size(
  p_page_name STRING,
  p_lookback_days INT64
)
AS (
  WITH page_stats AS (
    SELECT
      page_name,
      COUNT(DISTINCT DATE(sending_time)) AS active_days,
      COUNT(*) AS total_messages,
      SUM(viewed_count) AS total_views,
      AVG(viewed_count) AS avg_views_per_msg,
      APPROX_QUANTILES(viewed_count, 100)[OFFSET(50)] AS median_views,
      SUM(earnings) AS total_revenue,
      SUM(purchased_count) AS total_purchases,
      SAFE_DIVIDE(SUM(purchased_count), NULLIF(SUM(viewed_count), 0)) AS overall_conversion
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE page_name = p_page_name
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
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
-- PREREQUISITE TVF #2: ANALYZE_BEHAVIORAL_SEGMENTS
-- =============================================================================
-- Purpose: Analyze creator behavioral segments with performance metrics
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: Segment classification with RPR and conversion analytics
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
      AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
      AND viewed_count > 0 AND sent_count > 0
  ),
  segment_stats AS (
    SELECT
      COUNT(*) AS msg_count,
      COUNT(DISTINCT SAFE_DIVIDE(CAST(EXTRACT(DAY FROM CURRENT_TIMESTAMP()) AS INT64), 7)) AS cohort_size,
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
-- MAIN PROCEDURE: ANALYZE_CREATOR_PERFORMANCE
-- =============================================================================
-- Purpose: Comprehensive creator performance analysis integrating all TVFs
-- Input: p_page_name (STRING) - creator's page name
-- Output: performance_report (STRING) - comprehensive JSON report
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

  -- Initialize timestamps
  SET analysis_ts = CURRENT_TIMESTAMP();

  -- Ingest 90d account classification (tune in orchestrator if needed)
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
-- VALIDATION QUERIES
-- =============================================================================

-- Verify all TVF dependencies are available
SELECT
  routine_name,
  routine_type,
  data_type
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
