-- TVF Deployment Agent #2
-- Deploy: analyze_trigger_performance and analyze_content_categories TVFs
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain

-- ============================================================================
-- 1) ANALYZE_TRIGGER_PERFORMANCE TVF
-- ============================================================================
-- Purpose: Analyze psychological triggers for message performance
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: trigger analysis with statistical significance testing
-- ============================================================================

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
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
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

-- ============================================================================
-- 2) ANALYZE_CONTENT_CATEGORIES TVF
-- ============================================================================
-- Purpose: Analyze content category performance across price tiers
-- Input: page_name (STRING), lookback_days (INT64)
-- Output: category performance metrics with trend analysis
-- ============================================================================

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
      AND mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
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
      AVG(CASE WHEN sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) THEN rpr END)  AS rpr_last_30,
      AVG(CASE WHEN sending_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 60 DAY)
                               AND     TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) THEN rpr END) AS rpr_prev_30,
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
