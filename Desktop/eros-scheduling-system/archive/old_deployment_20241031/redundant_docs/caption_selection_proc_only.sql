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