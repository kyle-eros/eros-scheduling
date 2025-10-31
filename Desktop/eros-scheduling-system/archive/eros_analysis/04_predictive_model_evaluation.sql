-- =====================================================
-- EROS SCHEDULING BRAIN - PREDICTIVE MODEL EVALUATION
-- =====================================================
-- Purpose: Assess caption selection, saturation prediction, and forecasting accuracy
-- Author: Data Analyst Agent
-- Date: 2025-10-31

-- =====================================================
-- 1. CAPTION PERFORMANCE SCORE PREDICTION ACCURACY
-- =====================================================

-- Analyze how well scores predict actual performance
WITH score_performance AS (
  SELECT
    caption_id,
    -- Predicted scores
    conversion_score,
    revenue_score,
    efficiency_score,
    overall_performance_score,
    -- Actual performance
    avg_conversion_rate as actual_conversion,
    SAFE_DIVIDE(lifetime_revenue, total_sends) as actual_revenue_per_send,
    total_sends,
    validation_level,
    -- Decile buckets for analysis
    NTILE(10) OVER (ORDER BY overall_performance_score) as overall_score_decile,
    NTILE(10) OVER (ORDER BY conversion_score) as conversion_score_decile
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
    AND overall_performance_score IS NOT NULL
    AND total_conversions > 0
)
SELECT
  overall_score_decile,
  COUNT(*) as n_captions,
  ROUND(AVG(overall_performance_score), 4) as avg_predicted_score,
  ROUND(AVG(actual_conversion), 4) as avg_actual_conversion,
  ROUND(AVG(actual_revenue_per_send), 4) as avg_actual_rps,
  ROUND(STDDEV(actual_conversion), 4) as std_actual_conversion,
  ROUND(MIN(overall_performance_score), 4) as min_score_in_decile,
  ROUND(MAX(overall_performance_score), 4) as max_score_in_decile
FROM score_performance
GROUP BY overall_score_decile
ORDER BY overall_score_decile;

-- =====================================================
-- 2. CONVERSION SCORE CALIBRATION
-- =====================================================

-- Check if conversion scores are well-calibrated to actual conversion rates
WITH calibration_analysis AS (
  SELECT
    CASE
      WHEN conversion_score IS NULL THEN '0_null_score'
      WHEN conversion_score < 0.1 THEN '1_very_low'
      WHEN conversion_score < 0.5 THEN '2_low'
      WHEN conversion_score < 1.0 THEN '3_medium'
      WHEN conversion_score < 2.0 THEN '4_high'
      ELSE '5_very_high'
    END as score_bucket,
    conversion_score,
    avg_conversion_rate,
    lifetime_revenue,
    total_sends,
    total_conversions
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
)
SELECT
  score_bucket,
  COUNT(*) as n_captions,
  ROUND(AVG(conversion_score), 4) as avg_predicted_score,
  ROUND(AVG(avg_conversion_rate), 4) as avg_actual_conversion,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_actual_conversion,
  -- Calculate Mean Absolute Error (MAE)
  ROUND(AVG(ABS(COALESCE(conversion_score, 0) - avg_conversion_rate)), 4) as mae,
  -- Calculate Root Mean Square Error (RMSE)
  ROUND(SQRT(AVG(POW(COALESCE(conversion_score, 0) - avg_conversion_rate, 2))), 4) as rmse
FROM calibration_analysis
GROUP BY score_bucket
ORDER BY score_bucket;

-- =====================================================
-- 3. VALIDATION LEVEL EFFECTIVENESS
-- =====================================================

-- Evaluate how well validation levels predict caption success
WITH validation_performance AS (
  SELECT
    validation_level,
    COUNT(*) as n_captions,
    AVG(avg_conversion_rate) as avg_conversion,
    STDDEV(avg_conversion_rate) as std_conversion,
    AVG(lifetime_revenue) as avg_revenue,
    AVG(total_sends) as avg_sends,
    -- Calculate coefficient of variation (lower = more consistent)
    SAFE_DIVIDE(STDDEV(avg_conversion_rate), AVG(avg_conversion_rate)) as cv_conversion,
    -- Success rate (top quartile performance)
    COUNTIF(avg_conversion_rate >= (
      SELECT APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(75)]
      FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
      WHERE total_sends > 0
    )) as n_top_quartile
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
  GROUP BY validation_level
)
SELECT
  validation_level,
  n_captions,
  ROUND(avg_conversion, 4) as avg_conversion,
  ROUND(std_conversion, 4) as std_conversion,
  ROUND(avg_revenue, 2) as avg_revenue,
  ROUND(cv_conversion, 4) as coefficient_of_variation,
  n_top_quartile,
  ROUND(100.0 * n_top_quartile / n_captions, 2) as pct_top_quartile
FROM validation_performance
ORDER BY avg_conversion DESC;

-- =====================================================
-- 4. SATURATION DETECTION ANALYSIS
-- =====================================================

-- Analyze usage patterns to detect saturation/fatigue
WITH usage_trajectory AS (
  SELECT
    caption_id,
    caption_text,
    total_sends,
    pages_used_count,
    days_since_last_use,
    usage_status,
    avg_conversion_rate,
    best_conversion_rate,
    -- Detect performance degradation
    CASE
      WHEN best_conversion_rate > 0 THEN
        SAFE_DIVIDE(avg_conversion_rate, best_conversion_rate)
      ELSE NULL
    END as performance_retention_ratio,
    DATE_DIFF(last_used, first_used, DAY) as days_of_usage,
    SAFE_DIVIDE(total_sends, NULLIF(DATE_DIFF(last_used, first_used, DAY), 0)) as sends_per_day
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
    AND first_used IS NOT NULL
    AND last_used IS NOT NULL
)
SELECT
  usage_status,
  COUNT(*) as n_captions,
  ROUND(AVG(days_since_last_use), 1) as avg_days_since_use,
  ROUND(AVG(total_sends), 2) as avg_total_sends,
  ROUND(AVG(pages_used_count), 2) as avg_pages_used,
  ROUND(AVG(performance_retention_ratio), 4) as avg_performance_retention,
  ROUND(AVG(days_of_usage), 1) as avg_days_of_usage,
  COUNTIF(performance_retention_ratio < 0.5) as n_degraded_performance,
  ROUND(100.0 * COUNTIF(performance_retention_ratio < 0.5) / COUNT(*), 2) as pct_degraded
FROM usage_trajectory
WHERE performance_retention_ratio IS NOT NULL
GROUP BY usage_status
ORDER BY avg_performance_retention DESC;

-- =====================================================
-- 5. FRESHNESS IMPACT ON PERFORMANCE
-- =====================================================

WITH recency_performance AS (
  SELECT
    CASE
      WHEN days_since_last_use IS NULL OR days_since_last_use = 0 THEN '1_current'
      WHEN days_since_last_use <= 7 THEN '2_recent'
      WHEN days_since_last_use <= 30 THEN '3_moderate'
      WHEN days_since_last_use <= 90 THEN '4_aging'
      ELSE '5_stale'
    END as recency_bucket,
    avg_conversion_rate,
    lifetime_revenue,
    total_sends,
    days_since_last_use
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
)
SELECT
  recency_bucket,
  COUNT(*) as n_captions,
  ROUND(AVG(days_since_last_use), 1) as avg_days_since_use,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as avg_rps,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion,
  -- Compare to baseline (current captions)
  ROUND(AVG(avg_conversion_rate) - (
    SELECT AVG(avg_conversion_rate)
    FROM recency_performance
    WHERE recency_bucket = '1_current'
  ), 6) as conversion_delta_vs_current
FROM recency_performance
GROUP BY recency_bucket
ORDER BY recency_bucket;

-- =====================================================
-- 6. CONTENT CATEGORY RECOMMENDATION ACCURACY
-- =====================================================

-- Analyze if content categories are good predictors of performance
WITH category_prediction AS (
  SELECT
    content_category,
    COUNT(*) as n_captions,
    AVG(avg_conversion_rate) as avg_conversion,
    STDDEV(avg_conversion_rate) as std_conversion,
    APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(25)] as p25_conversion,
    APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(75)] as p75_conversion,
    -- Interquartile range (IQR) - lower means more predictable
    APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(75)] -
    APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(25)] as iqr_conversion,
    -- Coefficient of variation
    SAFE_DIVIDE(STDDEV(avg_conversion_rate), AVG(avg_conversion_rate)) as cv_conversion
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
  GROUP BY content_category
  HAVING COUNT(*) >= 10
)
SELECT
  content_category,
  n_captions,
  ROUND(avg_conversion, 4) as avg_conversion,
  ROUND(std_conversion, 4) as std_conversion,
  ROUND(iqr_conversion, 4) as iqr_conversion,
  ROUND(cv_conversion, 4) as cv_conversion,
  -- Predictability score (lower CV = more predictable)
  CASE
    WHEN cv_conversion < 0.5 THEN 'highly_predictable'
    WHEN cv_conversion < 1.0 THEN 'moderately_predictable'
    WHEN cv_conversion < 2.0 THEN 'somewhat_predictable'
    ELSE 'unpredictable'
  END as predictability
FROM category_prediction
ORDER BY avg_conversion DESC;

-- =====================================================
-- 7. PRICE TIER PREDICTION EFFECTIVENESS
-- =====================================================

WITH price_tier_performance AS (
  SELECT
    price_tier,
    COUNT(*) as n_captions,
    AVG(avg_conversion_rate) as avg_conversion,
    AVG(lifetime_revenue) as avg_revenue,
    AVG(avg_price) as avg_price_point,
    STDDEV(avg_conversion_rate) as std_conversion,
    STDDEV(lifetime_revenue) as std_revenue,
    -- Calculate conversion consistency within tier
    SAFE_DIVIDE(STDDEV(avg_conversion_rate), AVG(avg_conversion_rate)) as cv_conversion,
    -- Calculate revenue consistency within tier
    SAFE_DIVIDE(STDDEV(lifetime_revenue), AVG(lifetime_revenue)) as cv_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND total_conversions > 0
  GROUP BY price_tier
)
SELECT
  price_tier,
  n_captions,
  ROUND(avg_price_point, 2) as avg_price,
  ROUND(avg_conversion, 4) as avg_conversion,
  ROUND(avg_revenue, 2) as avg_revenue,
  ROUND(cv_conversion, 4) as cv_conversion,
  ROUND(cv_revenue, 4) as cv_revenue,
  -- Predictability assessment
  CASE
    WHEN cv_conversion < 1.0 AND cv_revenue < 1.0 THEN 'high_predictability'
    WHEN cv_conversion < 2.0 AND cv_revenue < 2.0 THEN 'moderate_predictability'
    ELSE 'low_predictability'
  END as tier_predictability
FROM price_tier_performance
ORDER BY avg_revenue DESC;

-- =====================================================
-- 8. RECOMMENDATION QUALITY ANALYSIS
-- =====================================================

WITH recommendation_quality AS (
  SELECT
    status,
    confidence_score,
    uniqueness_score,
    caption_quality_score,
    import_result,
    DATE_DIFF(imported_at, generated_at, HOUR) as hours_to_import,
    DATE_DIFF(CURRENT_TIMESTAMP(), generated_at, DAY) as days_since_generation
  FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
  WHERE generated_at IS NOT NULL
)
SELECT
  status,
  COUNT(*) as n_recommendations,
  ROUND(AVG(confidence_score), 4) as avg_confidence,
  ROUND(AVG(uniqueness_score), 4) as avg_uniqueness,
  ROUND(AVG(caption_quality_score), 4) as avg_quality_score,
  ROUND(AVG(hours_to_import), 2) as avg_hours_to_import,
  ROUND(AVG(days_since_generation), 1) as avg_days_since_generation,
  COUNTIF(confidence_score >= 0.7) as high_confidence_count,
  ROUND(100.0 * COUNTIF(confidence_score >= 0.7) / COUNT(*), 2) as pct_high_confidence
FROM recommendation_quality
GROUP BY status
ORDER BY n_recommendations DESC;

-- =====================================================
-- 9. THOMPSON SAMPLING CONVERGENCE ANALYSIS
-- =====================================================

-- Analyze if captions with more sends have more stable conversion rates
WITH sampling_convergence AS (
  SELECT
    caption_id,
    total_sends,
    avg_conversion_rate,
    best_conversion_rate,
    -- Group by send volume
    CASE
      WHEN total_sends = 1 THEN '1_single_send'
      WHEN total_sends <= 5 THEN '2_few_sends'
      WHEN total_sends <= 20 THEN '3_moderate_sends'
      WHEN total_sends <= 100 THEN '4_many_sends'
      ELSE '5_high_volume'
    END as volume_bucket,
    -- Calculate variance between best and average (should decrease with volume)
    ABS(best_conversion_rate - avg_conversion_rate) as conversion_variance
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
    AND avg_conversion_rate IS NOT NULL
    AND best_conversion_rate IS NOT NULL
)
SELECT
  volume_bucket,
  COUNT(*) as n_captions,
  ROUND(AVG(total_sends), 2) as avg_sends,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion,
  ROUND(AVG(conversion_variance), 6) as avg_variance_best_vs_avg,
  -- Convergence indicator (should decrease with more sends)
  ROUND(STDDEV(avg_conversion_rate) / SQRT(AVG(total_sends)), 6) as std_error_estimate,
  -- Confidence level based on sample size
  COUNTIF(total_sends >= 30) as n_statistically_significant,
  ROUND(100.0 * COUNTIF(total_sends >= 30) / COUNT(*), 2) as pct_statistically_significant
FROM sampling_convergence
GROUP BY volume_bucket
ORDER BY volume_bucket;

-- =====================================================
-- 10. FEATURE IMPORTANCE FOR PERFORMANCE PREDICTION
-- =====================================================

-- Calculate correlations between caption features and performance
SELECT
  'caption_length' as feature,
  ROUND(CORR(caption_length, avg_conversion_rate), 4) as corr_with_conversion,
  ROUND(CORR(caption_length, lifetime_revenue), 4) as corr_with_revenue

UNION ALL

SELECT 'question_count',
  ROUND(CORR(question_count, avg_conversion_rate), 4),
  ROUND(CORR(question_count, lifetime_revenue), 4)

UNION ALL

SELECT 'exclamation_count',
  ROUND(CORR(exclamation_count, avg_conversion_rate), 4),
  ROUND(CORR(exclamation_count, lifetime_revenue), 4)

UNION ALL

SELECT 'emoji_count',
  ROUND(CORR(emoji_count, avg_conversion_rate), 4),
  ROUND(CORR(emoji_count, lifetime_revenue), 4)

UNION ALL

SELECT 'avg_price',
  ROUND(CORR(avg_price, avg_conversion_rate), 4),
  ROUND(CORR(avg_price, lifetime_revenue), 4)

UNION ALL

SELECT 'pages_used_count',
  ROUND(CORR(pages_used_count, avg_conversion_rate), 4),
  ROUND(CORR(pages_used_count, lifetime_revenue), 4)

FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0 AND avg_conversion_rate IS NOT NULL;
