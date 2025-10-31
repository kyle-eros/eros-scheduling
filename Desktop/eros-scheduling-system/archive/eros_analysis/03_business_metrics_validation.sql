-- =====================================================
-- EROS SCHEDULING BRAIN - BUSINESS METRICS VALIDATION
-- =====================================================
-- Purpose: Validate KPI calculations and metric consistency
-- Author: Data Analyst Agent
-- Date: 2025-10-31

-- =====================================================
-- 1. KPI CALCULATION VALIDATION
-- =====================================================

-- Validate conversion score calculation
WITH score_validation AS (
  SELECT
    caption_id,
    conversion_score,
    avg_conversion_rate,
    best_conversion_rate,
    total_conversions,
    total_reach,
    -- Recalculate to validate
    SAFE_DIVIDE(total_conversions, NULLIF(total_reach, 0)) as calculated_conversion_rate,
    ABS(avg_conversion_rate - SAFE_DIVIDE(total_conversions, NULLIF(total_reach, 0))) as conversion_rate_diff
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
)
SELECT
  COUNT(*) as total_captions,
  COUNTIF(conversion_rate_diff > 0.001) as significant_discrepancies,
  ROUND(100.0 * COUNTIF(conversion_rate_diff > 0.001) / COUNT(*), 2) as pct_discrepancies,
  ROUND(AVG(conversion_rate_diff), 6) as avg_discrepancy,
  ROUND(MAX(conversion_rate_diff), 6) as max_discrepancy
FROM score_validation;

-- =====================================================
-- 2. REVENUE METRICS VALIDATION
-- =====================================================

WITH revenue_validation AS (
  SELECT
    caption_id,
    lifetime_revenue,
    total_conversions,
    avg_revenue,
    min_revenue,
    max_revenue,
    avg_revenue_per_recipient,
    total_reach,
    -- Validate revenue calculations
    SAFE_DIVIDE(lifetime_revenue, NULLIF(total_conversions, 0)) as calc_revenue_per_conversion,
    SAFE_DIVIDE(lifetime_revenue, NULLIF(total_reach, 0)) as calc_revenue_per_recipient,
    -- Check for logical errors
    CASE
      WHEN max_revenue < min_revenue THEN 'max_less_than_min'
      WHEN avg_revenue < min_revenue OR avg_revenue > max_revenue THEN 'avg_out_of_bounds'
      WHEN lifetime_revenue < 0 THEN 'negative_revenue'
      WHEN total_conversions > 0 AND lifetime_revenue = 0 THEN 'conversions_no_revenue'
      ELSE 'valid'
    END as validation_status
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
)
SELECT
  validation_status,
  COUNT(*) as n_captions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_total,
  ROUND(AVG(lifetime_revenue), 2) as avg_lifetime_revenue,
  ROUND(AVG(total_conversions), 2) as avg_conversions
FROM revenue_validation
GROUP BY validation_status
ORDER BY n_captions DESC;

-- =====================================================
-- 3. EFFICIENCY SCORE VALIDATION
-- =====================================================

SELECT
  COUNT(*) as total_captions_with_scores,
  COUNTIF(efficiency_score IS NOT NULL) as captions_with_efficiency_score,
  COUNTIF(efficiency_score < 0) as negative_efficiency_scores,
  COUNTIF(efficiency_score > 10) as unusually_high_efficiency,
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,
  ROUND(STDDEV(efficiency_score), 4) as std_efficiency_score,
  APPROX_QUANTILES(efficiency_score, 100)[OFFSET(50)] as median_efficiency,
  APPROX_QUANTILES(efficiency_score, 100)[OFFSET(90)] as p90_efficiency,
  -- Validate against revenue per send
  ROUND(CORR(efficiency_score, SAFE_DIVIDE(lifetime_revenue, total_sends)), 4) as corr_with_revenue_per_send
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0;

-- =====================================================
-- 4. OVERALL PERFORMANCE SCORE VALIDATION
-- =====================================================

WITH score_components AS (
  SELECT
    caption_id,
    overall_performance_score,
    conversion_score,
    revenue_score,
    efficiency_score,
    -- Check if overall score is a combination of component scores
    (COALESCE(conversion_score, 0) + COALESCE(revenue_score, 0) + COALESCE(efficiency_score, 0)) / 3.0 as avg_component_score
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
    AND total_conversions > 0
)
SELECT
  COUNT(*) as n_captions_analyzed,
  ROUND(AVG(overall_performance_score), 4) as avg_overall_score,
  ROUND(AVG(conversion_score), 4) as avg_conversion_score,
  ROUND(AVG(revenue_score), 4) as avg_revenue_score,
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,
  ROUND(AVG(avg_component_score), 4) as avg_of_components,
  ROUND(CORR(overall_performance_score, conversion_score), 4) as corr_overall_conversion,
  ROUND(CORR(overall_performance_score, revenue_score), 4) as corr_overall_revenue,
  ROUND(CORR(overall_performance_score, efficiency_score), 4) as corr_overall_efficiency
FROM score_components;

-- =====================================================
-- 5. CROSS-TABLE METRIC CONSISTENCY
-- =====================================================

-- Compare metrics between caption_bank and caption_performance_tracking
WITH bank_summary AS (
  SELECT
    caption_key as caption_hash,
    avg_conversion_rate as bank_conversion,
    total_sends as bank_sends,
    lifetime_revenue as bank_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0
),
tracking_summary AS (
  SELECT
    caption_hash,
    lifetime_conversion as tracking_conversion,
    total_uses as tracking_uses
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_performance_tracking`
  WHERE total_uses > 0
)
SELECT
  COUNT(DISTINCT b.caption_hash) as captions_in_bank,
  COUNT(DISTINCT t.caption_hash) as captions_in_tracking,
  COUNT(DISTINCT CASE WHEN b.caption_hash IS NOT NULL AND t.caption_hash IS NOT NULL THEN b.caption_hash END) as captions_in_both,
  ROUND(AVG(ABS(b.bank_conversion - COALESCE(t.tracking_conversion, 0))), 6) as avg_conversion_diff,
  COUNTIF(ABS(b.bank_conversion - COALESCE(t.tracking_conversion, 0)) > 0.01) as significant_conversion_diffs
FROM bank_summary b
FULL OUTER JOIN tracking_summary t
  ON b.caption_hash = t.caption_hash;

-- =====================================================
-- 6. CREATOR-LEVEL METRIC AGGREGATION
-- =====================================================

WITH creator_metrics AS (
  SELECT
    page_name,
    COUNT(DISTINCT cb.caption_id) as total_captions_used,
    ROUND(AVG(cb.avg_conversion_rate), 4) as avg_conversion,
    ROUND(SUM(cb.lifetime_revenue), 2) as total_revenue,
    ROUND(SUM(cb.total_sends), 0) as total_sends,
    ROUND(SUM(cb.total_conversions), 0) as total_conversions,
    ROUND(SAFE_DIVIDE(SUM(cb.lifetime_revenue), SUM(cb.total_sends)), 4) as revenue_per_send,
    ROUND(SAFE_DIVIDE(SUM(cb.total_conversions), SUM(cb.total_reach)), 4) as overall_conversion_rate
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb,
  UNNEST(sample_pages_used) as page_name
  WHERE cb.total_sends > 0
  GROUP BY page_name
)
SELECT
  COUNT(*) as total_creators_analyzed,
  ROUND(AVG(total_captions_used), 2) as avg_captions_per_creator,
  ROUND(AVG(avg_conversion), 4) as avg_creator_conversion,
  ROUND(AVG(total_revenue), 2) as avg_creator_revenue,
  ROUND(AVG(revenue_per_send), 4) as avg_creator_rps,
  ROUND(STDDEV(overall_conversion_rate), 4) as std_conversion_across_creators,
  APPROX_QUANTILES(total_revenue, 100)[OFFSET(25)] as p25_revenue,
  APPROX_QUANTILES(total_revenue, 100)[OFFSET(50)] as p50_revenue,
  APPROX_QUANTILES(total_revenue, 100)[OFFSET(75)] as p75_revenue,
  APPROX_QUANTILES(total_revenue, 100)[OFFSET(90)] as p90_revenue
FROM creator_metrics;

-- =====================================================
-- 7. CAPTION USAGE PATTERN CONSISTENCY
-- =====================================================

WITH usage_patterns AS (
  SELECT
    caption_id,
    total_sends,
    pages_used_count,
    ARRAY_LENGTH(sample_pages_used) as sample_pages_count,
    first_used,
    last_used,
    days_since_last_use,
    -- Validate days_since_last_use calculation
    DATE_DIFF(CURRENT_DATE(), DATE(last_used), DAY) as calculated_days_since_last_use,
    ABS(days_since_last_use - DATE_DIFF(CURRENT_DATE(), DATE(last_used), DAY)) as days_diff
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE last_used IS NOT NULL
)
SELECT
  COUNT(*) as total_captions,
  COUNTIF(days_diff > 1) as captions_with_date_discrepancy,
  ROUND(100.0 * COUNTIF(days_diff > 1) / COUNT(*), 2) as pct_date_discrepancy,
  COUNTIF(sample_pages_count > pages_used_count) as sample_exceeds_total_pages,
  COUNTIF(total_sends < pages_used_count) as sends_less_than_pages,
  COUNTIF(last_used < first_used) as last_before_first,
  ROUND(AVG(days_diff), 2) as avg_date_calculation_diff
FROM usage_patterns;

-- =====================================================
-- 8. CONTENT CATEGORY DISTRIBUTION VALIDATION
-- =====================================================

SELECT
  content_category,
  COUNT(*) as n_captions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_total,
  SUM(total_sends) as total_sends,
  ROUND(100.0 * SUM(total_sends) / SUM(SUM(total_sends)) OVER(), 2) as pct_of_sends,
  SUM(total_conversions) as total_conversions,
  ROUND(100.0 * SUM(total_conversions) / SUM(SUM(total_conversions)) OVER(), 2) as pct_of_conversions,
  SUM(lifetime_revenue) as total_revenue,
  ROUND(100.0 * SUM(lifetime_revenue) / SUM(SUM(lifetime_revenue)) OVER(), 2) as pct_of_revenue
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
GROUP BY content_category
HAVING COUNT(*) > 10
ORDER BY total_revenue DESC
LIMIT 20;

-- =====================================================
-- 9. PRICE TIER DISTRIBUTION AND REVENUE ATTRIBUTION
-- =====================================================

SELECT
  price_tier,
  COUNT(*) as n_captions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_captions,
  SUM(total_conversions) as total_conversions,
  SUM(lifetime_revenue) as total_revenue,
  ROUND(100.0 * SUM(lifetime_revenue) / SUM(SUM(lifetime_revenue)) OVER(), 2) as pct_of_revenue,
  ROUND(AVG(avg_price), 2) as avg_price_point,
  ROUND(AVG(min_price), 2) as avg_min_price,
  ROUND(AVG(max_price), 2) as avg_max_price,
  ROUND(SAFE_DIVIDE(SUM(lifetime_revenue), SUM(total_conversions)), 2) as revenue_per_conversion
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0 AND total_conversions > 0
GROUP BY price_tier
ORDER BY total_revenue DESC;

-- =====================================================
-- 10. CONVERSION FUNNEL VALIDATION
-- =====================================================

WITH funnel_metrics AS (
  SELECT
    COUNT(*) as total_captions_in_bank,
    COUNTIF(total_sends > 0) as captions_sent,
    COUNTIF(total_reach > 0) as captions_with_reach,
    COUNTIF(total_conversions > 0) as captions_with_conversions,
    COUNTIF(lifetime_revenue > 0) as captions_with_revenue,
    SUM(total_sends) as total_sends,
    SUM(total_reach) as total_reach,
    SUM(total_conversions) as total_conversions,
    SUM(lifetime_revenue) as total_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
)
SELECT
  total_captions_in_bank,
  captions_sent,
  ROUND(100.0 * captions_sent / total_captions_in_bank, 2) as pct_captions_sent,
  captions_with_reach,
  ROUND(100.0 * captions_with_reach / captions_sent, 2) as pct_sent_with_reach,
  captions_with_conversions,
  ROUND(100.0 * captions_with_conversions / captions_with_reach, 2) as pct_reach_to_conversion,
  captions_with_revenue,
  ROUND(100.0 * captions_with_revenue / captions_with_conversions, 2) as pct_conversions_with_revenue,
  total_sends,
  total_reach,
  total_conversions,
  ROUND(total_revenue, 2) as total_revenue,
  ROUND(100.0 * total_conversions / NULLIF(total_reach, 0), 4) as overall_conversion_rate,
  ROUND(total_revenue / NULLIF(total_conversions, 0), 2) as avg_revenue_per_conversion,
  ROUND(total_revenue / NULLIF(total_sends, 0), 2) as avg_revenue_per_send
FROM funnel_metrics;
