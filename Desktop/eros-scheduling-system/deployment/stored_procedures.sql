-- =============================================================================
-- EROS SCHEDULING SYSTEM - STORED PROCEDURES
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Core stored procedures for caption selection system with performance
--          feedback loops and atomic locking mechanisms
-- Created: October 31, 2025
-- =============================================================================

-- =============================================================================
-- PROCEDURE 1: update_caption_performance
-- =============================================================================
-- Purpose: Update caption performance metrics based on recent message history
--
-- Algorithm:
--   1. Calculate median EMV per page for last 30 days
--   2. Roll up message data to caption_id level (last 7 days)
--   3. Merge into caption_bandit_stats table with conflict detection
--   4. Update confidence bounds using wilson_score_bounds UDF
--   5. Calculate performance percentiles
--
-- Dependencies:
--   - UDF: wilson_score_bounds (calculates confidence intervals)
--   - Table: mass_messages (source data with caption_id)
--   - Table: caption_bandit_stats (target stats table)
--
-- Notes:
--   - Uses APPROX_QUANTILES for efficient median calculation
--   - Filters for caption_id IS NOT NULL to avoid sparse data
--   - Confidence bounds based on 95% Wilson score interval
--   - Exploration score inverse to sample size (encourages exploration)
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

-- =============================================================================
-- PROCEDURE 2: lock_caption_assignments
-- =============================================================================
-- Purpose: Atomically assign captions to a schedule with conflict prevention
--
-- Algorithm:
--   1. Build staged rows with caption metadata from caption_bank
--   2. Generate idempotency keys (SHA256 hash of assignment tuple)
--   3. Filter out assignments with 7-day scheduling conflicts
--   4. Merge into active_caption_assignments table
--   5. Verify insertion count against expected
--
-- Parameters:
--   @schedule_id: STRING - Unique schedule identifier
--   @page_name: STRING - Creator/page name
--   @caption_assignments: ARRAY<STRUCT> - Array of caption_id, scheduled_send_date, scheduled_send_hour
--
-- Dependencies:
--   - Table: caption_bank (caption metadata)
--   - Table: active_caption_assignments (assignment tracking)
--
-- Conflict Prevention:
--   - Checks for existing assignments within +/- 7 days
--   - Prevents same caption from being scheduled too close together
--   - Only inserts if no active conflicts found
--
-- Idempotency:
--   - Uses SHA256 hash of (page_name, caption_id, send_date, send_hour)
--   - Duplicate calls with same parameters are safely ignored
--   - Enables safe retries in case of transient failures
--
-- Notes:
--   - Uses MERGE statement for atomic insert-or-ignore semantics
--   - Verifies insertion count to detect partial failures
--   - All timestamps in America/Los_Angeles timezone
-- =============================================================================

CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
  schedule_id STRING,
  page_name STRING,
  caption_assignments ARRAY<STRUCT<
    caption_id INT64,
    scheduled_send_date DATE,
    scheduled_send_hour INT64
  >>
)
BEGIN
  DECLARE expected INT64;
  DECLARE inserted INT64;

  -- Build staged rows with caption_text/price_tier from bank
  CREATE TEMP TABLE new_rows AS
  SELECT
    page_name AS page_name,
    ca.caption_id,
    cb.caption_text,
    CURRENT_DATE('America/Los_Angeles') AS assigned_date,
    ca.scheduled_send_date,
    ca.scheduled_send_hour,
    cb.price_tier,
    TRUE AS is_active,
    CURRENT_TIMESTAMP() AS assigned_at,
    -- Idempotency key
    TO_HEX(SHA256(CONCAT(
      page_name, '|', CAST(ca.caption_id AS STRING), '|',
      CAST(ca.scheduled_send_date AS STRING), '|', CAST(ca.scheduled_send_hour AS STRING)
    ))) AS assignment_key,
    schedule_id AS schedule_id
  FROM UNNEST(caption_assignments) ca
  JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
    ON cb.caption_id = ca.caption_id;

  -- Merge with conflict prevention
  MERGE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` AS t
  USING (
    SELECT * FROM new_rows r
    WHERE NOT EXISTS (
      SELECT 1
      FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` e
      WHERE e.caption_id = r.caption_id
        AND e.is_active = TRUE
        AND e.scheduled_send_date BETWEEN DATE_SUB(r.scheduled_send_date, INTERVAL 7 DAY)
                                     AND DATE_ADD(r.scheduled_send_date, INTERVAL 7 DAY)
    )
  ) s
  ON t.assignment_key = s.assignment_key
  WHEN NOT MATCHED THEN
    INSERT (page_name, caption_id, caption_text, assigned_date, scheduled_send_date,
            scheduled_send_hour, price_tier, is_active, assigned_at, assignment_key, schedule_id)
    VALUES (s.page_name, s.caption_id, s.caption_text, s.assigned_date, s.scheduled_send_date,
            s.scheduled_send_hour, s.price_tier, s.is_active, s.assigned_at, s.assignment_key, s.schedule_id);

  -- Verify insertions (replace @@row_count)
  SET expected = (SELECT COUNT(*) FROM new_rows);
  SET inserted = (
    SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` a
    JOIN new_rows n USING (assignment_key)
  );

  IF inserted < expected THEN
    RAISE USING MESSAGE = FORMAT('Some assignments blocked by 7-day conflicts. Inserted %d of %d.', inserted, expected);
  END IF;

  DROP TABLE new_rows;
END;

-- =============================================================================
-- VALIDATION AND TESTING
-- =============================================================================

-- Test Query 1: Validate update_caption_performance procedure signature
-- This query checks if the procedure exists and can be called
SELECT
  routine_name,
  routine_type,
  routine_schema,
  routine_catalog
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'update_caption_performance'
  AND routine_schema = 'eros_scheduling_brain';

-- Test Query 2: Validate lock_caption_assignments procedure signature
SELECT
  routine_name,
  routine_type,
  routine_schema,
  routine_catalog
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'lock_caption_assignments'
  AND routine_schema = 'eros_scheduling_brain';

-- Test Query 3: Check UDF dependencies for update_caption_performance
SELECT
  routine_name,
  routine_type,
  routine_schema
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('wilson_score_bounds', 'wilson_sample')
  AND routine_schema = 'eros_scheduling_brain'
ORDER BY routine_name;

-- Test Query 4: Verify table schema compatibility
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable,
  ordinal_position
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('caption_bandit_stats', 'mass_messages', 'active_caption_assignments')
ORDER BY table_name, ordinal_position;

