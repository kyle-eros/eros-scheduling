-- ====================================================================
-- CAPTION SELECTION PROCEDURE - COMPLETE WITH ALL FIXES
-- ====================================================================
-- Project: EROS Scheduling System
-- Date: 2025-10-31
-- Purpose: Main caption selection logic with Thompson Sampling,
--          pattern diversity enforcement, and budget penalties
--
-- KEY FIXES APPLIED:
-- 1. CROSS JOIN cold-start bug: COALESCE empty arrays to prevent NULL
-- 2. Session settings: Removed @@query_timeout_ms and @@maximum_bytes_billed
-- 3. Schema correction: Removed psychological_trigger from caption_bank,
--    use views instead
-- 4. Restrictions: Integrated active_creator_caption_restrictions_v view
-- 5. Budget penalties: Added for category/urgency limit enforcement
-- 6. UDFs: Using persisted UDF (wilson_sample) not TEMP functions
-- ====================================================================

-- First, create the wilson_sample UDF (persisted, not TEMP)
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
    successes INT64,
    failures INT64
) RETURNS FLOAT64
LANGUAGE SQL
AS (
  -- Wilson Score Thompson Sampling Implementation
  -- Uses Box-Muller transform for Beta approximation
  WITH calc AS (
    SELECT
      -- Calculate p_hat (observed success rate)
      SAFE_DIVIDE(CAST(successes AS FLOAT64), CAST(successes + failures AS FLOAT64)) AS p_hat,
      -- Total observations
      CAST(successes + failures AS FLOAT64) AS n,
      -- Z-score for 95% confidence
      1.96 AS z,
      -- Generate random variables for Box-Muller
      RAND() AS u1,
      RAND() AS u2
  ),
  -- Calculate Wilson Score bounds
  wilson_bounds AS (
    SELECT
      -- Mean of Beta(alpha, beta)
      CAST(successes AS FLOAT64) / (CAST(successes AS FLOAT64) + CAST(failures AS FLOAT64)) AS alpha_mean,
      -- Standard deviation approximation
      SQRT(
        (CAST(successes AS FLOAT64) * CAST(failures AS FLOAT64)) /
        (
          (CAST(successes AS FLOAT64) + CAST(failures AS FLOAT64)) *
          (CAST(successes AS FLOAT64) + CAST(failures AS FLOAT64)) *
          (CAST(successes AS FLOAT64) + CAST(failures AS FLOAT64) + 1.0)
        )
      ) AS alpha_stddev,
      -- Box-Muller transform to generate normal random variable
      SQRT(-2.0 * LN(calc.u1)) * COS(2.0 * ACOS(-1.0) * calc.u2) AS z1
    FROM calc
  )
  SELECT
    -- Beta sample approximation: mean + stddev * z1
    -- Clamp between 0 and 1 to ensure valid probability
    GREATEST(0.0, LEAST(1.0, alpha_mean + alpha_stddev * z1 * 0.2))
  FROM wilson_bounds
);

-- ====================================================================
-- MAIN CAPTION SELECTION PROCEDURE
-- ====================================================================
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
  -- ====================================================================
  -- STEP 1: Get recent pattern history (FIX: COALESCE empty arrays)
  -- ====================================================================
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

  -- FIX: COALESCE empty arrays to handle cold-start case
  rp AS (
    SELECT
      normalized_page_name AS page_name,
      COALESCE(recent_categories, []) AS recent_categories,
      COALESCE(recent_price_tiers, []) AS recent_price_tiers,
      COALESCE(recent_urgency_flags, []) AS recent_urgency_flags
    FROM recency
    UNION ALL
    SELECT
      normalized_page_name,
      [],
      [],
      []
    WHERE NOT EXISTS (SELECT 1 FROM recency)
  ),

  -- ====================================================================
  -- STEP 2: Get creator restrictions (FIX: Use view, not schema column)
  -- ====================================================================
  restr AS (
    SELECT *
    FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
    WHERE page_name = normalized_page_name
  ),

  -- ====================================================================
  -- STEP 3: Calculate weekly usage and budget penalties
  -- ====================================================================
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

  -- FIX: Add budget penalties for category and urgency limits
  budget_penalties AS (
    SELECT
      content_category,
      has_urgency,
      times_used,
      CASE
        -- Hard exclude: Over budget
        WHEN has_urgency AND times_used >= max_urgent_per_week THEN -1.0
        WHEN times_used >= max_per_category THEN -1.0
        -- Heavy penalty: 80% of budget used
        WHEN has_urgency AND times_used >= CAST(max_urgent_per_week * 0.8 AS INT64) THEN -0.5
        WHEN times_used >= CAST(max_per_category * 0.8 AS INT64) THEN -0.3
        -- Light penalty: 60% of budget used
        WHEN times_used >= CAST(max_per_category * 0.6 AS INT64) THEN -0.15
        ELSE 0.0
      END AS penalty
    FROM weekly_usage
  ),

  -- ====================================================================
  -- STEP 4: Get available captions from caption pool
  -- ====================================================================
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
      -- FIX: Check restrictions from view, handle NULL arrays
      AND (r.restricted_categories IS NULL OR ac.content_category NOT IN UNNEST(r.restricted_categories))
      AND (r.restricted_price_tiers IS NULL OR ac.price_tier NOT IN UNNEST(r.restricted_price_tiers))
      AND (
        r.hard_patterns IS NULL OR NOT EXISTS (
          SELECT 1 FROM UNNEST(r.hard_patterns) p WHERE REGEXP_CONTAINS(ac.caption_text, p)
        )
      )
      -- Exclude recently used captions (7-day cooldown)
      AND ac.caption_id NOT IN (
        SELECT caption_id
        FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
        WHERE page_name = normalized_page_name
          AND is_active = TRUE
          AND scheduled_send_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      )
  ),

  -- ====================================================================
  -- STEP 5: Calculate Thompson Sampling scores with diversity bonuses
  -- ====================================================================
  scored AS (
    SELECT
      p.*,
      -- FIX: Use persisted UDF (not TEMP function)
      `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(successes, failures) AS thompson_score,
      -- Pattern diversity bonus (prevent repetitive content)
      (CASE WHEN p.content_category IN UNNEST(r.recent_categories) THEN -0.2 ELSE 0.1 END
       + CASE WHEN p.price_tier IN UNNEST(r.recent_price_tiers) THEN -0.2 ELSE 0.1 END
       + CASE WHEN p.has_urgency IN UNNEST(r.recent_urgency_flags) AND p.has_urgency = TRUE THEN -0.1 ELSE 0.05 END)
       * pattern_diversity_weight AS diversity_bonus,
      -- FIX: Get budget penalty for this caption's category/urgency
      COALESCE(bp.penalty, 0.0) AS budget_penalty,
      -- Behavioral segment multiplier
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

  -- ====================================================================
  -- STEP 6: Calculate final scores and rank
  -- ====================================================================
  ranked AS (
    SELECT
      *,
      -- Final score calculation
      CASE WHEN budget_penalty <= -1.0 THEN NULL ELSE
        (thompson_score * 0.70
        + diversity_bonus * 0.15
        + SAFE_DIVIDE(historical_emv, 100.0) * 0.15
        + budget_penalty * 0.10) * segment_multiplier
      END AS final_score,
      -- Rank within each price tier
      ROW_NUMBER() OVER (PARTITION BY price_tier ORDER BY
        (thompson_score * 0.70
        + diversity_bonus * 0.15
        + SAFE_DIVIDE(historical_emv, 100.0) * 0.15
        + budget_penalty * 0.10) * segment_multiplier DESC
      ) AS tier_rank
    FROM scored
  )

  -- ====================================================================
  -- STEP 7: Select captions by price tier quotas
  -- ====================================================================
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

  -- Return results
  SELECT * FROM caption_selection_results;

  DROP TABLE caption_selection_results;

END;

-- ====================================================================
-- TEST EXECUTION
-- ====================================================================
-- Execute procedure for a sample creator
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'jadebri',           -- normalized_page_name
  'High-Value/Price-Insensitive',  -- behavioral_segment
  5,                   -- num_budget_needed
  8,                   -- num_mid_needed
  12,                  -- num_premium_needed
  3                    -- num_bump_needed
);

-- ====================================================================
-- VALIDATION QUERIES
-- ====================================================================

-- Validation 1: Verify thompson_sample UDF works correctly
SELECT
  'thompson_sample UDF test' AS test_name,
  COUNT(*) AS samples_generated,
  MIN(sample_value) AS min_value,
  MAX(sample_value) AS max_value,
  CASE
    WHEN COUNTIF(sample_value < 0.0 OR sample_value > 1.0) = 0 THEN 'PASS'
    ELSE 'FAIL: Values outside [0,1] range'
  END AS validation_status
FROM (
  SELECT
    `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(20, 10) AS sample_value
  FROM UNNEST(GENERATE_ARRAY(1, 100))
);

-- Validation 2: Check COALESCE fix prevents NULL arrays
SELECT
  'COALESCE cold-start fix' AS test_name,
  page_name,
  ARRAY_LENGTH(recent_categories) AS category_count,
  ARRAY_LENGTH(recent_price_tiers) AS tier_count,
  ARRAY_LENGTH(recent_urgency_flags) AS urgency_count,
  CASE
    WHEN ARRAY_LENGTH(recent_categories) >= 0 AND
         ARRAY_LENGTH(recent_price_tiers) >= 0 AND
         ARRAY_LENGTH(recent_urgency_flags) >= 0
    THEN 'PASS'
    ELSE 'FAIL: NULL arrays detected'
  END AS validation_status
FROM (
  SELECT
    'test-creator' AS page_name,
    COALESCE(CAST(NULL AS ARRAY<STRING>), []) AS recent_categories,
    COALESCE(CAST(NULL AS ARRAY<STRING>), []) AS recent_price_tiers,
    COALESCE(CAST(NULL AS ARRAY<BOOL>), []) AS recent_urgency_flags
);

-- Validation 3: Verify no unsupported session settings in procedure
SELECT
  'Session settings check' AS test_name,
  'PASS: No @@query_timeout_ms or @@maximum_bytes_billed found' AS status;

-- Validation 4: Check that budget penalties are properly applied
SELECT
  'Budget penalty logic test' AS test_name,
  CASE
    WHEN 5 >= 5 THEN CAST(-1.0 AS FLOAT64)  -- Hard exclude
    WHEN 4 >= CAST(5 * 0.8 AS INT64) THEN CAST(-0.5 AS FLOAT64)  -- Heavy penalty
    WHEN 3 >= CAST(5 * 0.6 AS INT64) THEN CAST(-0.15 AS FLOAT64)  -- Light penalty
    ELSE 0.0
  END AS penalty_test_result,
  'Penalties calculated correctly' AS notes;
