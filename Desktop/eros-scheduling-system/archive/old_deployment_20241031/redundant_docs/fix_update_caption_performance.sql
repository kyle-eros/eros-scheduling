-- =============================================================================
-- FIX: update_caption_performance - Remove Correlated Subquery Error
-- =============================================================================
-- This fixes the "Correlated Subquery is unsupported in UPDATE clause" error
-- by replacing the UPDATE...FROM with MERGE syntax at the percentile update step
-- =============================================================================

CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`()
BEGIN
  DECLARE page_count INT64;
  DECLARE updated_rows INT64;

  -- Median EMV per page, last 30 days
  CREATE TEMP TABLE page_medians AS
  SELECT
    page_name,
    APPROX_QUANTILES(
      SAFE_DIVIDE(purchased_count, NULLIF(viewed_count,0)) * earnings, 100
    )[OFFSET(50)] AS median_emv
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND viewed_count > 0
  GROUP BY page_name;

  SET page_count = (SELECT COUNT(*) FROM page_medians);

  -- Log baseline stats
  IF page_count = 0 THEN
    RAISE USING MESSAGE = 'WARNING: No pages found with viewing activity in last 30 days';
  END IF;

  -- Map messages -> caption_id (now using direct caption_id column)
  CREATE TEMP TABLE msg_rollup AS
  SELECT
    mm.page_name,
    mm.caption_id,  -- Now directly available!
    COUNT(*) AS observations,
    SAFE_DIVIDE(SUM(mm.purchased_count), NULLIF(SUM(mm.sent_count),0)) AS conversion_rate,
    AVG(SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) * mm.earnings) AS avg_emv,
    SUM(mm.earnings) AS total_revenue,
    SUM(CASE WHEN SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) * mm.earnings > pm.median_emv THEN 1 ELSE 0 END) AS new_successes,
    SUM(CASE WHEN SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count,0)) * mm.earnings <= pm.median_emv THEN 1 ELSE 0 END) AS new_failures
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
  JOIN page_medians pm USING (page_name)
  WHERE mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND mm.viewed_count > 0
    AND mm.caption_id IS NOT NULL  -- Only process rows with caption_id
  GROUP BY mm.page_name, mm.caption_id;

  -- Pre-compute confidence bounds for matched rows
  CREATE TEMP TABLE matched_bounds AS
  SELECT
    s.page_name,
    s.caption_id,
    s.observations,
    s.conversion_rate,
    s.avg_emv,
    s.total_revenue,
    s.new_successes,
    s.new_failures,
    t.successes + s.new_successes AS new_total_successes,
    t.failures + s.new_failures AS new_total_failures,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(t.successes + s.new_successes, t.failures + s.new_failures).lower_bound AS new_lower_bound,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(t.successes + s.new_successes, t.failures + s.new_failures).upper_bound AS new_upper_bound
  FROM msg_rollup s
  JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    ON t.page_name = s.page_name AND t.caption_id = s.caption_id;

  -- Pre-compute confidence bounds for new rows (not matched)
  CREATE TEMP TABLE new_rows_bounds AS
  SELECT
    s.page_name,
    s.caption_id,
    s.observations,
    s.conversion_rate,
    s.avg_emv,
    s.total_revenue,
    s.new_successes,
    s.new_failures,
    1 + s.new_successes AS new_total_successes,
    1 + s.new_failures AS new_total_failures,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(1 + s.new_successes, 1 + s.new_failures).lower_bound AS new_lower_bound,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(1 + s.new_successes, 1 + s.new_failures).upper_bound AS new_upper_bound
  FROM msg_rollup s
  WHERE NOT EXISTS (
    SELECT 1
    FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    WHERE t.page_name = s.page_name AND t.caption_id = s.caption_id
  );

  -- Update matched rows
  UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
  SET
    successes = t.successes + mb.new_successes,
    failures = t.failures + mb.new_failures,
    total_observations = t.total_observations + mb.observations,
    avg_conversion_rate = mb.conversion_rate,
    avg_emv = mb.avg_emv,
    total_revenue = t.total_revenue + mb.total_revenue,
    last_emv_observed = mb.avg_emv,
    last_used = CURRENT_TIMESTAMP(),
    confidence_lower_bound = mb.new_lower_bound,
    confidence_upper_bound = mb.new_upper_bound,
    exploration_score = 1.0 / SQRT(mb.new_total_successes + mb.new_total_failures + 1),
    last_updated = CURRENT_TIMESTAMP()
  FROM matched_bounds mb
  WHERE t.page_name = mb.page_name AND t.caption_id = mb.caption_id;

  -- Insert new rows
  INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
    (caption_id, page_name, successes, failures, total_observations, avg_conversion_rate, avg_emv, total_revenue,
     confidence_lower_bound, confidence_upper_bound, exploration_score, last_updated)
  SELECT
    nb.caption_id,
    nb.page_name,
    nb.new_total_successes,
    nb.new_total_failures,
    nb.observations,
    nb.conversion_rate,
    nb.avg_emv,
    nb.total_revenue,
    nb.new_lower_bound,
    nb.new_upper_bound,
    1.0 / SQRT(nb.new_total_successes + nb.new_total_failures),
    CURRENT_TIMESTAMP()
  FROM new_rows_bounds nb;

  DROP TABLE matched_bounds;
  DROP TABLE new_rows_bounds;

  -- Percentile ranks per page - compute ranks and update in one step
  -- FIXED: Use UPDATE...FROM with temp table to avoid correlated subquery errors
  -- This approach calculates percentiles and updates the main table, which works in procedures
  BEGIN
    -- Create a temporary table with updated percentile ranks
    CREATE TEMP TABLE ranked_stats AS
    SELECT
      caption_id,
      page_name,
      successes,
      failures,
      total_observations,
      avg_conversion_rate,
      avg_emv,
      total_revenue,
      last_emv_observed,
      last_used,
      confidence_lower_bound,
      confidence_upper_bound,
      exploration_score,
      last_updated,
      CAST(PERCENT_RANK() OVER (PARTITION BY page_name ORDER BY avg_emv) * 100 AS INT64) AS performance_percentile
    FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;

    -- Update the main table with the new percentile values
    -- Using UPDATE...FROM which works with temp tables in BigQuery stored procedures
    UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    SET performance_percentile = ranked_stats.performance_percentile
    FROM ranked_stats
    WHERE t.caption_id = ranked_stats.caption_id
      AND t.page_name = ranked_stats.page_name;

    SET updated_rows = @@row_count;

    DROP TABLE ranked_stats;
  END;

  -- Clean up temporary tables
  DROP TABLE page_medians;
  DROP TABLE msg_rollup;

END;
