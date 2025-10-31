-- =====================================================
-- EROS SCHEDULING BRAIN - STATISTICAL ANALYSIS
-- =====================================================
-- Purpose: Analyze engagement patterns, conversion distributions, and algorithm performance
-- Author: Data Analyst Agent
-- Date: 2025-10-31

-- =====================================================
-- 1. ENGAGEMENT PATTERN ANALYSIS
-- =====================================================

-- Conversion Rate Distribution Analysis
WITH conversion_stats AS (
  SELECT
    avg_conversion_rate,
    conversion_score,
    total_sends,
    total_reach,
    total_conversions,
    lifetime_revenue,
    content_category,
    price_tier,
    validation_level
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE avg_conversion_rate IS NOT NULL
    AND total_sends > 0
)
SELECT
  -- Overall statistics
  COUNT(*) as n_captions,

  -- Conversion rate stats
  ROUND(AVG(avg_conversion_rate), 4) as mean_conversion_rate,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion_rate,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(25)] as p25_conversion,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(50)] as p50_conversion,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(75)] as p75_conversion,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(90)] as p90_conversion,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(95)] as p95_conversion,

  -- Revenue stats
  ROUND(AVG(lifetime_revenue), 2) as mean_revenue,
  ROUND(STDDEV(lifetime_revenue), 2) as std_revenue,
  APPROX_QUANTILES(lifetime_revenue, 100)[OFFSET(50)] as median_revenue,
  APPROX_QUANTILES(lifetime_revenue, 100)[OFFSET(90)] as p90_revenue,

  -- Efficiency stats
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as mean_revenue_per_send,
  ROUND(AVG(SAFE_DIVIDE(total_conversions, total_reach)), 4) as mean_reach_conversion_rate,

  -- Coefficient of variation (CV) to measure consistency
  ROUND(SAFE_DIVIDE(STDDEV(avg_conversion_rate), NULLIF(AVG(avg_conversion_rate), 0)), 4) as cv_conversion_rate,
  ROUND(SAFE_DIVIDE(STDDEV(lifetime_revenue), NULLIF(AVG(lifetime_revenue), 0)), 4) as cv_revenue
FROM conversion_stats;

-- =====================================================
-- 2. PERFORMANCE BY CONTENT CATEGORY
-- =====================================================

SELECT
  content_category,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(total_sends), 2) as avg_sends,
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as revenue_per_send,
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,
  COUNTIF(validation_level = 'high_confidence') as high_confidence_count,
  ROUND(100.0 * COUNTIF(validation_level = 'high_confidence') / COUNT(*), 2) as pct_high_confidence
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
GROUP BY content_category
ORDER BY avg_revenue DESC;

-- =====================================================
-- 3. PERFORMANCE BY PRICE TIER
-- =====================================================

SELECT
  price_tier,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(avg_price), 2) as avg_price_point,
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_conversions)), 2) as revenue_per_conversion,
  ROUND(AVG(conversion_score), 4) as avg_conversion_score,
  ROUND(AVG(revenue_score), 4) as avg_revenue_score,
  ROUND(AVG(overall_performance_score), 4) as avg_overall_score
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0 AND total_conversions > 0
GROUP BY price_tier
ORDER BY avg_overall_score DESC;

-- =====================================================
-- 4. PSYCHOLOGICAL TRIGGER EFFECTIVENESS
-- =====================================================

SELECT
  has_urgency,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(total_sends), 2) as avg_sends,
  ROUND(AVG(conversion_score), 4) as avg_conversion_score,

  -- Caption characteristics
  ROUND(AVG(caption_length), 1) as avg_caption_length,
  ROUND(AVG(question_count), 2) as avg_questions,
  ROUND(AVG(exclamation_count), 2) as avg_exclamations,
  ROUND(AVG(emoji_count), 2) as avg_emojis,

  -- Performance comparison
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as revenue_per_send
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
GROUP BY has_urgency
ORDER BY avg_conversion DESC;

-- =====================================================
-- 5. CAPTION LENGTH EFFECTIVENESS ANALYSIS
-- =====================================================

WITH length_buckets AS (
  SELECT
    CASE
      WHEN caption_length < 50 THEN '1_very_short'
      WHEN caption_length < 100 THEN '2_short'
      WHEN caption_length < 200 THEN '3_medium'
      WHEN caption_length < 300 THEN '4_long'
      ELSE '5_very_long'
    END as length_category,
    avg_conversion_rate,
    lifetime_revenue,
    total_sends,
    conversion_score,
    question_count,
    exclamation_count,
    emoji_count
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND caption_length IS NOT NULL
)
SELECT
  length_category,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as revenue_per_send,
  ROUND(AVG(question_count), 2) as avg_questions,
  ROUND(AVG(exclamation_count), 2) as avg_exclamations,
  ROUND(AVG(emoji_count), 2) as avg_emojis
FROM length_buckets
GROUP BY length_category
ORDER BY length_category;

-- =====================================================
-- 6. TIME-BASED PERFORMANCE PATTERNS
-- =====================================================

-- Day of week performance (from successful_days array)
WITH day_analysis AS (
  SELECT
    day_of_week,
    AVG(avg_conversion_rate) as avg_conversion,
    AVG(lifetime_revenue) as avg_revenue,
    COUNT(DISTINCT caption_id) as n_captions_used
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`,
  UNNEST(successful_days) as day_of_week
  WHERE total_sends > 0
  GROUP BY day_of_week
)
SELECT *
FROM day_analysis
ORDER BY avg_conversion DESC;

-- Hour of day performance (from successful_hours array)
WITH hour_analysis AS (
  SELECT
    hour_of_day,
    COUNT(DISTINCT caption_id) as n_captions_used,
    AVG(avg_conversion_rate) as avg_conversion,
    AVG(lifetime_revenue) as avg_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`,
  UNNEST(successful_hours) as hour_of_day
  WHERE total_sends > 0
  GROUP BY hour_of_day
)
SELECT *
FROM hour_analysis
ORDER BY hour_of_day;

-- =====================================================
-- 7. USAGE RECENCY AND FATIGUE ANALYSIS
-- =====================================================

WITH recency_buckets AS (
  SELECT
    CASE
      WHEN days_since_last_use IS NULL THEN '0_never_used'
      WHEN days_since_last_use = 0 THEN '1_used_today'
      WHEN days_since_last_use <= 7 THEN '2_last_week'
      WHEN days_since_last_use <= 30 THEN '3_last_month'
      WHEN days_since_last_use <= 90 THEN '4_last_quarter'
      ELSE '5_stale'
    END as recency_bucket,
    usage_status,
    avg_conversion_rate,
    total_sends,
    lifetime_revenue,
    conversion_score
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
)
SELECT
  recency_bucket,
  usage_status,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(total_sends), 2) as avg_sends,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_total
FROM recency_buckets
GROUP BY recency_bucket, usage_status
ORDER BY recency_bucket, usage_status;

-- =====================================================
-- 8. VALIDATION LEVEL EFFECTIVENESS
-- =====================================================

SELECT
  validation_level,
  COUNT(*) as n_captions,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue,
  ROUND(AVG(total_sends), 2) as avg_sends,
  ROUND(AVG(pages_used_count), 2) as avg_pages_used,
  ROUND(AVG(conversion_score), 4) as avg_conversion_score,
  ROUND(AVG(revenue_score), 4) as avg_revenue_score,
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,
  ROUND(AVG(overall_performance_score), 4) as avg_overall_score,

  -- Statistical significance indicators
  ROUND(AVG(SAFE_DIVIDE(STDDEV(avg_conversion_rate), SQRT(total_sends))), 6) as avg_std_error
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
GROUP BY validation_level
ORDER BY avg_overall_score DESC;

-- =====================================================
-- 9. CORRELATION ANALYSIS
-- =====================================================

-- Correlation between caption features and performance
SELECT
  ROUND(CORR(caption_length, avg_conversion_rate), 4) as corr_length_conversion,
  ROUND(CORR(question_count, avg_conversion_rate), 4) as corr_questions_conversion,
  ROUND(CORR(exclamation_count, avg_conversion_rate), 4) as corr_exclamations_conversion,
  ROUND(CORR(emoji_count, avg_conversion_rate), 4) as corr_emoji_conversion,
  ROUND(CORR(avg_price, avg_conversion_rate), 4) as corr_price_conversion,
  ROUND(CORR(avg_price, lifetime_revenue), 4) as corr_price_revenue,
  ROUND(CORR(total_sends, avg_conversion_rate), 4) as corr_volume_conversion,
  ROUND(CORR(pages_used_count, avg_conversion_rate), 4) as corr_breadth_conversion
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
  AND avg_conversion_rate IS NOT NULL;

-- =====================================================
-- 10. OUTLIER DETECTION
-- =====================================================

WITH stats AS (
  SELECT
    AVG(avg_conversion_rate) as mean_conv,
    STDDEV(avg_conversion_rate) as std_conv,
    AVG(lifetime_revenue) as mean_rev,
    STDDEV(lifetime_revenue) as std_rev
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND avg_conversion_rate IS NOT NULL
),
outliers AS (
  SELECT
    caption_id,
    caption_text,
    content_category,
    price_tier,
    avg_conversion_rate,
    lifetime_revenue,
    total_sends,
    -- Z-scores
    ROUND((avg_conversion_rate - stats.mean_conv) / NULLIF(stats.std_conv, 0), 2) as z_score_conversion,
    ROUND((lifetime_revenue - stats.mean_rev) / NULLIF(stats.std_rev, 0), 2) as z_score_revenue,
    validation_level
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`, stats
  WHERE total_sends > 0 AND avg_conversion_rate IS NOT NULL
)
SELECT
  'High Performance Outliers (Z > 2)' as outlier_type,
  COUNT(*) as n_outliers,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue
FROM outliers
WHERE z_score_conversion > 2 OR z_score_revenue > 2

UNION ALL

SELECT
  'Low Performance Outliers (Z < -2)' as outlier_type,
  COUNT(*) as n_outliers,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue
FROM outliers
WHERE z_score_conversion < -2 OR z_score_revenue < -2

UNION ALL

SELECT
  'Normal Performance (-2 < Z < 2)' as outlier_type,
  COUNT(*) as n_outliers,
  ROUND(AVG(avg_conversion_rate), 4) as avg_conversion,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue
FROM outliers
WHERE z_score_conversion BETWEEN -2 AND 2
  AND z_score_revenue BETWEEN -2 AND 2;
