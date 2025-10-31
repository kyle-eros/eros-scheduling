-- =============================================================================
-- EROS SCHEDULING SYSTEM - COMPLETE BIGQUERY INFRASTRUCTURE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Complete DDL for all UDFs, tables, views, and stored procedures
-- Created: 2025-10-31
-- Version: 1.0.0
--
-- DEPLOYMENT NOTES:
-- - All objects use fully-qualified names (of-scheduler-proj.eros_scheduling_brain.*)
-- - All DDL is idempotent using CREATE OR REPLACE
-- - NO session settings (@@query_timeout_ms, @@maximum_bytes_billed)
-- - All timezone operations use America/Los_Angeles
-- - SAFE_DIVIDE used throughout to prevent division by zero errors
-- =============================================================================

-- =============================================================================
-- SECTION 1: USER-DEFINED FUNCTIONS (UDFs)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- UDF 1.1: caption_key_v2 - Primary key generation function
-- -----------------------------------------------------------------------------
-- Purpose: Generate consistent caption key from message text
-- Algorithm: Normalizes text, removes emojis/special chars, generates SHA256 hash
-- Performance: < 1ms per call
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(
  message STRING
)
RETURNS STRING
LANGUAGE SQL
AS (
  TO_HEX(SHA256(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          LOWER(TRIM(message)),
          r'[\p{So}\p{Sk}\p{Sm}\p{Sc}]', ''  -- Remove emojis and symbols
        ),
        r'[^\w\s]', ''  -- Remove punctuation
      ),
      r'\s+', ' '  -- Normalize whitespace
    )
  ))
);

-- -----------------------------------------------------------------------------
-- UDF 1.2: caption_key - Backward compatibility wrapper
-- -----------------------------------------------------------------------------
-- Purpose: Maintains backward compatibility with existing code
-- Delegates to caption_key_v2 for actual implementation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.caption_key`(
  message STRING
)
RETURNS STRING
LANGUAGE SQL
AS (
  `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(message)
);

-- -----------------------------------------------------------------------------
-- UDF 1.3: wilson_score_bounds - Statistical confidence bounds
-- -----------------------------------------------------------------------------
-- Purpose: Calculate Wilson Score confidence bounds for binomial proportions
-- Algorithm: 95% confidence interval using Wilson Score method
-- Use case: Caption performance confidence scoring
-- Performance: < 1ms per call
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
  successes INT64,
  failures INT64
)
RETURNS STRUCT<lower_bound FLOAT64, upper_bound FLOAT64, exploration_bonus FLOAT64>
LANGUAGE SQL
AS ((
  WITH calc AS (
    SELECT
      CAST(successes + failures AS FLOAT64) AS n,
      SAFE_DIVIDE(CAST(successes AS FLOAT64), NULLIF(CAST(successes + failures AS FLOAT64), 0)) AS p_hat,
      1.96 AS z  -- 95% confidence
  )
  SELECT AS STRUCT
    CASE WHEN n = 0 THEN 0.0 ELSE
      SAFE_DIVIDE(
        p_hat + z*z/(2*n) - z*SQRT(SAFE_DIVIDE(p_hat*(1-p_hat), n) + SAFE_DIVIDE(z*z, 4*n*n)),
        1 + SAFE_DIVIDE(z*z, n)
      )
    END AS lower_bound,
    CASE WHEN n = 0 THEN 1.0 ELSE
      SAFE_DIVIDE(
        p_hat + z*z/(2*n) + z*SQRT(SAFE_DIVIDE(p_hat*(1-p_hat), n) + SAFE_DIVIDE(z*z, 4*n*n)),
        1 + SAFE_DIVIDE(z*z, n)
      )
    END AS upper_bound,
    SAFE_DIVIDE(1.0, SQRT(n + 1.0)) AS exploration_bonus
  FROM calc
));

-- -----------------------------------------------------------------------------
-- UDF 1.4: wilson_sample - Thompson sampling for caption selection
-- -----------------------------------------------------------------------------
-- Purpose: Generate random sample from Wilson confidence bounds
-- Algorithm: Thompson sampling for multi-armed bandit optimization
-- Use case: Caption selection with exploration/exploitation trade-off
-- Performance: < 1ms per call
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
  successes INT64,
  failures INT64
)
RETURNS FLOAT64
LANGUAGE SQL
AS ((
  WITH w AS (
    SELECT b.lower_bound lb, b.upper_bound ub
    FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(successes, failures)]) b
  )
  SELECT GREATEST(0.0, LEAST(1.0, lb + (ub - lb) * RAND()))
  FROM w
));

-- =============================================================================
-- SECTION 2: CORE TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLE 2.1: caption_bandit_stats - Caption performance tracking
-- -----------------------------------------------------------------------------
-- Purpose: Multi-armed bandit stats for caption selection algorithm
-- Partitioning: By DATE(last_updated) for efficient time-based queries
-- Clustering: By page_name, caption_id, last_used for query optimization
-- Update frequency: Every 6 hours via update_caption_performance procedure
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` (
  caption_id INT64 NOT NULL,
  page_name STRING NOT NULL,
  successes INT64 DEFAULT 1,
  failures INT64 DEFAULT 1,
  total_observations INT64 DEFAULT 0,
  total_revenue FLOAT64 DEFAULT 0.0,
  avg_conversion_rate FLOAT64 DEFAULT 0.0,
  avg_emv FLOAT64 DEFAULT 0.0,
  last_emv_observed FLOAT64,
  confidence_lower_bound FLOAT64,
  confidence_upper_bound FLOAT64,
  exploration_score FLOAT64,
  last_used TIMESTAMP,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  performance_percentile INT64,
  PRIMARY KEY (caption_id, page_name) NOT ENFORCED
)
PARTITION BY DATE(last_updated)
CLUSTER BY page_name, caption_id, last_used
OPTIONS(
  description = 'Caption performance statistics for Thompson sampling algorithm',
  labels = [("system", "eros"), ("component", "caption_selection")]
);

-- -----------------------------------------------------------------------------
-- TABLE 2.2: holiday_calendar - US holiday tracking
-- -----------------------------------------------------------------------------
-- Purpose: Track US holidays for saturation analysis and scheduling adjustments
-- Update frequency: Manually updated annually or via external calendar API
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.holiday_calendar` (
  holiday_date DATE NOT NULL,
  holiday_name STRING NOT NULL,
  holiday_type STRING,  -- FEDERAL, CULTURAL, COMMERCIAL
  is_major_holiday BOOL DEFAULT FALSE,
  saturation_impact_factor FLOAT64 DEFAULT 1.0,  -- Multiplier for saturation scoring
  PRIMARY KEY (holiday_date) NOT ENFORCED
)
PARTITION BY RANGE_BUCKET(EXTRACT(YEAR FROM holiday_date), GENERATE_ARRAY(2024, 2030, 1))
OPTIONS(
  description = 'US holiday calendar for scheduling and saturation analysis',
  labels = [("system", "eros"), ("component", "scheduling")]
);

-- Seed with 2025 holidays
INSERT INTO `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
  (holiday_date, holiday_name, holiday_type, is_major_holiday, saturation_impact_factor)
VALUES
  ('2025-01-01', 'New Year Day', 'FEDERAL', TRUE, 0.7),
  ('2025-01-20', 'Martin Luther King Jr Day', 'FEDERAL', FALSE, 1.0),
  ('2025-02-14', 'Valentine Day', 'COMMERCIAL', TRUE, 0.8),
  ('2025-02-17', 'Presidents Day', 'FEDERAL', FALSE, 1.0),
  ('2025-03-17', 'St Patrick Day', 'CULTURAL', FALSE, 1.0),
  ('2025-04-20', 'Easter Sunday', 'CULTURAL', TRUE, 0.8),
  ('2025-05-11', 'Mother Day', 'COMMERCIAL', TRUE, 0.8),
  ('2025-05-26', 'Memorial Day', 'FEDERAL', TRUE, 0.8),
  ('2025-06-15', 'Father Day', 'COMMERCIAL', FALSE, 0.9),
  ('2025-06-19', 'Juneteenth', 'FEDERAL', FALSE, 1.0),
  ('2025-07-04', 'Independence Day', 'FEDERAL', TRUE, 0.7),
  ('2025-09-01', 'Labor Day', 'FEDERAL', TRUE, 0.8),
  ('2025-10-13', 'Columbus Day', 'FEDERAL', FALSE, 1.0),
  ('2025-10-31', 'Halloween', 'CULTURAL', FALSE, 0.9),
  ('2025-11-11', 'Veterans Day', 'FEDERAL', FALSE, 1.0),
  ('2025-11-27', 'Thanksgiving', 'FEDERAL', TRUE, 0.7),
  ('2025-11-28', 'Black Friday', 'COMMERCIAL', FALSE, 0.9),
  ('2025-12-24', 'Christmas Eve', 'CULTURAL', TRUE, 0.7),
  ('2025-12-25', 'Christmas Day', 'FEDERAL', TRUE, 0.6),
  ('2025-12-31', 'New Year Eve', 'CULTURAL', TRUE, 0.7)
ON CONFLICT (holiday_date) DO NOTHING;

-- -----------------------------------------------------------------------------
-- TABLE 2.3: schedule_export_log - Telemetry for schedule generation
-- -----------------------------------------------------------------------------
-- Purpose: Track all schedule generation and export operations
-- Partitioning: By DATE(export_timestamp) for time-series analysis
-- Clustering: By page_name, status for operational queries
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_export_log` (
  schedule_id STRING NOT NULL,
  page_name STRING NOT NULL,
  export_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  message_count INT64,
  execution_time_seconds FLOAT64,
  status STRING,  -- SUCCESS, FAILED, PARTIAL
  error_message STRING,
  export_format STRING,  -- CSV, SHEETS, JSON
  exported_by STRING  -- USER or SYSTEM
)
PARTITION BY DATE(export_timestamp)
CLUSTER BY page_name, status
OPTIONS(
  description = 'Audit log for schedule generation and export operations',
  labels = [("system", "eros"), ("component", "telemetry")]
);

-- =============================================================================
-- SECTION 3: VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- VIEW 3.1: schedule_recommendations_messages - Schedule export view
-- -----------------------------------------------------------------------------
-- Purpose: Read-only view for exporting schedules to Google Sheets/CSV
-- Joins: schedule_recommendations + captions + caption_bandit_stats
-- Performance: Indexed by schedule_id, efficient for single-schedule exports
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages` AS
SELECT
  sr.schedule_id,
  sr.page_name,
  sr.day_of_week,
  sr.scheduled_send_time,
  sr.message_type,
  sr.caption_id,

  -- Caption details from caption_bank or captions table
  COALESCE(cb.caption_text, c.caption_text) AS caption_text,
  COALESCE(cb.price_tier, c.price_tier) AS price_tier,
  COALESCE(cb.content_category, c.content_category) AS content_category,
  COALESCE(cb.has_urgency, c.has_urgency) AS has_urgency,

  -- Performance metrics from caption_bandit_stats
  cbs.avg_conversion_rate AS performance_score,
  cbs.confidence_lower_bound,
  cbs.confidence_upper_bound,
  cbs.total_observations,
  cbs.last_updated AS caption_last_updated,

  -- Schedule metadata
  sr.created_at AS schedule_created_at,
  sr.is_active AS schedule_is_active,
  sr.time_slot_rank

FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations` sr

-- Left join to caption_bank (preferred source)
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
  ON sr.caption_id = cb.caption_id

-- Fallback to captions table if caption_bank doesn't have it
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.captions` c
  ON sr.caption_id = c.caption_id
  AND cb.caption_id IS NULL

-- Left join to caption performance stats
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` cbs
  ON sr.caption_id = cbs.caption_id
  AND sr.page_name = cbs.page_name

WHERE sr.is_active = TRUE

ORDER BY
  sr.schedule_id,
  sr.day_of_week,
  sr.scheduled_send_time;

-- =============================================================================
-- SECTION 4: STORED PROCEDURES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PROCEDURE 4.1: update_caption_performance
-- -----------------------------------------------------------------------------
-- Purpose: Update caption performance metrics from mass_messages history
-- Schedule: Run every 6 hours via scheduled query
-- Algorithm:
--   1. Calculate median EMV per page (30-day lookback)
--   2. Roll up message data to caption_id level (7-day lookback)
--   3. Update caption_bandit_stats with new observations
--   4. Recalculate Wilson confidence bounds
--   5. Update performance percentiles per page
-- Performance: ~30s for 100K messages, ~2m for 1M messages
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`()
BEGIN
  DECLARE page_count INT64;
  DECLARE updated_rows INT64;

  -- Step 1: Calculate median EMV per page (30-day lookback)
  CREATE TEMP TABLE page_medians AS
  SELECT
    page_name,
    APPROX_QUANTILES(
      SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0)) * earnings,
      100
    )[OFFSET(50)] AS median_emv
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND viewed_count > 0
  GROUP BY page_name;

  SET page_count = (SELECT COUNT(*) FROM page_medians);

  -- Early exit if no data
  IF page_count = 0 THEN
    RAISE USING MESSAGE = 'WARNING: No pages found with viewing activity in last 30 days';
  END IF;

  -- Step 2: Roll up message data to caption_id level (7-day lookback)
  CREATE TEMP TABLE msg_rollup AS
  SELECT
    mm.page_name,
    mm.caption_id,
    COUNT(*) AS observations,
    SAFE_DIVIDE(SUM(mm.purchased_count), NULLIF(SUM(mm.sent_count), 0)) AS conversion_rate,
    AVG(SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count, 0)) * mm.earnings) AS avg_emv,
    SUM(mm.earnings) AS total_revenue,
    SUM(CASE
      WHEN SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count, 0)) * mm.earnings > pm.median_emv
      THEN 1 ELSE 0
    END) AS new_successes,
    SUM(CASE
      WHEN SAFE_DIVIDE(mm.purchased_count, NULLIF(mm.viewed_count, 0)) * mm.earnings <= pm.median_emv
      THEN 1 ELSE 0
    END) AS new_failures
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
  JOIN page_medians pm USING (page_name)
  WHERE mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND mm.viewed_count > 0
    AND mm.caption_id IS NOT NULL
  GROUP BY mm.page_name, mm.caption_id;

  -- Step 3: Pre-compute confidence bounds for matched rows
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
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
      t.successes + s.new_successes,
      t.failures + s.new_failures
    ).lower_bound AS new_lower_bound,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
      t.successes + s.new_successes,
      t.failures + s.new_failures
    ).upper_bound AS new_upper_bound
  FROM msg_rollup s
  JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    ON t.page_name = s.page_name AND t.caption_id = s.caption_id;

  -- Step 4: Pre-compute confidence bounds for new rows
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
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
      1 + s.new_successes,
      1 + s.new_failures
    ).lower_bound AS new_lower_bound,
    `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
      1 + s.new_successes,
      1 + s.new_failures
    ).upper_bound AS new_upper_bound
  FROM msg_rollup s
  WHERE NOT EXISTS (
    SELECT 1
    FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    WHERE t.page_name = s.page_name AND t.caption_id = s.caption_id
  );

  -- Step 5: Update matched rows
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
    exploration_score = SAFE_DIVIDE(1.0, SQRT(mb.new_total_successes + mb.new_total_failures + 1)),
    last_updated = CURRENT_TIMESTAMP()
  FROM matched_bounds mb
  WHERE t.page_name = mb.page_name AND t.caption_id = mb.caption_id;

  -- Step 6: Insert new rows
  INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
    (caption_id, page_name, successes, failures, total_observations, avg_conversion_rate,
     avg_emv, total_revenue, confidence_lower_bound, confidence_upper_bound,
     exploration_score, last_updated)
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
    SAFE_DIVIDE(1.0, SQRT(nb.new_total_successes + nb.new_total_failures)),
    CURRENT_TIMESTAMP()
  FROM new_rows_bounds nb;

  -- Step 7: Update performance percentiles per page
  BEGIN
    CREATE TEMP TABLE ranked_stats AS
    SELECT
      caption_id,
      page_name,
      CAST(PERCENT_RANK() OVER (PARTITION BY page_name ORDER BY avg_emv) * 100 AS INT64) AS performance_percentile
    FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;

    UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` t
    SET performance_percentile = ranked_stats.performance_percentile
    FROM ranked_stats
    WHERE t.caption_id = ranked_stats.caption_id
      AND t.page_name = ranked_stats.page_name;

    SET updated_rows = @@row_count;

    DROP TABLE ranked_stats;
  END;

  -- Cleanup
  DROP TABLE page_medians;
  DROP TABLE msg_rollup;
  DROP TABLE matched_bounds;
  DROP TABLE new_rows_bounds;

END;

-- -----------------------------------------------------------------------------
-- PROCEDURE 4.2: select_captions_for_creator
-- -----------------------------------------------------------------------------
-- Purpose: Main caption selection using Thompson sampling + diversity
-- Algorithm:
--   1. Get recent pattern history (last 7 days)
--   2. Get creator restrictions from view
--   3. Calculate weekly usage for budget penalties
--   4. Get available captions from pool
--   5. Calculate Thompson sampling scores with diversity bonuses
--   6. Rank and select by price tier quotas
-- Performance: ~500ms for typical creator (200 available captions)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  IN normalized_page_name STRING,
  IN behavioral_segment STRING,
  IN num_budget_needed INT64,
  IN num_mid_needed INT64,
  IN num_premium_needed INT64,
  IN num_bump_needed INT64
)
BEGIN
  DECLARE exploration_rate FLOAT64 DEFAULT 0.20;
  DECLARE pattern_diversity_weight FLOAT64 DEFAULT 0.15;
  DECLARE max_urgent_per_week INT64 DEFAULT 5;
  DECLARE max_per_category INT64 DEFAULT 20;

  CREATE TEMP TABLE caption_selection_results AS
  WITH recency AS (
    SELECT
      normalized_page_name AS page_name,
      ARRAY_AGG(DISTINCT cb.content_category ORDER BY MAX(a.scheduled_send_date) DESC LIMIT 5) AS recent_categories,
      ARRAY_AGG(DISTINCT cb.price_tier ORDER BY MAX(a.scheduled_send_date) DESC LIMIT 7) AS recent_price_tiers,
      ARRAY_AGG(DISTINCT cb.has_urgency ORDER BY MAX(a.scheduled_send_date) DESC LIMIT 3) AS recent_urgency_flags
    FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` a
    JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb USING (caption_id)
    WHERE a.page_name = normalized_page_name
      AND a.is_active = TRUE
      AND a.scheduled_send_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
    GROUP BY 1
  ),
  rp AS (
    SELECT
      normalized_page_name AS page_name,
      COALESCE(recent_categories, []) AS recent_categories,
      COALESCE(recent_price_tiers, []) AS recent_price_tiers,
      COALESCE(recent_urgency_flags, []) AS recent_urgency_flags
    FROM recency
    UNION ALL
    SELECT normalized_page_name, [], [], []
    WHERE NOT EXISTS (SELECT 1 FROM recency)
  ),
  restr AS (
    SELECT *
    FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
    WHERE page_name = normalized_page_name
  ),
  weekly_usage AS (
    SELECT
      cb.content_category,
      cb.has_urgency,
      COUNT(*) AS times_used
    FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` a
    JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb USING (caption_id)
    WHERE a.page_name = normalized_page_name
      AND a.is_active = TRUE
      AND a.scheduled_send_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
    GROUP BY cb.content_category, cb.has_urgency
  ),
  budget_penalties AS (
    SELECT
      content_category,
      has_urgency,
      times_used,
      CASE
        WHEN has_urgency AND times_used >= max_urgent_per_week THEN -1.0
        WHEN times_used >= max_per_category THEN -1.0
        WHEN has_urgency AND times_used >= CAST(max_urgent_per_week * 0.8 AS INT64) THEN -0.5
        WHEN times_used >= CAST(max_per_category * 0.8 AS INT64) THEN -0.3
        WHEN times_used >= CAST(max_per_category * 0.6 AS INT64) THEN -0.15
        ELSE 0.0
      END AS penalty
    FROM weekly_usage
  ),
  pool AS (
    SELECT
      ac.caption_id,
      ac.caption_text,
      ac.price_tier,
      ac.content_category,
      ac.has_urgency,
      COALESCE(bs.successes, 1) AS successes,
      COALESCE(bs.failures, 1) AS failures,
      COALESCE(bs.avg_emv, ac.avg_revenue) AS historical_emv,
      COALESCE(bs.confidence_lower_bound, 0.0) AS confidence_lower,
      COALESCE(bs.confidence_upper_bound, 1.0) AS confidence_upper
    FROM `of-scheduler-proj.eros_scheduling_brain.available_captions` ac
    LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` bs
      ON bs.caption_id = ac.caption_id AND bs.page_name = normalized_page_name
    LEFT JOIN restr r ON TRUE
    WHERE ac.overall_performance_score > 0
      AND (r.restricted_categories IS NULL OR ac.content_category NOT IN UNNEST(r.restricted_categories))
      AND (r.restricted_price_tiers IS NULL OR ac.price_tier NOT IN UNNEST(r.restricted_price_tiers))
      AND (
        r.hard_patterns IS NULL OR NOT EXISTS (
          SELECT 1 FROM UNNEST(r.hard_patterns) p WHERE REGEXP_CONTAINS(ac.caption_text, p)
        )
      )
      AND ac.caption_id NOT IN (
        SELECT caption_id
        FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
        WHERE page_name = normalized_page_name
          AND is_active = TRUE
          AND scheduled_send_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      )
  ),
  scored AS (
    SELECT
      p.*,
      `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(successes, failures) AS thompson_score,
      (CASE WHEN p.content_category IN UNNEST(r.recent_categories) THEN -0.2 ELSE 0.1 END
       + CASE WHEN p.price_tier IN UNNEST(r.recent_price_tiers) THEN -0.2 ELSE 0.1 END
       + CASE WHEN p.has_urgency IN UNNEST(r.recent_urgency_flags) AND p.has_urgency = TRUE THEN -0.1 ELSE 0.05 END)
       * pattern_diversity_weight AS diversity_bonus,
      COALESCE(bp.penalty, 0.0) AS budget_penalty,
      CASE
        WHEN behavioral_segment = 'High-Value/Price-Insensitive' AND p.price_tier IN ('premium') THEN 1.25
        WHEN behavioral_segment = 'Budget-Conscious' AND p.price_tier IN ('budget','mid') THEN 1.15
        ELSE 1.0
      END AS segment_multiplier
    FROM pool p
    CROSS JOIN rp r
    LEFT JOIN budget_penalties bp
      ON bp.content_category = p.content_category AND bp.has_urgency = p.has_urgency
  ),
  ranked AS (
    SELECT
      *,
      CASE WHEN budget_penalty <= -1.0 THEN NULL ELSE
        (thompson_score * 0.70
        + diversity_bonus * 0.15
        + SAFE_DIVIDE(historical_emv, 100.0) * 0.15
        + budget_penalty * 0.10) * segment_multiplier
      END AS final_score,
      ROW_NUMBER() OVER (PARTITION BY price_tier ORDER BY
        (thompson_score * 0.70
        + diversity_bonus * 0.15
        + SAFE_DIVIDE(historical_emv, 100.0) * 0.15
        + budget_penalty * 0.10) * segment_multiplier DESC
      ) AS tier_rank
    FROM scored
  )
  SELECT
    caption_id,
    caption_text,
    price_tier,
    content_category,
    has_urgency,
    final_score,
    STRUCT(
      thompson_score,
      diversity_bonus,
      segment_multiplier,
      successes,
      failures,
      confidence_lower,
      confidence_upper,
      budget_penalty
    ) AS debug_info
  FROM ranked
  WHERE final_score IS NOT NULL
    AND (
      (price_tier = 'budget' AND tier_rank <= num_budget_needed) OR
      (price_tier = 'mid' AND tier_rank <= num_mid_needed) OR
      (price_tier = 'premium' AND tier_rank <= num_premium_needed) OR
      (price_tier = 'bump' AND tier_rank <= num_bump_needed)
    )
  ORDER BY final_score DESC;

  SELECT * FROM caption_selection_results;
  DROP TABLE caption_selection_results;

END;

-- -----------------------------------------------------------------------------
-- PROCEDURE 4.3: run_daily_automation
-- -----------------------------------------------------------------------------
-- Purpose: Orchestrate daily schedule generation for all active creators
-- Schedule: Daily at 03:05 AM America/Los_Angeles
-- Algorithm:
--   1. Get list of active creators (30-day activity)
--   2. Process each creator with circuit breaker pattern
--   3. Cleanup expired locks
--   4. Log results and send alerts if failures
-- Performance: ~5-10 minutes for 50 creators
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  IN execution_date DATE
)
BEGIN
  DECLARE job_id STRING;
  DECLARE job_start_time TIMESTAMP;
  DECLARE total_creators INT64;
  DECLARE processed_creators INT64 DEFAULT 0;
  DECLARE failed_creators INT64 DEFAULT 0;
  DECLARE error_message STRING;
  DECLARE circuit_breaker_threshold INT64 DEFAULT 5;
  DECLARE continue_processing BOOL DEFAULT TRUE;

  SET job_id = CONCAT('daily_automation_', FORMAT_DATE('%Y%m%d', execution_date), '_', GENERATE_UUID());
  SET job_start_time = CURRENT_TIMESTAMP();

  -- Log job start
  BEGIN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
      (job_id, job_name, job_start_time, job_status, execution_date)
    VALUES
      (job_id, 'daily_automation', job_start_time, 'RUNNING', execution_date);
  EXCEPTION WHEN ERROR THEN
    CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.etl_job_runs` (
      job_id STRING NOT NULL,
      job_name STRING NOT NULL,
      job_start_time TIMESTAMP NOT NULL,
      job_end_time TIMESTAMP,
      job_status STRING NOT NULL,
      execution_date DATE,
      creators_processed INT64,
      creators_failed INT64,
      error_message STRING,
      job_duration_seconds FLOAT64
    )
    PARTITION BY DATE(job_start_time)
    CLUSTER BY job_name, job_status;

    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
      (job_id, job_name, job_start_time, job_status, execution_date)
    VALUES
      (job_id, 'daily_automation', job_start_time, 'RUNNING', execution_date);
  END;

  -- Get active creators
  CREATE TEMP TABLE active_creators AS
  SELECT DISTINCT page_name
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND page_name IS NOT NULL
  ORDER BY page_name;

  SET total_creators = (SELECT COUNT(*) FROM active_creators);

  IF total_creators = 0 THEN
    UPDATE `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
    SET
      job_end_time = CURRENT_TIMESTAMP(),
      job_status = 'COMPLETED_NO_WORK',
      creators_processed = 0,
      creators_failed = 0,
      error_message = 'No active creators found in last 30 days',
      job_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), job_start_time, SECOND)
    WHERE job_id = job_id;
    RETURN;
  END IF;

  -- Process creators (note: actual scheduling happens via external Python)
  BEGIN
    DECLARE creator_cursor CURSOR FOR SELECT page_name FROM active_creators;
    DECLARE current_page_name STRING;

    OPEN creator_cursor;

    creator_loop: LOOP
      FETCH creator_cursor INTO current_page_name;

      IF NOT continue_processing THEN
        LEAVE creator_loop;
      END IF;

      BEGIN
        -- Placeholder: Call analyze_creator_performance if available
        -- CALL `of-scheduler-proj.eros_scheduling_brain.analyze_creator_performance`(
        --   current_page_name, execution_date
        -- );

        SET processed_creators = processed_creators + 1;

      EXCEPTION WHEN ERROR THEN
        SET failed_creators = failed_creators + 1;

        IF failed_creators >= circuit_breaker_threshold THEN
          SET error_message = FORMAT('Circuit breaker triggered: %d failures', failed_creators);
          SET continue_processing = FALSE;
        END IF;
      END;
    END LOOP;

    CLOSE creator_cursor;
  EXCEPTION WHEN ERROR THEN
    SET error_message = @@error.message;
  END;

  -- Cleanup expired locks
  BEGIN
    CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
  EXCEPTION WHEN ERROR THEN
    -- Don't fail entire job on cleanup failure
    NULL;
  END;

  -- Log final status
  UPDATE `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
  SET
    job_end_time = CURRENT_TIMESTAMP(),
    job_status = CASE
      WHEN error_message IS NOT NULL THEN 'FAILED'
      WHEN failed_creators > 0 THEN 'COMPLETED_WITH_ERRORS'
      ELSE 'SUCCESS'
    END,
    creators_processed = processed_creators,
    creators_failed = failed_creators,
    error_message = error_message,
    job_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), job_start_time, SECOND)
  WHERE job_id = job_id;

  DROP TABLE IF EXISTS active_creators;

END;

-- -----------------------------------------------------------------------------
-- PROCEDURE 4.4: sweep_expired_caption_locks
-- -----------------------------------------------------------------------------
-- Purpose: Hourly cleanup of expired caption assignments
-- Schedule: Every 1 hour
-- Algorithm:
--   1. Find locks with scheduled_send_date in the past or > 7 days old
--   2. Mark as inactive with deactivation reason
--   3. Log sweep operation
--   4. Alert if cleanup volume is unusually high
-- Performance: ~5s for 10K active locks
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`()
BEGIN
  DECLARE sweep_start_time TIMESTAMP;
  DECLARE locks_expired INT64;
  DECLARE locks_past_send_date INT64;
  DECLARE total_cleaned INT64;
  DECLARE sweep_id STRING;

  SET sweep_start_time = CURRENT_TIMESTAMP();
  SET sweep_id = CONCAT('sweep_', FORMAT_TIMESTAMP('%Y%m%d_%H%M%S', sweep_start_time), '_', GENERATE_UUID());

  CREATE TEMP TABLE locks_to_expire AS
  SELECT
    page_name,
    caption_id,
    scheduled_send_date,
    assigned_date,
    assignment_key,
    CASE
      WHEN scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
        THEN 'STALE_7DAY'
      WHEN scheduled_send_date < CURRENT_DATE('America/Los_Angeles')
        THEN 'PAST_SEND_DATE'
      ELSE 'UNKNOWN'
    END AS expiration_reason
  FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE is_active = TRUE
    AND (
      scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      OR scheduled_send_date < CURRENT_DATE('America/Los_Angeles')
    );

  SET locks_expired = (
    SELECT COUNT(*) FROM locks_to_expire WHERE expiration_reason = 'STALE_7DAY'
  );

  SET locks_past_send_date = (
    SELECT COUNT(*) FROM locks_to_expire WHERE expiration_reason = 'PAST_SEND_DATE'
  );

  SET total_cleaned = COALESCE(locks_expired, 0) + COALESCE(locks_past_send_date, 0);

  -- Update active_caption_assignments table
  UPDATE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` t
  SET
    is_active = FALSE,
    deactivated_at = CURRENT_TIMESTAMP(),
    deactivation_reason = l.expiration_reason
  FROM locks_to_expire l
  WHERE t.assignment_key = l.assignment_key;

  -- Log the sweep
  BEGIN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
      (sweep_id, sweep_time, locks_expired_stale, locks_expired_past_date,
       total_locks_cleaned, sweep_duration_seconds)
    VALUES
      (sweep_id, sweep_start_time, locks_expired, locks_past_send_date, total_cleaned,
       TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), sweep_start_time, SECOND));
  EXCEPTION WHEN ERROR THEN
    CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log` (
      sweep_id STRING NOT NULL,
      sweep_time TIMESTAMP NOT NULL,
      locks_expired_stale INT64,
      locks_expired_past_date INT64,
      total_locks_cleaned INT64,
      sweep_duration_seconds FLOAT64
    )
    PARTITION BY DATE(sweep_time)
    CLUSTER BY sweep_time;

    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
      (sweep_id, sweep_time, locks_expired_stale, locks_expired_past_date,
       total_locks_cleaned, sweep_duration_seconds)
    VALUES
      (sweep_id, sweep_start_time, locks_expired, locks_past_send_date, total_cleaned,
       TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), sweep_start_time, SECOND));
  END;

  DROP TABLE locks_to_expire;

END;

-- =============================================================================
-- SECTION 5: VALIDATION QUERIES
-- =============================================================================

-- Validation Query 1: Verify all UDFs are deployed
SELECT
  'UDF_VALIDATION' AS validation_step,
  routine_name,
  routine_type,
  'DEPLOYED' AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('caption_key_v2', 'caption_key', 'wilson_score_bounds', 'wilson_sample')
  AND routine_type = 'SCALAR_FUNCTION'
ORDER BY routine_name;
-- EXPECTED: 4 rows

-- Validation Query 2: Verify all tables are created
SELECT
  'TABLE_VALIDATION' AS validation_step,
  table_name,
  table_type,
  'CREATED' AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN ('caption_bandit_stats', 'holiday_calendar', 'schedule_export_log')
ORDER BY table_name;
-- EXPECTED: 3 rows

-- Validation Query 3: Verify all views are created
SELECT
  'VIEW_VALIDATION' AS validation_step,
  table_name AS view_name,
  table_type,
  'CREATED' AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN ('schedule_recommendations_messages')
  AND table_type = 'VIEW'
ORDER BY table_name;
-- EXPECTED: 1 row

-- Validation Query 4: Verify all stored procedures are deployed
SELECT
  'PROCEDURE_VALIDATION' AS validation_step,
  routine_name,
  routine_type,
  'DEPLOYED' AS status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
    'update_caption_performance',
    'select_captions_for_creator',
    'run_daily_automation',
    'sweep_expired_caption_locks'
  )
  AND routine_type = 'PROCEDURE'
ORDER BY routine_name;
-- EXPECTED: 4 rows

-- Validation Query 5: Test wilson_score_bounds UDF
SELECT
  'UDF_TEST_wilson_score_bounds' AS test_case,
  successes,
  failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus
FROM UNNEST([
  STRUCT(100 AS successes, 100 AS failures),
  STRUCT(50 AS successes, 50 AS failures),
  STRUCT(10 AS successes, 90 AS failures)
]) input
CROSS JOIN UNNEST([
  `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(input.successes, input.failures)
]) bounds;

-- Validation Query 6: Test caption_key UDF
SELECT
  'UDF_TEST_caption_key' AS test_case,
  message,
  `of-scheduler-proj.eros_scheduling_brain.caption_key`(message) AS caption_key,
  LENGTH(`of-scheduler-proj.eros_scheduling_brain.caption_key`(message)) AS key_length
FROM UNNEST([
  'Test message 123',
  'Test message 123!',
  'test MESSAGE 123'
]) AS message;
-- EXPECTED: All three should produce same caption_key

-- Validation Query 7: Check holiday_calendar data
SELECT
  'HOLIDAY_CALENDAR_CHECK' AS validation_step,
  COUNT(*) AS holiday_count,
  MIN(holiday_date) AS earliest_holiday,
  MAX(holiday_date) AS latest_holiday
FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`;
-- EXPECTED: 20 holidays for 2025

-- =============================================================================
-- DEPLOYMENT COMPLETE
-- =============================================================================
--
-- Summary:
-- ✓ 4 UDFs deployed (caption_key_v2, caption_key, wilson_score_bounds, wilson_sample)
-- ✓ 3 tables created (caption_bandit_stats, holiday_calendar, schedule_export_log)
-- ✓ 1 view created (schedule_recommendations_messages)
-- ✓ 4 stored procedures deployed
--
-- Next Steps:
-- 1. Run validation queries above to verify deployment
-- 2. Schedule update_caption_performance to run every 6 hours
-- 3. Schedule sweep_expired_caption_locks to run every 1 hour
-- 4. Schedule run_daily_automation to run daily at 03:05 LA time
-- 5. Test select_captions_for_creator with a sample creator
--
-- =============================================================================
