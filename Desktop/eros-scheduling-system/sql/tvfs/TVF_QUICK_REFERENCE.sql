-- TVF Quick Reference Guide
-- Table-Valued Functions: analyze_trigger_performance & analyze_content_categories
-- Deployment Date: 2025-10-31

-- ============================================================================
-- TVF #1: ANALYZE_TRIGGER_PERFORMANCE
-- ============================================================================

-- Basic Usage: Find most effective psychological triggers
SELECT
  psychological_trigger,
  msg_count,
  ROUND(avg_rpr * 1000, 2) AS rpr_per_1000_recipients,
  ROUND(avg_conv * 100, 2) AS conversion_pct,
  ROUND(rpr_lift_pct, 1) AS lift_pct,
  CASE WHEN rpr_stat_sig THEN 'SIGNIFICANT' ELSE 'NOT_SIG' END AS rpr_significance,
  CASE WHEN conv_stat_sig THEN 'SIGNIFICANT' ELSE 'NOT_SIG' END AS conv_significance
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
ORDER BY rpr_lift_pct DESC;


-- Use Case 1: Identify statistically significant winners
-- Goal: Find triggers with proven performance improvement
SELECT
  psychological_trigger,
  msg_count,
  ROUND(avg_rpr, 6) AS rpr,
  ROUND(rpr_lift_pct, 2) AS rpr_lift,
  conv_ci.lower AS conv_ci_lower,
  conv_ci.upper AS conv_ci_upper
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
WHERE rpr_stat_sig = true
  AND msg_count >= 20
ORDER BY rpr_lift_pct DESC;


-- Use Case 2: Compare baseline vs trigger performance
-- Goal: Understand absolute vs relative trigger effectiveness
WITH trigger_analysis AS (
  SELECT
    psychological_trigger,
    msg_count,
    avg_rpr,
    avg_conv,
    rpr_lift_pct,
    conv_lift_pct,
    rpr_stat_sig,
    conv_stat_sig
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
)
SELECT
  psychological_trigger,
  msg_count,
  CASE
    WHEN rpr_lift_pct > 10 AND rpr_stat_sig THEN 'HIGH_PERFORMER'
    WHEN rpr_lift_pct > 0 THEN 'POSITIVE_TREND'
    WHEN rpr_lift_pct > -10 THEN 'STABLE'
    ELSE 'UNDERPERFORMER'
  END AS classification,
  ROUND(rpr_lift_pct, 1) AS lift_pct
FROM trigger_analysis
ORDER BY avg_rpr DESC;


-- Use Case 3: Track trigger confidence intervals
-- Goal: Understand statistical precision of conversion estimates
SELECT
  psychological_trigger,
  msg_count,
  ROUND(avg_conv, 4) AS point_estimate,
  ROUND(conv_ci.lower, 4) AS ci_lower_95,
  ROUND(conv_ci.upper, 4) AS ci_upper_95,
  ROUND((conv_ci.upper - conv_ci.lower) * 100, 2) AS ci_width_pct
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
WHERE msg_count >= 50
ORDER BY ci_width_pct ASC;


-- ============================================================================
-- TVF #2: ANALYZE_CONTENT_CATEGORIES
-- ============================================================================

-- Basic Usage: Analyze content category performance across price tiers
SELECT
  content_category,
  price_tier,
  msg_count,
  ROUND(avg_rpr * 1000, 2) AS rpr_per_1000,
  ROUND(avg_conv * 100, 2) AS conversion_pct,
  trend_direction,
  ROUND(trend_pct, 1) AS trend_pct,
  ROUND(price_sensitivity_corr, 3) AS price_corr,
  best_price_tier
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
ORDER BY avg_rpr DESC;


-- Use Case 1: Find optimal price tier per category
-- Goal: Maximize revenue by identifying best-performing tier
SELECT
  content_category,
  best_price_tier,
  ROUND(MAX(CASE WHEN price_tier = best_price_tier THEN avg_rpr END), 6) AS optimal_rpr,
  ROUND(MAX(CASE WHEN price_tier = best_price_tier THEN avg_conv END), 4) AS optimal_conv,
  SUM(CASE WHEN price_tier = best_price_tier THEN msg_count ELSE 0 END) AS optimal_msg_count
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
WHERE msg_count >= 5
GROUP BY content_category, best_price_tier
ORDER BY optimal_rpr DESC;


-- Use Case 2: Identify growth categories (RISING trend)
-- Goal: Find content gaining momentum for focus investment
SELECT
  content_category,
  price_tier,
  msg_count,
  ROUND(avg_rpr, 6) AS rpr,
  trend_direction,
  ROUND(trend_pct, 1) AS trend_pct,
  ROUND(price_sensitivity_corr, 3) AS price_corr
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
WHERE trend_direction = 'RISING'
  AND msg_count >= 10
ORDER BY trend_pct DESC, avg_rpr DESC;


-- Use Case 3: Analyze price sensitivity
-- Goal: Understand how price elasticity affects conversion
WITH price_analysis AS (
  SELECT
    content_category,
    price_tier,
    msg_count,
    avg_conv,
    price_sensitivity_corr,
    CASE
      WHEN price_sensitivity_corr > 0.3 THEN 'PRICE_INSENSITIVE'
      WHEN price_sensitivity_corr > 0 THEN 'SLIGHT_POSITIVE'
      WHEN price_sensitivity_corr > -0.3 THEN 'SLIGHT_NEGATIVE'
      ELSE 'PRICE_SENSITIVE'
    END AS price_elasticity
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
  WHERE msg_count >= 5
    AND price_sensitivity_corr IS NOT NULL
)
SELECT
  content_category,
  price_tier,
  ROUND(avg_conv * 100, 2) AS conversion_pct,
  ROUND(price_sensitivity_corr, 3) AS corr,
  price_elasticity
FROM price_analysis
ORDER BY price_sensitivity_corr DESC;


-- Use Case 4: Trend analysis by category
-- Goal: Track performance momentum across time periods
SELECT
  content_category,
  price_tier,
  msg_count,
  ROUND(avg_rpr * 1000, 3) AS rpr_per_1000,
  trend_direction,
  ROUND(trend_pct, 1) AS trend_pct,
  CASE
    WHEN trend_pct > 50 THEN 'STRONG_RISE'
    WHEN trend_pct > 0 THEN 'MODERATE_RISE'
    WHEN trend_pct > -50 THEN 'MODERATE_DECLINE'
    ELSE 'STRONG_DECLINE'
  END AS momentum
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
WHERE trend_direction != 'STABLE'
ORDER BY trend_pct DESC;


-- ============================================================================
-- CROSS-TVF ANALYSIS
-- ============================================================================

-- Use Case: Optimal Strategy - Combine Triggers with Rising Categories
-- Goal: Use high-lift triggers on rising content categories
WITH top_triggers AS (
  SELECT psychological_trigger
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
  WHERE rpr_lift_pct > 10 AND msg_count >= 20
),
rising_categories AS (
  SELECT content_category, price_tier, trend_pct
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
  WHERE trend_direction = 'RISING' AND msg_count >= 10
)
SELECT
  tt.psychological_trigger,
  rc.content_category,
  rc.price_tier,
  'RECOMMENDED_COMBINATION' AS strategy
FROM top_triggers tt
CROSS JOIN rising_categories rc;


-- Use Case: Revenue Optimization Matrix
-- Goal: Identify high RPR + high conversion combinations
WITH trigger_perf AS (
  SELECT
    psychological_trigger,
    avg_rpr AS trigger_rpr,
    avg_conv AS trigger_conv,
    rpr_lift_pct
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance('itskassielee_paid', 90)
  WHERE msg_count >= 30
),
category_perf AS (
  SELECT
    content_category,
    price_tier,
    avg_rpr AS category_rpr,
    avg_conv AS category_conv,
    best_price_tier
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories('itskassielee_paid', 90)
  WHERE msg_count >= 10
)
SELECT
  tp.psychological_trigger,
  cp.content_category,
  cp.price_tier,
  ROUND(tp.trigger_rpr, 6) AS trigger_rpr,
  ROUND(cp.category_rpr, 6) AS category_rpr,
  ROUND(tp.trigger_rpr + cp.category_rpr, 6) AS combined_expected_rpr,
  ROUND(tp.rpr_lift_pct, 1) AS trigger_lift,
  cp.best_price_tier AS optimal_tier
FROM trigger_perf tp
CROSS JOIN category_perf cp
WHERE tp.trigger_rpr > 0
  AND cp.category_rpr > 0
ORDER BY combined_expected_rpr DESC;


-- ============================================================================
-- MONITORING & DIAGNOSTICS
-- ============================================================================

-- Diagnostic: Check function availability
SELECT
  routine_name,
  routine_type,
  DATE(CURRENT_TIMESTAMP()) AS check_date
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('analyze_trigger_performance', 'analyze_content_categories')
ORDER BY routine_name;


-- Diagnostic: Data quality check
-- Verify sufficient data for analysis
SELECT
  'mass_messages' AS table_name,
  COUNT(*) AS total_records,
  COUNT(DISTINCT page_name) AS unique_pages,
  COUNT(DISTINCT message) AS unique_messages,
  MIN(sending_time) AS earliest_date,
  MAX(sending_time) AS latest_date,
  DATE_DIFF(CURRENT_DATE(), DATE(MAX(sending_time)), DAY) AS days_since_latest
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE viewed_count > 0 AND sent_count > 0;


-- Diagnostic: Enrichment coverage
-- Check caption_bank_enriched coverage
SELECT
  COUNT(DISTINCT cb.caption_key) AS enriched_captions,
  COUNT(DISTINCT mm.message) AS total_messages_sent,
  ROUND(100 * COUNT(DISTINCT cb.caption_key) / COUNT(DISTINCT mm.message), 2) AS coverage_pct
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank_enriched` cb
  ON `of-scheduler-proj.eros_scheduling_brain`.caption_key(mm.message) = cb.caption_key;


-- ============================================================================
-- REPORTING TEMPLATES
-- ============================================================================

-- Daily Report Template: Trigger Performance Summary
DECLARE analysis_page STRING DEFAULT 'itskassielee_paid';
DECLARE lookback_days INT64 DEFAULT 7;

SELECT
  FORMAT_DATE('%Y-%m-%d', CURRENT_DATE()) AS report_date,
  analysis_page AS page_analyzed,
  lookback_days AS lookback_window,
  COUNT(*) AS num_triggers,
  SUM(msg_count) AS total_messages,
  ROUND(MAX(rpr_lift_pct), 2) AS max_lift_pct,
  ROUND(MIN(rpr_lift_pct), 2) AS min_lift_pct,
  COUNTIF(rpr_stat_sig) AS significant_results
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance(analysis_page, lookback_days);


-- Weekly Report Template: Category Performance Summary
DECLARE analysis_page STRING DEFAULT 'itskassielee_paid';
DECLARE lookback_days INT64 DEFAULT 30;

SELECT
  'WEEKLY_CATEGORY_REPORT' AS report_type,
  FORMAT_DATE('%Y-%m-%d', CURRENT_DATE()) AS report_date,
  COUNT(DISTINCT content_category) AS categories_analyzed,
  COUNT(DISTINCT CONCAT(content_category, '|', price_tier)) AS category_tier_combos,
  SUM(msg_count) AS total_messages,
  ROUND(AVG(avg_rpr), 6) AS avg_rpr_across_all,
  COUNTIF(trend_direction = 'RISING') AS rising_count,
  COUNTIF(trend_direction = 'DECLINING') AS declining_count,
  COUNTIF(trend_direction = 'STABLE') AS stable_count
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories(analysis_page, lookback_days);
