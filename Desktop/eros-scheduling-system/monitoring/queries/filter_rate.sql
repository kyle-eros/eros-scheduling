/**
 * FILTER RATE MONITORING QUERY
 *
 * PURPOSE:
 * Calculate the percentage of captions filtered by HARD restrictions per creator/day.
 * Alert if >80% of captions are being filtered (suggests overly aggressive restrictions).
 * Note: Only HARD restrictions are counted (SOFT restrictions don't block from pool).
 *
 * METRICS:
 * - filter_rate: % of captions blocked by HARD restrictions
 * - blocked_by_rule_type: Breakdown by category/price_tier/regex/caption_id
 * - trend_7d: 7-day rolling average of filter_rate
 *
 * ALERT THRESHOLD:
 * - filter_rate > 80% → Overly aggressive HARD restrictions
 * - filter_rate < 5% → HARD restrictions may not be working
 *
 * RUN FREQUENCY:
 * - Daily (automated)
 * - On-demand when investigating selection issues
 */

WITH
-- Get audit log data for last 30 days (HARD restrictions only)
filter_events AS (
  SELECT
    page_name,
    DATE(filtered_at) as filter_date,
    rule_type,
    rule_value,
    caption_id,
    workflow_id
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log`
  WHERE filtered_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND action = 'filtered'
    AND enforcement = 'HARD'  -- Only count HARD restrictions in filter rate
),

-- Aggregate by creator/day/rule
daily_filter_stats AS (
  SELECT
    page_name,
    filter_date,
    rule_type,
    rule_value,
    COUNT(DISTINCT caption_id) as captions_filtered,
    COUNT(DISTINCT workflow_id) as workflows_affected
  FROM filter_events
  GROUP BY page_name, filter_date, rule_type, rule_value
),

-- Calculate total captions considered (from workflow metadata)
daily_workflow_stats AS (
  SELECT
    page_name,
    DATE(filtered_at) as filter_date,
    workflow_id,
    -- Estimate total captions considered (assume 200 baseline for 70/20/10 selection)
    200 as total_captions_considered
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log`
  WHERE filtered_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY page_name, filter_date, workflow_id
),

-- Calculate filter rate per creator/day
daily_filter_rate AS (
  SELECT
    dfs.page_name,
    dfs.filter_date,
    SUM(dfs.captions_filtered) as total_filtered,
    MAX(dws.total_captions_considered) as total_considered,
    SAFE_DIVIDE(
      SUM(dfs.captions_filtered),
      MAX(dws.total_captions_considered)
    ) * 100 as filter_rate_pct,

    -- Breakdown by rule type (all are HARD restrictions)
    COUNTIF(dfs.rule_type = 'category') as filtered_by_category,
    COUNTIF(dfs.rule_type = 'price_tier') as filtered_by_price_tier,
    COUNTIF(dfs.rule_type = 'keyword') as filtered_by_keyword,
    COUNTIF(dfs.rule_type = 'caption_id') as filtered_by_caption_id

  FROM daily_filter_stats dfs
  LEFT JOIN daily_workflow_stats dws
    ON dfs.page_name = dws.page_name
    AND dfs.filter_date = dws.filter_date
  GROUP BY dfs.page_name, dfs.filter_date
),

-- Calculate 7-day rolling average
filter_rate_with_trend AS (
  SELECT
    page_name,
    filter_date,
    total_filtered,
    total_considered,
    filter_rate_pct,
    filtered_by_category,
    filtered_by_price_tier,
    filtered_by_keyword,
    filtered_by_caption_id,

    -- 7-day rolling average
    AVG(filter_rate_pct) OVER (
      PARTITION BY page_name
      ORDER BY filter_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as trend_7d_avg,

    -- Week-over-week change
    filter_rate_pct - LAG(filter_rate_pct, 7) OVER (
      PARTITION BY page_name
      ORDER BY filter_date
    ) as wow_change_pct

  FROM daily_filter_rate
),

-- Add status and alerts
filter_rate_with_status AS (
  SELECT
    *,
    CASE
      WHEN filter_rate_pct > 80 THEN 'CRITICAL'
      WHEN filter_rate_pct > 60 THEN 'WARNING'
      WHEN filter_rate_pct < 5 THEN 'LOW_EFFECTIVENESS'
      ELSE 'OK'
    END as status,

    CASE
      WHEN filter_rate_pct > 80 THEN 'URGENT: >80% of captions filtered. Restrictions too aggressive. Review and relax rules.'
      WHEN filter_rate_pct > 60 THEN 'WARNING: >60% of captions filtered. Consider relaxing some restrictions.'
      WHEN filter_rate_pct < 5 THEN 'INFO: <5% filtered. Verify restrictions are active and working correctly.'
      ELSE 'Filter rate healthy'
    END as alert_message

  FROM filter_rate_with_trend
)

-- Final output
SELECT
  page_name,
  filter_date,
  total_filtered,
  total_considered,
  ROUND(filter_rate_pct, 2) as filter_rate_pct,
  ROUND(trend_7d_avg, 2) as trend_7d_avg,
  ROUND(wow_change_pct, 2) as wow_change_pct,
  filtered_by_category,
  filtered_by_price_tier,
  filtered_by_keyword,
  filtered_by_caption_id,
  status,
  alert_message
FROM filter_rate_with_status
WHERE filter_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
  AND status IN ('CRITICAL', 'WARNING', 'LOW_EFFECTIVENESS') -- Only show issues
ORDER BY
  filter_date DESC,
  CASE status
    WHEN 'CRITICAL' THEN 1
    WHEN 'WARNING' THEN 2
    WHEN 'LOW_EFFECTIVENESS' THEN 3
    ELSE 4
  END,
  filter_rate_pct DESC;

/**
 * USAGE:
 *
 * 1. Daily monitoring (alert on >80% filter rate):
 *    bq query --use_legacy_sql=false --format=json < filter_rate.sql | \
 *      jq '.[] | select(.status == "CRITICAL")' | \
 *      sendmail ops@company.com
 *
 * 2. Weekly report (filter rate trends):
 *    bq query --use_legacy_sql=false --format=csv < filter_rate.sql > weekly_filter_report.csv
 *
 * 3. Creator-specific investigation:
 *    Add WHERE clause: WHERE page_name = 'jadebri'
 *
 * INTERPRETATION:
 * - filter_rate_pct > 80%: HARD restrictions blocking too many captions (pool exhaustion risk)
 * - trend_7d_avg increasing: Filter rate getting worse over time
 * - wow_change_pct > 20: Significant increase week-over-week (investigate)
 * - filtered_by_category high: Category-based blocks dominating
 * - filtered_by_keyword high: Keyword pattern blocks dominating
 */
