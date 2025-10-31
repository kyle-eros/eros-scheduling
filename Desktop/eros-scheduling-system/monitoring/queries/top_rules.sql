/**
 * TOP RULES MONITORING QUERY
 *
 * PURPOSE:
 * Identify the top 10 most impactful HARD restriction rules by block count (last 7 days).
 * Helps identify overly aggressive rules that may need adjustment.
 * Note: Only HARD restrictions are analyzed (SOFT restrictions don't block from pool).
 *
 * METRICS:
 * - total_blocks: Number of captions blocked by this HARD rule
 * - affected_creators: Number of creators impacted
 * - avg_blocks_per_creator: Average blocks per creator
 * - block_rate_trend: 7-day trend (increasing/decreasing/stable)
 *
 * USE CASES:
 * - Identify HARD rules causing pool exhaustion
 * - Find HARD rules that may be too broad
 * - Discover HARD rules affecting multiple creators
 *
 * RUN FREQUENCY:
 * - Weekly (automated report)
 * - On-demand when investigating restriction impact
 */

WITH
-- Get filter events from last 7 days (HARD restrictions only)
recent_filters AS (
  SELECT
    page_name,
    rule_type,
    rule_value,
    caption_id,
    filtered_at,
    DATE(filtered_at) as filter_date
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log`
  WHERE filtered_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND action = 'filtered'
    AND enforcement = 'HARD'  -- Only analyze HARD restrictions
),

-- Aggregate by rule
rule_impact AS (
  SELECT
    rule_type,
    rule_value,
    COUNT(DISTINCT caption_id) as total_blocks,
    COUNT(DISTINCT page_name) as affected_creators,
    SAFE_DIVIDE(COUNT(DISTINCT caption_id), COUNT(DISTINCT page_name)) as avg_blocks_per_creator,
    ARRAY_AGG(DISTINCT page_name ORDER BY page_name LIMIT 10) as sample_creators,
    MIN(filtered_at) as first_block_time,
    MAX(filtered_at) as last_block_time
  FROM recent_filters
  GROUP BY rule_type, rule_value
),

-- Calculate daily trend
daily_rule_blocks AS (
  SELECT
    rule_type,
    rule_value,
    filter_date,
    COUNT(DISTINCT caption_id) as daily_blocks
  FROM recent_filters
  GROUP BY rule_type, rule_value, filter_date
),

-- Calculate 7-day trend direction
rule_trend AS (
  SELECT
    rule_type,
    rule_value,

    -- Compare first 3 days vs last 3 days
    AVG(CASE WHEN filter_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) THEN daily_blocks END) as recent_avg,
    AVG(CASE WHEN filter_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY) THEN daily_blocks END) as earlier_avg,

    -- Trend direction
    CASE
      WHEN AVG(CASE WHEN filter_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) THEN daily_blocks END) >
           AVG(CASE WHEN filter_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY) THEN daily_blocks END) * 1.2
        THEN 'INCREASING'
      WHEN AVG(CASE WHEN filter_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) THEN daily_blocks END) <
           AVG(CASE WHEN filter_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY) THEN daily_blocks END) * 0.8
        THEN 'DECREASING'
      ELSE 'STABLE'
    END as trend_direction

  FROM daily_rule_blocks
  GROUP BY rule_type, rule_value
),

-- Join impact + trend
rule_summary AS (
  SELECT
    ri.rule_type,
    ri.rule_value,
    ri.total_blocks,
    ri.affected_creators,
    ROUND(ri.avg_blocks_per_creator, 2) as avg_blocks_per_creator,
    ri.sample_creators,
    rt.trend_direction,
    ROUND(rt.recent_avg, 2) as recent_daily_avg,
    ROUND(rt.earlier_avg, 2) as earlier_daily_avg,

    -- Severity assessment
    CASE
      WHEN ri.total_blocks > 500 AND ri.affected_creators > 5 THEN 'HIGH_IMPACT'
      WHEN ri.total_blocks > 200 OR ri.affected_creators > 3 THEN 'MEDIUM_IMPACT'
      ELSE 'LOW_IMPACT'
    END as impact_level,

    -- Recommendation
    CASE
      WHEN ri.total_blocks > 500 AND ri.affected_creators > 5 THEN 'REVIEW: Rule blocking >500 captions across multiple creators. Consider narrowing scope.'
      WHEN ri.total_blocks > 200 AND rt.trend_direction = 'INCREASING' THEN 'MONITOR: Block count increasing. Rule may be too aggressive.'
      WHEN ri.affected_creators = 1 AND ri.total_blocks > 100 THEN 'CREATOR_SPECIFIC: High block count for single creator. Verify rule is intended.'
      ELSE 'OK: Rule impact within normal range.'
    END as recommendation,

    ri.first_block_time,
    ri.last_block_time

  FROM rule_impact ri
  LEFT JOIN rule_trend rt
    ON ri.rule_type = rt.rule_type
    AND ri.rule_value = rt.rule_value
)

-- Final output: Top 10 rules by total blocks
SELECT
  rule_type,
  rule_value,
  total_blocks,
  affected_creators,
  avg_blocks_per_creator,
  trend_direction,
  recent_daily_avg,
  earlier_daily_avg,
  impact_level,
  recommendation,
  sample_creators,
  TIMESTAMP_DIFF(last_block_time, first_block_time, HOUR) as active_hours,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', first_block_time, 'America/Los_Angeles') as first_block,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_block_time, 'America/Los_Angeles') as last_block
FROM rule_summary
WHERE impact_level IN ('HIGH_IMPACT', 'MEDIUM_IMPACT') -- Focus on impactful rules
ORDER BY total_blocks DESC
LIMIT 10;

/**
 * USAGE:
 *
 * 1. Weekly top rules report:
 *    bq query --use_legacy_sql=false --format=prettyjson < top_rules.sql
 *
 * 2. Alert on high-impact rules:
 *    bq query --use_legacy_sql=false --format=json < top_rules.sql | \
 *      jq '.[] | select(.impact_level == "HIGH_IMPACT")' | \
 *      sendmail ops@company.com
 *
 * 3. Rule-specific investigation:
 *    Add WHERE clause: WHERE rule_type = 'regex' AND rule_value LIKE '%forbidden_term%'
 *
 * INTERPRETATION:
 * - High total_blocks + High affected_creators → Rule may be too broad
 * - High avg_blocks_per_creator → Rule very effective (or overly aggressive)
 * - Trend INCREASING → Rule blocking more over time (investigate why)
 * - affected_creators = 1 + High blocks → Creator-specific issue (not systemic)
 *
 * ACTIONABLE INSIGHTS:
 * - HIGH_IMPACT rules: Review and potentially narrow scope
 * - INCREASING trends: Monitor closely, may need adjustment
 * - Rules affecting 1 creator: Verify rule is correct and necessary
 */
