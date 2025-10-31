--------------------------------------------------------------------------------
-- EROS Platform v2 - Deployment Monitoring Queries
--
-- Description: Comprehensive health check and monitoring queries
--   - Daily health checks
--   - Performance monitoring
--   - Cost tracking
--   - EMV improvement tracking
--
-- Usage:
--   bq query --use_legacy_sql=false < monitor_deployment.sql
--   OR run individual sections as needed
--
-- Author: Deployment Engineer
-- Version: 1.0
-- Date: 2025-10-31
--------------------------------------------------------------------------------

-- NOTE: Replace PROJECT_ID and DATASET with your actual values before running
-- You can use environment variables or set them at runtime:
-- bq query --use_legacy_sql=false --parameter=project_id:STRING:your-project-id ...

--------------------------------------------------------------------------------
-- SECTION 1: DAILY HEALTH CHECKS
--------------------------------------------------------------------------------

-- Health Check 1: Table Row Counts
-- Verify all tables have expected data
SELECT 'Table Row Counts' as check_name;

SELECT
  'caption_bank' as table_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT caption_id) as unique_captions,
  COUNTIF(is_active = TRUE) as active_captions,
  CURRENT_TIMESTAMP() as checked_at
FROM `PROJECT_ID.DATASET.caption_bank`

UNION ALL

SELECT
  'caption_bandit_stats' as table_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT caption_id) as unique_captions,
  NULL as active_captions,
  CURRENT_TIMESTAMP() as checked_at
FROM `PROJECT_ID.DATASET.caption_bandit_stats`

UNION ALL

SELECT
  'active_caption_assignments' as table_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT account_id) as unique_accounts,
  NULL as active_captions,
  CURRENT_TIMESTAMP() as checked_at
FROM `PROJECT_ID.DATASET.active_caption_assignments`;

--------------------------------------------------------------------------------

-- Health Check 2: Data Integrity
-- Check for data corruption or invalid values
SELECT 'Data Integrity Check' as check_name;

SELECT
  'Invalid Wilson Scores' as issue_type,
  COUNT(*) as affected_rows,
  'caption_bandit_stats' as table_name
FROM `PROJECT_ID.DATASET.caption_bandit_stats`
WHERE wilson_score_lower_bound < 0
   OR wilson_score_lower_bound > 1
   OR wilson_score_lower_bound IS NULL

UNION ALL

SELECT
  'Negative View Counts' as issue_type,
  COUNT(*) as affected_rows,
  'caption_bandit_stats' as table_name
FROM `PROJECT_ID.DATASET.caption_bandit_stats`
WHERE total_views < 0

UNION ALL

SELECT
  'Negative Engagement Counts' as issue_type,
  COUNT(*) as affected_rows,
  'caption_bandit_stats' as table_name
FROM `PROJECT_ID.DATASET.caption_bandit_stats`
WHERE engagement_count < 0

UNION ALL

SELECT
  'Engagement > Views' as issue_type,
  COUNT(*) as affected_rows,
  'caption_bandit_stats' as table_name
FROM `PROJECT_ID.DATASET.caption_bandit_stats`
WHERE engagement_count > total_views

UNION ALL

SELECT
  'Missing Caption Text' as issue_type,
  COUNT(*) as affected_rows,
  'caption_bank' as table_name
FROM `PROJECT_ID.DATASET.caption_bank`
WHERE caption_text IS NULL
   OR LENGTH(TRIM(caption_text)) = 0;

-- Expected result: All counts should be 0

--------------------------------------------------------------------------------

-- Health Check 3: Caption Distribution Health
-- Verify caption assignments are balanced
SELECT 'Caption Distribution Health' as check_name;

WITH distribution_stats AS (
  SELECT
    c.caption_id,
    c.category,
    s.total_views,
    s.engagement_count,
    s.wilson_score_lower_bound,
    COUNT(DISTINCT a.account_id) as assignment_count
  FROM `PROJECT_ID.DATASET.caption_bank` c
  LEFT JOIN `PROJECT_ID.DATASET.caption_bandit_stats` s
    ON c.caption_id = s.caption_id
  LEFT JOIN `PROJECT_ID.DATASET.active_caption_assignments` a
    ON c.caption_id = a.caption_id
  WHERE c.is_active = TRUE
  GROUP BY c.caption_id, c.category, s.total_views, s.engagement_count, s.wilson_score_lower_bound
)
SELECT
  'Total Active Captions' as metric,
  COUNT(*) as value,
  NULL as category
FROM distribution_stats

UNION ALL

SELECT
  'Captions with Assignments' as metric,
  COUNT(*) as value,
  NULL as category
FROM distribution_stats
WHERE assignment_count > 0

UNION ALL

SELECT
  'Captions Never Assigned' as metric,
  COUNT(*) as value,
  NULL as category
FROM distribution_stats
WHERE assignment_count = 0

UNION ALL

SELECT
  'High Performing Captions (Wilson > 0.7)' as metric,
  COUNT(*) as value,
  NULL as category
FROM distribution_stats
WHERE wilson_score_lower_bound > 0.7

UNION ALL

SELECT
  'Low Performing Captions (Wilson < 0.3)' as metric,
  COUNT(*) as value,
  NULL as category
FROM distribution_stats
WHERE wilson_score_lower_bound < 0.3
  AND total_views >= 30;  -- Only count captions with sufficient data

--------------------------------------------------------------------------------

-- Health Check 4: Caption Locks Status
-- Monitor active locks and detect potential issues
SELECT 'Caption Locks Status' as check_name;

SELECT
  COUNT(*) as total_active_locks,
  COUNT(DISTINCT caption_id) as unique_locked_captions,
  COUNT(DISTINCT account_id) as unique_accounts_with_locks,
  MIN(locked_at) as oldest_lock,
  MAX(expires_at) as latest_expiration,
  COUNTIF(expires_at < CURRENT_TIMESTAMP()) as expired_locks_needing_cleanup
FROM `PROJECT_ID.DATASET.caption_locks`
WHERE expires_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR);

-- Note: expired_locks_needing_cleanup should be 0 if cleanup is running properly

--------------------------------------------------------------------------------
-- SECTION 2: PERFORMANCE MONITORING
--------------------------------------------------------------------------------

-- Performance Check 1: Query Response Times
-- Monitor average query execution times
SELECT 'Query Performance Metrics' as check_name;

SELECT
  query_type,
  COUNT(*) as total_queries,
  AVG(duration_ms) as avg_duration_ms,
  MIN(duration_ms) as min_duration_ms,
  MAX(duration_ms) as max_duration_ms,
  APPROX_QUANTILES(duration_ms, 100)[OFFSET(50)] as p50_duration_ms,
  APPROX_QUANTILES(duration_ms, 100)[OFFSET(95)] as p95_duration_ms,
  APPROX_QUANTILES(duration_ms, 100)[OFFSET(99)] as p99_duration_ms,
  COUNTIF(success = FALSE) as failed_queries,
  SAFE_DIVIDE(COUNTIF(success = FALSE), COUNT(*)) * 100 as failure_rate_pct
FROM `PROJECT_ID.DATASET.query_performance_log`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY query_type
ORDER BY avg_duration_ms DESC;

-- Target: p95 < 1000ms for most query types, failure rate < 1%

--------------------------------------------------------------------------------

-- Performance Check 2: Wilson Score Calculation Performance
-- Verify Wilson score calculations are completing in reasonable time
SELECT 'Wilson Score Calculation Performance' as check_name;

WITH recent_updates AS (
  SELECT
    caption_id,
    total_views,
    engagement_count,
    wilson_score_lower_bound,
    last_updated
  FROM `PROJECT_ID.DATASET.caption_bandit_stats`
  WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
)
SELECT
  COUNT(*) as captions_updated_last_hour,
  AVG(total_views) as avg_views,
  AVG(engagement_count) as avg_engagements,
  AVG(wilson_score_lower_bound) as avg_wilson_score,
  MIN(last_updated) as earliest_update,
  MAX(last_updated) as latest_update
FROM recent_updates;

--------------------------------------------------------------------------------

-- Performance Check 3: Caption Selection Performance
-- Monitor caption selection efficiency
SELECT 'Caption Selection Efficiency' as check_name;

WITH selection_stats AS (
  SELECT
    s.caption_id,
    s.total_views,
    s.wilson_score_lower_bound,
    COUNT(DISTINCT a.account_id) as times_selected
  FROM `PROJECT_ID.DATASET.caption_bandit_stats` s
  LEFT JOIN `PROJECT_ID.DATASET.active_caption_assignments` a
    ON s.caption_id = a.caption_id
  WHERE s.total_views > 0
  GROUP BY s.caption_id, s.total_views, s.wilson_score_lower_bound
)
SELECT
  'High Performers (Wilson > 0.7)' as performance_tier,
  COUNT(*) as caption_count,
  AVG(times_selected) as avg_times_selected,
  SUM(times_selected) as total_selections
FROM selection_stats
WHERE wilson_score_lower_bound > 0.7

UNION ALL

SELECT
  'Medium Performers (0.4-0.7)' as performance_tier,
  COUNT(*) as caption_count,
  AVG(times_selected) as avg_times_selected,
  SUM(times_selected) as total_selections
FROM selection_stats
WHERE wilson_score_lower_bound BETWEEN 0.4 AND 0.7

UNION ALL

SELECT
  'Low Performers (< 0.4)' as performance_tier,
  COUNT(*) as caption_count,
  AVG(times_selected) as avg_times_selected,
  SUM(times_selected) as total_selections
FROM selection_stats
WHERE wilson_score_lower_bound < 0.4

UNION ALL

SELECT
  'Untested (< 10 views)' as performance_tier,
  COUNT(*) as caption_count,
  AVG(times_selected) as avg_times_selected,
  SUM(times_selected) as total_selections
FROM selection_stats
WHERE total_views < 10;

-- Ideal: High exploration of untested captions, while exploiting high performers

--------------------------------------------------------------------------------

-- Performance Check 4: Account Size Classification Distribution
-- Verify account classification is working correctly
SELECT 'Account Size Classification Distribution' as check_name;

SELECT
  account_size_category,
  COUNT(*) as account_count,
  AVG(follower_count) as avg_followers,
  AVG(avg_engagement_rate) as avg_engagement_rate,
  MIN(follower_count) as min_followers,
  MAX(follower_count) as max_followers
FROM `PROJECT_ID.DATASET.account_metrics`
WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY account_size_category
ORDER BY AVG(follower_count) ASC;

--------------------------------------------------------------------------------
-- SECTION 3: COST TRACKING
--------------------------------------------------------------------------------

-- Cost Check 1: Daily Query Costs
-- Track BigQuery costs over time
SELECT 'Daily Query Costs' as check_name;

SELECT
  DATE(start_time) as query_date,
  query_type,
  COUNT(*) as total_queries,
  SUM(bytes_processed) as total_bytes_processed,
  SUM(bytes_billed) as total_bytes_billed,
  -- BigQuery pricing: $5 per TB processed
  ROUND(SUM(bytes_billed) / POW(10, 12) * 5, 2) as estimated_cost_usd,
  SUM(slot_ms) / 1000 as total_slot_seconds
FROM `PROJECT_ID.DATASET.query_performance_log`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY query_date, query_type
ORDER BY query_date DESC, estimated_cost_usd DESC;

-- Target: Track daily costs, aim for < 5% increase week-over-week

--------------------------------------------------------------------------------

-- Cost Check 2: Top Cost Drivers
-- Identify most expensive queries
SELECT 'Top Cost Drivers (Last 24 Hours)' as check_name;

SELECT
  query_type,
  COUNT(*) as query_count,
  SUM(bytes_billed) as total_bytes_billed,
  AVG(bytes_billed) as avg_bytes_billed,
  ROUND(SUM(bytes_billed) / POW(10, 12) * 5, 2) as estimated_cost_usd,
  SUM(slot_ms) / 1000 as total_slot_seconds,
  AVG(duration_ms) as avg_duration_ms
FROM `PROJECT_ID.DATASET.query_performance_log`
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY query_type
ORDER BY estimated_cost_usd DESC
LIMIT 10;

--------------------------------------------------------------------------------

-- Cost Check 3: Storage Costs
-- Monitor table storage growth
SELECT 'Table Storage Costs' as check_name;

SELECT
  table_name,
  -- Storage pricing: $0.02 per GB per month (active), $0.01 per GB (long-term)
  ROUND(size_bytes / POW(10, 9), 2) as size_gb,
  ROUND(size_bytes / POW(10, 9) * 0.02, 2) as monthly_storage_cost_usd,
  row_count,
  TIMESTAMP_MILLIS(creation_time) as created_at,
  TIMESTAMP_MILLIS(CAST(last_modified_time AS INT64)) as last_modified
FROM `PROJECT_ID.DATASET.__TABLES__`
WHERE table_id IN ('caption_bank', 'caption_bandit_stats', 'active_caption_assignments',
                   'caption_locks', 'account_metrics', 'query_performance_log')
ORDER BY size_bytes DESC;

--------------------------------------------------------------------------------

-- Cost Check 4: Cost Optimization Opportunities
-- Identify potential cost savings
SELECT 'Cost Optimization Opportunities' as check_name;

WITH query_efficiency AS (
  SELECT
    query_type,
    AVG(bytes_billed) as avg_bytes,
    AVG(duration_ms) as avg_duration,
    COUNT(*) as query_count
  FROM `PROJECT_ID.DATASET.query_performance_log`
  WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY query_type
)
SELECT
  query_type,
  query_count,
  ROUND(avg_bytes / POW(10, 6), 2) as avg_mb_per_query,
  ROUND(avg_duration, 0) as avg_ms,
  ROUND(avg_bytes / POW(10, 12) * 5 * query_count, 2) as total_cost_usd,
  CASE
    WHEN avg_bytes > 100 * POW(10, 6) THEN 'High data volume - consider caching or materialized views'
    WHEN avg_duration > 5000 THEN 'Slow queries - review query optimization'
    WHEN query_count > 10000 THEN 'High frequency - consider batching'
    ELSE 'Optimized'
  END as recommendation
FROM query_efficiency
ORDER BY total_cost_usd DESC;

--------------------------------------------------------------------------------
-- SECTION 4: EMV IMPROVEMENT TRACKING
--------------------------------------------------------------------------------

-- EMV Check 1: Overall EMV Performance
-- Track Expected Monetary Value improvements
SELECT 'Overall EMV Performance' as check_name;

WITH daily_emv AS (
  SELECT
    DATE(last_updated) as performance_date,
    AVG(wilson_score_lower_bound) as avg_wilson_score,
    AVG(SAFE_DIVIDE(engagement_count, total_views)) as avg_engagement_rate,
    SUM(total_views) as total_views,
    SUM(engagement_count) as total_engagements
  FROM `PROJECT_ID.DATASET.caption_bandit_stats`
  WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND total_views >= 10  -- Only include captions with sufficient data
  GROUP BY performance_date
)
SELECT
  performance_date,
  avg_wilson_score,
  avg_engagement_rate,
  total_views,
  total_engagements,
  -- EMV approximation: engagement_rate * total_views
  avg_engagement_rate * total_views as estimated_emv
FROM daily_emv
ORDER BY performance_date DESC;

-- Target: 10%+ improvement in avg_engagement_rate after deployment

--------------------------------------------------------------------------------

-- EMV Check 2: Top Performing Captions
-- Identify highest value captions
SELECT 'Top Performing Captions (Last 7 Days)' as check_name;

SELECT
  c.caption_id,
  c.category,
  LEFT(c.caption_text, 100) as caption_preview,
  s.total_views,
  s.engagement_count,
  ROUND(SAFE_DIVIDE(s.engagement_count, s.total_views), 4) as engagement_rate,
  s.wilson_score_lower_bound,
  -- EMV = engagement_rate * potential_reach (simplified)
  ROUND(SAFE_DIVIDE(s.engagement_count, s.total_views) * s.total_views, 2) as emv_score,
  COUNT(DISTINCT a.account_id) as times_assigned
FROM `PROJECT_ID.DATASET.caption_bank` c
JOIN `PROJECT_ID.DATASET.caption_bandit_stats` s
  ON c.caption_id = s.caption_id
LEFT JOIN `PROJECT_ID.DATASET.active_caption_assignments` a
  ON c.caption_id = a.caption_id
WHERE s.last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND s.total_views >= 30  -- Require statistical significance
GROUP BY c.caption_id, c.category, c.caption_text, s.total_views,
         s.engagement_count, s.wilson_score_lower_bound
ORDER BY emv_score DESC
LIMIT 20;

--------------------------------------------------------------------------------

-- EMV Check 3: Category Performance Comparison
-- Compare EMV across caption categories
SELECT 'Category Performance Comparison' as check_name;

SELECT
  c.category,
  COUNT(DISTINCT c.caption_id) as caption_count,
  AVG(s.total_views) as avg_views,
  AVG(s.engagement_count) as avg_engagements,
  AVG(SAFE_DIVIDE(s.engagement_count, s.total_views)) as avg_engagement_rate,
  AVG(s.wilson_score_lower_bound) as avg_wilson_score,
  SUM(s.total_views) as total_category_views,
  SUM(s.engagement_count) as total_category_engagements
FROM `PROJECT_ID.DATASET.caption_bank` c
JOIN `PROJECT_ID.DATASET.caption_bandit_stats` s
  ON c.caption_id = s.caption_id
WHERE c.is_active = TRUE
  AND s.total_views > 0
GROUP BY c.category
ORDER BY avg_engagement_rate DESC;

--------------------------------------------------------------------------------

-- EMV Check 4: Week-over-Week Improvement
-- Calculate week-over-week EMV growth
SELECT 'Week-over-Week EMV Improvement' as check_name;

WITH weekly_performance AS (
  SELECT
    DATE_TRUNC(DATE(last_updated), WEEK) as week_start,
    AVG(wilson_score_lower_bound) as avg_wilson_score,
    AVG(SAFE_DIVIDE(engagement_count, total_views)) as avg_engagement_rate,
    SUM(total_views) as total_views,
    SUM(engagement_count) as total_engagements
  FROM `PROJECT_ID.DATASET.caption_bandit_stats`
  WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 8 WEEK)
    AND total_views >= 10
  GROUP BY week_start
),
with_previous AS (
  SELECT
    week_start,
    avg_wilson_score,
    avg_engagement_rate,
    total_views,
    total_engagements,
    LAG(avg_engagement_rate) OVER (ORDER BY week_start) as prev_week_engagement_rate,
    LAG(avg_wilson_score) OVER (ORDER BY week_start) as prev_week_wilson_score
  FROM weekly_performance
)
SELECT
  week_start,
  ROUND(avg_engagement_rate, 4) as engagement_rate,
  ROUND(avg_wilson_score, 4) as wilson_score,
  total_views,
  total_engagements,
  ROUND((avg_engagement_rate - prev_week_engagement_rate) / NULLIF(prev_week_engagement_rate, 0) * 100, 2) as engagement_rate_change_pct,
  ROUND((avg_wilson_score - prev_week_wilson_score) / NULLIF(prev_week_wilson_score, 0) * 100, 2) as wilson_score_change_pct
FROM with_previous
WHERE prev_week_engagement_rate IS NOT NULL
ORDER BY week_start DESC;

-- Target: Positive week-over-week growth after deployment

--------------------------------------------------------------------------------

-- EMV Check 5: Account-Level EMV Analysis
-- Track EMV by account size category
SELECT 'Account-Level EMV Analysis' as check_name;

WITH account_performance AS (
  SELECT
    m.account_size_category,
    a.account_id,
    a.caption_id,
    s.total_views,
    s.engagement_count,
    s.wilson_score_lower_bound
  FROM `PROJECT_ID.DATASET.active_caption_assignments` a
  JOIN `PROJECT_ID.DATASET.account_metrics` m
    ON a.account_id = m.account_id
  JOIN `PROJECT_ID.DATASET.caption_bandit_stats` s
    ON a.caption_id = s.caption_id
  WHERE m.last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
SELECT
  account_size_category,
  COUNT(DISTINCT account_id) as account_count,
  COUNT(DISTINCT caption_id) as unique_captions_used,
  AVG(wilson_score_lower_bound) as avg_wilson_score,
  AVG(SAFE_DIVIDE(engagement_count, total_views)) as avg_engagement_rate,
  SUM(total_views) as total_views,
  SUM(engagement_count) as total_engagements
FROM account_performance
GROUP BY account_size_category
ORDER BY
  CASE account_size_category
    WHEN 'mega' THEN 1
    WHEN 'macro' THEN 2
    WHEN 'mid_tier' THEN 3
    WHEN 'micro' THEN 4
    WHEN 'nano_high_engagement' THEN 5
    WHEN 'nano' THEN 6
    ELSE 7
  END;

--------------------------------------------------------------------------------
-- SECTION 5: DEPLOYMENT SUCCESS METRICS
--------------------------------------------------------------------------------

-- Success Metric 1: Deployment Stability
-- Verify no increase in errors post-deployment
SELECT 'Deployment Stability Check' as check_name;

WITH error_rates AS (
  SELECT
    DATE(start_time) as query_date,
    COUNT(*) as total_queries,
    COUNTIF(success = FALSE) as failed_queries,
    SAFE_DIVIDE(COUNTIF(success = FALSE), COUNT(*)) * 100 as error_rate_pct
  FROM `PROJECT_ID.DATASET.query_performance_log`
  WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
  GROUP BY query_date
)
SELECT
  query_date,
  total_queries,
  failed_queries,
  ROUND(error_rate_pct, 2) as error_rate_pct,
  CASE
    WHEN error_rate_pct > 5 THEN 'ALERT: High error rate'
    WHEN error_rate_pct > 2 THEN 'WARNING: Elevated errors'
    ELSE 'OK'
  END as status
FROM error_rates
ORDER BY query_date DESC;

-- Target: Error rate < 1%

--------------------------------------------------------------------------------

-- Success Metric 2: Deployment Impact Summary
-- Overall deployment success evaluation
SELECT 'Deployment Impact Summary' as check_name;

WITH pre_deployment AS (
  SELECT
    AVG(SAFE_DIVIDE(engagement_count, total_views)) as engagement_rate,
    AVG(wilson_score_lower_bound) as wilson_score
  FROM `PROJECT_ID.DATASET.caption_bandit_stats`
  WHERE last_updated < TIMESTAMP('2025-10-31 00:00:00')  -- Replace with actual deployment date
    AND total_views >= 30
),
post_deployment AS (
  SELECT
    AVG(SAFE_DIVIDE(engagement_count, total_views)) as engagement_rate,
    AVG(wilson_score_lower_bound) as wilson_score
  FROM `PROJECT_ID.DATASET.caption_bandit_stats`
  WHERE last_updated >= TIMESTAMP('2025-10-31 00:00:00')  -- Replace with actual deployment date
    AND total_views >= 30
)
SELECT
  'Pre-Deployment' as period,
  ROUND(pre.engagement_rate, 4) as avg_engagement_rate,
  ROUND(pre.wilson_score, 4) as avg_wilson_score,
  NULL as improvement_pct
FROM pre_deployment pre

UNION ALL

SELECT
  'Post-Deployment' as period,
  ROUND(post.engagement_rate, 4) as avg_engagement_rate,
  ROUND(post.wilson_score, 4) as avg_wilson_score,
  ROUND((post.engagement_rate - pre.engagement_rate) / NULLIF(pre.engagement_rate, 0) * 100, 2) as improvement_pct
FROM pre_deployment pre, post_deployment post;

-- Target: 10%+ improvement in engagement_rate

--------------------------------------------------------------------------------

-- Success Metric 3: System Health Score
-- Overall health score (0-100)
SELECT 'System Health Score' as check_name;

WITH health_metrics AS (
  SELECT
    -- Data integrity (20 points)
    CASE
      WHEN (SELECT COUNT(*) FROM `PROJECT_ID.DATASET.caption_bandit_stats`
            WHERE wilson_score_lower_bound < 0 OR wilson_score_lower_bound > 1) = 0
      THEN 20 ELSE 0
    END as integrity_score,

    -- Performance (20 points)
    CASE
      WHEN (SELECT AVG(duration_ms) FROM `PROJECT_ID.DATASET.query_performance_log`
            WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)) < 1000
      THEN 20 ELSE 10
    END as performance_score,

    -- Error rate (20 points)
    CASE
      WHEN (SELECT SAFE_DIVIDE(COUNTIF(success = FALSE), COUNT(*)) FROM `PROJECT_ID.DATASET.query_performance_log`
            WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) < 0.01
      THEN 20 ELSE 5
    END as error_rate_score,

    -- EMV improvement (20 points)
    CASE
      WHEN (SELECT AVG(wilson_score_lower_bound) FROM `PROJECT_ID.DATASET.caption_bandit_stats`
            WHERE total_views >= 30) > 0.5
      THEN 20 ELSE 10
    END as emv_score,

    -- System availability (20 points)
    20 as availability_score  -- Assume 100% if queries are running
)
SELECT
  integrity_score,
  performance_score,
  error_rate_score,
  emv_score,
  availability_score,
  (integrity_score + performance_score + error_rate_score + emv_score + availability_score) as total_health_score,
  CASE
    WHEN (integrity_score + performance_score + error_rate_score + emv_score + availability_score) >= 90 THEN 'EXCELLENT'
    WHEN (integrity_score + performance_score + error_rate_score + emv_score + availability_score) >= 75 THEN 'GOOD'
    WHEN (integrity_score + performance_score + error_rate_score + emv_score + availability_score) >= 60 THEN 'FAIR'
    ELSE 'NEEDS ATTENTION'
  END as health_status
FROM health_metrics;

-- Target: Health score >= 90

--------------------------------------------------------------------------------
-- END OF MONITORING QUERIES
--------------------------------------------------------------------------------

-- USAGE INSTRUCTIONS:
--
-- 1. Run daily health checks:
--    Run sections 1 and 5 every morning
--
-- 2. Monitor performance:
--    Run section 2 during business hours or if issues reported
--
-- 3. Track costs:
--    Run section 3 weekly for cost review meetings
--
-- 4. Measure deployment success:
--    Run section 4 daily for first week, then weekly
--
-- 5. Create automated monitoring:
--    Schedule these queries as BigQuery scheduled queries
--    Set up alerts for critical metrics
--
-- 6. Export results:
--    bq query --use_legacy_sql=false --format=csv < monitor_deployment.sql > results.csv
--
--------------------------------------------------------------------------------
