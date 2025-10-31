-- =====================================================
-- EROS SCHEDULING BRAIN - DASHBOARD METRICS & MONITORING
-- =====================================================
-- Purpose: Production-ready queries for executive dashboards and monitoring
-- Author: Data Analyst Agent
-- Date: 2025-10-31

-- =====================================================
-- EXECUTIVE DASHBOARD - OVERALL PERFORMANCE METRICS
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.executive_dashboard` AS
WITH current_period AS (
  SELECT
    COUNT(DISTINCT caption_id) as total_active_captions,
    COUNT(DISTINCT page_name) as total_active_creators,
    SUM(total_sends) as total_sends,
    SUM(total_conversions) as total_conversions,
    SUM(lifetime_revenue) as total_revenue,
    ROUND(SAFE_DIVIDE(SUM(total_conversions), SUM(total_reach)) * 100, 2) as overall_conversion_rate_pct,
    ROUND(SAFE_DIVIDE(SUM(lifetime_revenue), SUM(total_sends)), 2) as revenue_per_send,
    ROUND(SAFE_DIVIDE(SUM(lifetime_revenue), SUM(total_conversions)), 2) as revenue_per_conversion
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb,
  UNNEST(sample_pages_used) as page_name
  WHERE total_sends > 0
),
recent_7d AS (
  SELECT
    COUNT(DISTINCT caption_id) as captions_used_7d,
    SUM(total_sends) as sends_7d
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE last_used >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
SELECT
  cp.*,
  r.captions_used_7d,
  r.sends_7d,
  CURRENT_TIMESTAMP() as last_updated
FROM current_period cp
CROSS JOIN recent_7d r;

-- =====================================================
-- KPI SUMMARY - KEY METRICS TRACKER
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.kpi_summary` AS
SELECT
  -- Engagement Metrics
  ROUND(AVG(avg_conversion_rate) * 100, 2) as avg_conversion_rate_pct,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(50)] * 100 as median_conversion_rate_pct,
  APPROX_QUANTILES(avg_conversion_rate, 100)[OFFSET(90)] * 100 as p90_conversion_rate_pct,

  -- Revenue Metrics
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue_per_caption,
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 2) as avg_revenue_per_send,
  ROUND(SUM(lifetime_revenue), 2) as total_revenue,

  -- Efficiency Metrics
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,
  ROUND(AVG(overall_performance_score), 4) as avg_overall_performance_score,

  -- Volume Metrics
  SUM(total_sends) as total_message_volume,
  SUM(total_conversions) as total_conversions,
  COUNT(DISTINCT caption_id) as total_captions,

  -- Quality Metrics
  ROUND(100.0 * COUNTIF(validation_level IN ('high_confidence', 'multi_page_success')) / COUNT(*), 2) as pct_high_quality_captions,
  ROUND(100.0 * COUNTIF(total_conversions > 0) / COUNT(*), 2) as caption_success_rate_pct,

  CURRENT_DATE() as report_date
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0;

-- =====================================================
-- PERFORMANCE TREND - 30 DAY ROLLING
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.performance_trend_30d` AS
WITH daily_metrics AS (
  SELECT
    DATE(last_used) as metric_date,
    COUNT(DISTINCT caption_id) as captions_used,
    COUNT(DISTINCT page_name) as creators_active,
    SUM(total_sends) as daily_sends,
    SUM(total_conversions) as daily_conversions,
    SUM(lifetime_revenue) as daily_revenue,
    AVG(avg_conversion_rate) as avg_conversion_rate
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`,
  UNNEST(sample_pages_used) as page_name
  WHERE last_used >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND last_used IS NOT NULL
  GROUP BY metric_date
)
SELECT
  metric_date,
  captions_used,
  creators_active,
  daily_sends,
  daily_conversions,
  ROUND(daily_revenue, 2) as daily_revenue,
  ROUND(avg_conversion_rate * 100, 2) as avg_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(daily_revenue, daily_sends), 2) as revenue_per_send,
  -- 7-day moving averages
  ROUND(AVG(daily_revenue) OVER (ORDER BY metric_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) as revenue_7d_ma,
  ROUND(AVG(avg_conversion_rate) OVER (ORDER BY metric_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) * 100, 2) as conversion_7d_ma_pct
FROM daily_metrics
ORDER BY metric_date DESC;

-- =====================================================
-- CONTENT CATEGORY PERFORMANCE DASHBOARD
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.category_performance_dashboard` AS
SELECT
  content_category,
  COUNT(*) as total_captions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) as pct_of_captions,

  -- Performance Metrics
  ROUND(AVG(avg_conversion_rate) * 100, 2) as avg_conversion_rate_pct,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue_per_caption,
  ROUND(SUM(lifetime_revenue), 2) as total_revenue,
  ROUND(100.0 * SUM(lifetime_revenue) / SUM(SUM(lifetime_revenue)) OVER(), 2) as pct_of_revenue,

  -- Efficiency Metrics
  ROUND(AVG(SAFE_DIVIDE(lifetime_revenue, total_sends)), 2) as avg_revenue_per_send,
  ROUND(AVG(efficiency_score), 4) as avg_efficiency_score,

  -- Volume Metrics
  SUM(total_sends) as total_sends,
  SUM(total_conversions) as total_conversions,

  -- Quality Indicators
  ROUND(STDDEV(avg_conversion_rate), 4) as std_conversion_rate,
  COUNTIF(total_conversions > 0) as successful_captions,
  ROUND(100.0 * COUNTIF(total_conversions > 0) / COUNT(*), 2) as success_rate_pct,

  CURRENT_DATE() as snapshot_date
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE total_sends > 0
GROUP BY content_category
ORDER BY total_revenue DESC;

-- =====================================================
-- CREATOR PERFORMANCE LEADERBOARD
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.creator_leaderboard` AS
WITH creator_stats AS (
  SELECT
    page_name,
    COUNT(DISTINCT cb.caption_id) as captions_used,
    SUM(cb.total_sends) as total_sends,
    SUM(cb.total_conversions) as total_conversions,
    SUM(cb.lifetime_revenue) as total_revenue,
    AVG(cb.avg_conversion_rate) as avg_conversion_rate,
    ROUND(SAFE_DIVIDE(SUM(cb.lifetime_revenue), SUM(cb.total_sends)), 2) as revenue_per_send,
    ROUND(SAFE_DIVIDE(SUM(cb.total_conversions), SUM(cb.total_reach)), 4) as overall_conversion_rate,
    MAX(cb.last_used) as last_activity
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb,
  UNNEST(sample_pages_used) as page_name
  WHERE cb.total_sends > 0
  GROUP BY page_name
)
SELECT
  page_name,
  captions_used,
  total_sends,
  total_conversions,
  ROUND(total_revenue, 2) as total_revenue,
  ROUND(avg_conversion_rate * 100, 2) as avg_conversion_rate_pct,
  revenue_per_send,
  ROUND(overall_conversion_rate * 100, 2) as overall_conversion_rate_pct,
  DATE_DIFF(CURRENT_DATE(), DATE(last_activity), DAY) as days_since_last_activity,
  -- Rankings
  ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as revenue_rank,
  ROW_NUMBER() OVER (ORDER BY overall_conversion_rate DESC) as conversion_rank,
  ROW_NUMBER() OVER (ORDER BY revenue_per_send DESC) as efficiency_rank,
  CURRENT_DATE() as snapshot_date
FROM creator_stats
ORDER BY total_revenue DESC;

-- =====================================================
-- REAL-TIME ALERTING QUERIES
-- =====================================================

-- Alert: Data Freshness Check
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.alert_data_freshness` AS
SELECT
  'caption_bank' as table_name,
  MAX(last_used) as latest_data_timestamp,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(last_used), HOUR) as hours_stale,
  CASE
    WHEN DATE_DIFF(CURRENT_TIMESTAMP(), MAX(last_used), HOUR) > 48 THEN 'CRITICAL'
    WHEN DATE_DIFF(CURRENT_TIMESTAMP(), MAX(last_used), HOUR) > 24 THEN 'WARNING'
    ELSE 'OK'
  END as alert_status
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`

UNION ALL

SELECT
  'etl_jobs' as table_name,
  MAX(started_at) as latest_data_timestamp,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(started_at), HOUR) as hours_stale,
  CASE
    WHEN DATE_DIFF(CURRENT_TIMESTAMP(), MAX(started_at), HOUR) > 48 THEN 'CRITICAL'
    WHEN DATE_DIFF(CURRENT_TIMESTAMP(), MAX(started_at), HOUR) > 24 THEN 'WARNING'
    ELSE 'OK'
  END as alert_status
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`;

-- Alert: Performance Degradation Detection
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.alert_performance_degradation` AS
WITH recent_performance AS (
  SELECT
    AVG(avg_conversion_rate) as recent_7d_conversion
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE last_used >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND total_sends > 0
),
baseline_performance AS (
  SELECT
    AVG(avg_conversion_rate) as baseline_conversion
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE last_used >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND last_used < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND total_sends > 0
)
SELECT
  ROUND(rp.recent_7d_conversion, 4) as recent_7d_conversion_rate,
  ROUND(bp.baseline_conversion, 4) as baseline_conversion_rate,
  ROUND((rp.recent_7d_conversion - bp.baseline_conversion) / NULLIF(bp.baseline_conversion, 0) * 100, 2) as pct_change,
  CASE
    WHEN (rp.recent_7d_conversion - bp.baseline_conversion) / NULLIF(bp.baseline_conversion, 0) < -0.20 THEN 'CRITICAL'
    WHEN (rp.recent_7d_conversion - bp.baseline_conversion) / NULLIF(bp.baseline_conversion, 0) < -0.10 THEN 'WARNING'
    ELSE 'OK'
  END as alert_status,
  CURRENT_TIMESTAMP() as check_timestamp
FROM recent_performance rp
CROSS JOIN baseline_performance bp;

-- Alert: Data Quality Issues
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.alert_data_quality` AS
WITH quality_checks AS (
  SELECT
    COUNT(*) as total_captions,
    COUNTIF(conversion_score < 0 OR conversion_score > 1) as invalid_scores,
    COUNTIF(total_conversions > total_reach) as invalid_funnel,
    COUNTIF(max_revenue < min_revenue) as invalid_revenue_bounds,
    COUNTIF(last_used < first_used) as invalid_dates
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
)
SELECT
  total_captions,
  invalid_scores + invalid_funnel + invalid_revenue_bounds + invalid_dates as total_quality_issues,
  ROUND(100.0 * (invalid_scores + invalid_funnel + invalid_revenue_bounds + invalid_dates) / total_captions, 2) as pct_quality_issues,
  CASE
    WHEN (invalid_scores + invalid_funnel + invalid_revenue_bounds + invalid_dates) / total_captions > 0.05 THEN 'CRITICAL'
    WHEN (invalid_scores + invalid_funnel + invalid_revenue_bounds + invalid_dates) / total_captions > 0.01 THEN 'WARNING'
    ELSE 'OK'
  END as alert_status,
  invalid_scores,
  invalid_funnel,
  invalid_revenue_bounds,
  invalid_dates,
  CURRENT_TIMESTAMP() as check_timestamp
FROM quality_checks;

-- =====================================================
-- COHORT ANALYSIS TEMPLATE
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.caption_cohort_analysis` AS
WITH caption_cohorts AS (
  SELECT
    caption_id,
    DATE_TRUNC(DATE(first_used), MONTH) as cohort_month,
    total_sends,
    total_conversions,
    lifetime_revenue,
    avg_conversion_rate,
    content_category,
    price_tier,
    DATE_DIFF(DATE(last_used), DATE(first_used), DAY) as lifetime_days
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE first_used IS NOT NULL
    AND total_sends > 0
)
SELECT
  cohort_month,
  content_category,
  COUNT(*) as cohort_size,
  ROUND(AVG(lifetime_days), 1) as avg_lifetime_days,
  ROUND(AVG(total_sends), 2) as avg_sends_per_caption,
  ROUND(AVG(avg_conversion_rate) * 100, 2) as avg_conversion_rate_pct,
  ROUND(AVG(lifetime_revenue), 2) as avg_revenue_per_caption,
  ROUND(SUM(lifetime_revenue), 2) as total_cohort_revenue,
  COUNTIF(total_conversions > 0) as successful_captions,
  ROUND(100.0 * COUNTIF(total_conversions > 0) / COUNT(*), 2) as success_rate_pct
FROM caption_cohorts
WHERE cohort_month >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
GROUP BY cohort_month, content_category
ORDER BY cohort_month DESC, total_cohort_revenue DESC;

-- =====================================================
-- ANOMALY DETECTION QUERY
-- =====================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.anomaly_detection` AS
WITH statistics AS (
  SELECT
    AVG(avg_conversion_rate) as mean_conversion,
    STDDEV(avg_conversion_rate) as std_conversion,
    AVG(lifetime_revenue) as mean_revenue,
    STDDEV(lifetime_revenue) as std_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND avg_conversion_rate IS NOT NULL
),
z_scores AS (
  SELECT
    cb.caption_id,
    cb.caption_text,
    cb.content_category,
    cb.avg_conversion_rate,
    cb.lifetime_revenue,
    cb.total_sends,
    ROUND((cb.avg_conversion_rate - s.mean_conversion) / NULLIF(s.std_conversion, 0), 2) as z_score_conversion,
    ROUND((cb.lifetime_revenue - s.mean_revenue) / NULLIF(s.std_revenue, 0), 2) as z_score_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb, statistics s
  WHERE cb.total_sends > 0 AND cb.avg_conversion_rate IS NOT NULL
)
SELECT
  caption_id,
  SUBSTR(caption_text, 1, 100) as caption_preview,
  content_category,
  ROUND(avg_conversion_rate * 100, 2) as conversion_rate_pct,
  ROUND(lifetime_revenue, 2) as lifetime_revenue,
  total_sends,
  z_score_conversion,
  z_score_revenue,
  CASE
    WHEN ABS(z_score_conversion) > 3 OR ABS(z_score_revenue) > 3 THEN 'extreme_outlier'
    WHEN ABS(z_score_conversion) > 2 OR ABS(z_score_revenue) > 2 THEN 'outlier'
    ELSE 'normal'
  END as anomaly_classification,
  CURRENT_DATE() as detection_date
FROM z_scores
WHERE ABS(z_score_conversion) > 2 OR ABS(z_score_revenue) > 2
ORDER BY GREATEST(ABS(z_score_conversion), ABS(z_score_revenue)) DESC
LIMIT 100;

-- =====================================================
-- A/B TEST FRAMEWORK - TEMPLATE QUERY
-- =====================================================

-- Template for comparing two variants (e.g., urgency vs non-urgency)
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.ab_test_template_urgency` AS
WITH variant_a AS (
  SELECT
    COUNT(*) as n,
    AVG(avg_conversion_rate) as mean_conversion,
    STDDEV(avg_conversion_rate) as std_conversion,
    SUM(lifetime_revenue) as total_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND has_urgency = TRUE
),
variant_b AS (
  SELECT
    COUNT(*) as n,
    AVG(avg_conversion_rate) as mean_conversion,
    STDDEV(avg_conversion_rate) as std_conversion,
    SUM(lifetime_revenue) as total_revenue
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  WHERE total_sends > 0 AND has_urgency = FALSE
)
SELECT
  'Urgency=TRUE' as variant_a_name,
  a.n as variant_a_size,
  ROUND(a.mean_conversion * 100, 4) as variant_a_conversion_pct,
  ROUND(a.total_revenue, 2) as variant_a_revenue,

  'Urgency=FALSE' as variant_b_name,
  b.n as variant_b_size,
  ROUND(b.mean_conversion * 100, 4) as variant_b_conversion_pct,
  ROUND(b.total_revenue, 2) as variant_b_revenue,

  -- Effect size (percentage point difference)
  ROUND((a.mean_conversion - b.mean_conversion) * 100, 4) as conversion_diff_pct_points,
  ROUND((a.mean_conversion - b.mean_conversion) / NULLIF(b.mean_conversion, 0) * 100, 2) as pct_improvement,

  -- Pooled standard deviation for t-test
  ROUND(SQRT(((a.n - 1) * POW(a.std_conversion, 2) + (b.n - 1) * POW(b.std_conversion, 2)) / (a.n + b.n - 2)), 6) as pooled_std,

  -- T-statistic (for reference)
  ROUND((a.mean_conversion - b.mean_conversion) /
    (SQRT(((a.n - 1) * POW(a.std_conversion, 2) + (b.n - 1) * POW(b.std_conversion, 2)) / (a.n + b.n - 2)) *
     SQRT(1.0/a.n + 1.0/b.n)), 4) as t_statistic,

  CASE
    WHEN ABS((a.mean_conversion - b.mean_conversion) /
      (SQRT(((a.n - 1) * POW(a.std_conversion, 2) + (b.n - 1) * POW(b.std_conversion, 2)) / (a.n + b.n - 2)) *
       SQRT(1.0/a.n + 1.0/b.n))) > 2.576 THEN 'p < 0.01 (highly significant)'
    WHEN ABS((a.mean_conversion - b.mean_conversion) /
      (SQRT(((a.n - 1) * POW(a.std_conversion, 2) + (b.n - 1) * POW(b.std_conversion, 2)) / (a.n + b.n - 2)) *
       SQRT(1.0/a.n + 1.0/b.n))) > 1.96 THEN 'p < 0.05 (significant)'
    ELSE 'not significant'
  END as statistical_significance,

  CURRENT_DATE() as analysis_date
FROM variant_a a
CROSS JOIN variant_b b;
