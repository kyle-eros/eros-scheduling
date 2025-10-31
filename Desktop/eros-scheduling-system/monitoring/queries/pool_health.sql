-- ============================================================================
-- Monitoring Query: Caption Pool Health
-- Purpose: Monitor available caption pool sizes after allowed filters and HARD restrictions
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================
-- This query calculates caption pool health for each creator and scope (PPV/BUMP).
-- It shows pool size progression through the filtering pipeline:
--   1. pool_before_hard: Captions after applying allowed filters (categories/tiers)
--   2. pool_after_hard: Captions after applying HARD restrictions
--   3. hard_filtered: Number of captions blocked by HARD restrictions
--   4. needs_attention: Whether pool is below minimum threshold
--
-- The query respects feature flags and provides safe handling when views are missing.
-- ============================================================================

-- Configuration parameters
DECLARE min_pool_size_ppv INT64 DEFAULT 10;
DECLARE min_pool_size_bump INT64 DEFAULT 5;
DECLARE recent_usage_days INT64 DEFAULT 30;
DECLARE exclude_recent_usage BOOL DEFAULT FALSE;  -- Set TRUE to exclude recently used captions
DECLARE global_feature_enabled BOOL DEFAULT (
  SELECT COALESCE(
    (SELECT flag_value
     FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
     WHERE flag = 'caption_restrictions_enabled'
     LIMIT 1),
    FALSE)
);

-- ============================================================================
-- Step 1: Build PPV caption pools (with allowed filters and HARD restrictions)
-- ============================================================================
WITH ppv_pools AS (
  SELECT
    c.page_name,
    'PPV' AS scope,

    -- Pool before HARD restrictions (after allowed filters only)
    COUNT(DISTINCT cap.caption_id) AS pool_before_hard,

    -- Pool after HARD restrictions (respects global feature flag)
    COUNT(DISTINCT CASE
      WHEN NOT global_feature_enabled THEN cap.caption_id  -- Feature OFF: no filtering
      WHEN NOT EXISTS (
        -- Check if this caption is blocked by any HARD restriction
        SELECT 1
        FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v` AS r
        WHERE r.page_name = c.page_name
          AND r.scope IN ('PPV', 'BOTH')
          AND r.enforcement = 'HARD'
          AND r.is_active = TRUE
          AND (
            -- Block by category (case-insensitive)
            (r.block_category IS NOT NULL AND LOWER(cap.category) = LOWER(r.block_category))
            OR
            -- Block by price tier (case-insensitive)
            (r.block_price_tier IS NOT NULL AND LOWER(cap.price_tier) = LOWER(r.block_price_tier))
            OR
            -- Block by keyword pattern (case-insensitive)
            (r.block_keyword_pattern IS NOT NULL AND REGEXP_CONTAINS(LOWER(cap.caption_text), LOWER(r.block_keyword_pattern)))
            OR
            -- Block by specific caption ID
            (r.block_caption_id IS NOT NULL AND cap.caption_id = r.block_caption_id)
          )
      )
      THEN cap.caption_id
    END) AS pool_after_hard

  FROM `of-scheduler-proj.eros_scheduling_brain.active_creators` AS c

  -- Join allowed profile (NULL = allow all)
  LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile_v` AS ap
    ON c.page_name = ap.page_name

  -- Join caption pool
  INNER JOIN `of-scheduler-proj.eros_scheduling_brain.captions` AS cap
    ON cap.is_active = TRUE
    AND cap.is_deleted = FALSE

  -- Optional: Exclude recently used captions
  LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.recent_caption_usage_v` AS recent
    ON recent.page_name = c.page_name
    AND recent.caption_id = cap.caption_id
    AND recent.days_since_last_use <= recent_usage_days

  WHERE 1=1
    -- Apply allowed category filter (NULL/empty = allow all)
    AND (
      ap.ppv_allowed_categories IS NULL
      OR ARRAY_LENGTH(ap.ppv_allowed_categories) = 0
      OR LOWER(cap.category) IN (
        SELECT LOWER(c) FROM UNNEST(ap.ppv_allowed_categories) AS c
      )
    )

    -- Apply allowed price tier filter (NULL/empty = allow all)
    AND (
      ap.ppv_allowed_price_tiers IS NULL
      OR ARRAY_LENGTH(ap.ppv_allowed_price_tiers) = 0
      OR LOWER(cap.price_tier) IN (
        SELECT LOWER(t) FROM UNNEST(ap.ppv_allowed_price_tiers) AS t
      )
    )

    -- Apply recent usage exclusion if enabled
    AND (
      NOT exclude_recent_usage
      OR recent.caption_id IS NULL
    )

  GROUP BY c.page_name
),

-- ============================================================================
-- Step 2: Build BUMP caption pools (with allowed filters and HARD restrictions)
-- ============================================================================
bump_pools AS (
  SELECT
    c.page_name,
    'BUMP' AS scope,

    -- Pool before HARD restrictions (after allowed filters only)
    COUNT(DISTINCT cap.caption_id) AS pool_before_hard,

    -- Pool after HARD restrictions (respects global feature flag)
    COUNT(DISTINCT CASE
      WHEN NOT global_feature_enabled THEN cap.caption_id  -- Feature OFF: no filtering
      WHEN NOT EXISTS (
        -- Check if this caption is blocked by any HARD restriction
        SELECT 1
        FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v` AS r
        WHERE r.page_name = c.page_name
          AND r.scope IN ('BUMP', 'BOTH')
          AND r.enforcement = 'HARD'
          AND r.is_active = TRUE
          AND (
            -- Block by category (case-insensitive)
            (r.block_category IS NOT NULL AND LOWER(cap.category) = LOWER(r.block_category))
            OR
            -- Block by price tier (case-insensitive)
            (r.block_price_tier IS NOT NULL AND LOWER(cap.price_tier) = LOWER(r.block_price_tier))
            OR
            -- Block by keyword pattern (case-insensitive)
            (r.block_keyword_pattern IS NOT NULL AND REGEXP_CONTAINS(LOWER(cap.caption_text), LOWER(r.block_keyword_pattern)))
            OR
            -- Block by specific caption ID
            (r.block_caption_id IS NOT NULL AND cap.caption_id = r.block_caption_id)
          )
      )
      THEN cap.caption_id
    END) AS pool_after_hard

  FROM `of-scheduler-proj.eros_scheduling_brain.active_creators` AS c

  -- Join allowed profile (NULL = allow all)
  LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile_v` AS ap
    ON c.page_name = ap.page_name

  -- Join caption pool
  INNER JOIN `of-scheduler-proj.eros_scheduling_brain.captions` AS cap
    ON cap.is_active = TRUE
    AND cap.is_deleted = FALSE

  -- Optional: Exclude recently used captions
  LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.recent_caption_usage_v` AS recent
    ON recent.page_name = c.page_name
    AND recent.caption_id = cap.caption_id
    AND recent.days_since_last_use <= recent_usage_days

  WHERE 1=1
    -- Apply allowed category filter (NULL/empty = allow all)
    AND (
      ap.bump_allowed_categories IS NULL
      OR ARRAY_LENGTH(ap.bump_allowed_categories) = 0
      OR LOWER(cap.category) IN (
        SELECT LOWER(c) FROM UNNEST(ap.bump_allowed_categories) AS c
      )
    )

    -- Apply allowed price tier filter (NULL/empty = allow all)
    AND (
      ap.bump_allowed_price_tiers IS NULL
      OR ARRAY_LENGTH(ap.bump_allowed_price_tiers) = 0
      OR LOWER(cap.price_tier) IN (
        SELECT LOWER(t) FROM UNNEST(ap.bump_allowed_price_tiers) AS t
      )
    )

    -- Apply recent usage exclusion if enabled
    AND (
      NOT exclude_recent_usage
      OR recent.caption_id IS NULL
    )

  GROUP BY c.page_name
),

-- ============================================================================
-- Step 3: Union PPV and BUMP pools
-- ============================================================================
combined_pools AS (
  SELECT page_name, scope, pool_before_hard, pool_after_hard FROM ppv_pools
  UNION ALL
  SELECT page_name, scope, pool_before_hard, pool_after_hard FROM bump_pools
)

-- ============================================================================
-- Step 4: Final output with health metrics
-- ============================================================================
SELECT
  CURRENT_DATE() AS report_date,
  page_name,
  scope,

  -- Pool sizes
  pool_before_hard,
  pool_after_hard,
  pool_before_hard - pool_after_hard AS hard_filtered,

  -- Health assessment
  CASE
    WHEN scope = 'PPV' THEN min_pool_size_ppv
    WHEN scope = 'BUMP' THEN min_pool_size_bump
    ELSE 10
  END AS min_pool_required,

  CASE
    WHEN scope = 'PPV' AND pool_after_hard < min_pool_size_ppv THEN TRUE
    WHEN scope = 'BUMP' AND pool_after_hard < min_pool_size_bump THEN TRUE
    ELSE FALSE
  END AS needs_attention,

  -- Configuration context
  global_feature_enabled AS feature_enabled,
  exclude_recent_usage AS recent_usage_excluded,
  recent_usage_days AS recent_days

FROM combined_pools

-- Order by attention needed, then scope, then page_name
ORDER BY
  needs_attention DESC,
  scope,
  page_name

OPTIONS(
  description="Caption pool health monitoring - shows pool sizes after allowed filters and HARD restrictions"
);

-- ============================================================================
-- Output Schema:
-- ============================================================================
-- report_date: Date of the report (CURRENT_DATE)
-- page_name: Creator OnlyFans page name
-- scope: 'PPV' or 'BUMP'
-- pool_before_hard: Caption count after allowed filters, before HARD restrictions
-- pool_after_hard: Caption count after both allowed filters AND HARD restrictions
-- hard_filtered: Number of captions blocked by HARD restrictions
-- min_pool_required: Minimum pool size threshold for this scope
-- needs_attention: TRUE if pool_after_hard < min_pool_required
-- feature_enabled: Whether caption_restrictions_enabled flag is true
-- recent_usage_excluded: Whether recent usage filtering is enabled
-- recent_days: Number of days for recent usage exclusion window
--
-- ============================================================================
-- Usage Examples:
-- ============================================================================
-- 1. Run with defaults (exclude_recent_usage = FALSE):
--    Just execute the query as-is
--
-- 2. Run with recent usage exclusion enabled:
--    Change: DECLARE exclude_recent_usage BOOL DEFAULT TRUE;
--
-- 3. Adjust minimum pool thresholds:
--    Change: DECLARE min_pool_size_ppv INT64 DEFAULT 15;
--    Change: DECLARE min_pool_size_bump INT64 DEFAULT 8;
--
-- 4. Adjust recent usage window:
--    Change: DECLARE recent_usage_days INT64 DEFAULT 45;
--
-- 5. Filter to only creators needing attention:
--    Add to final SELECT: WHERE needs_attention = TRUE
--
-- 6. Scheduled monitoring (daily):
--    bq query --use_legacy_sql=false --destination_table=monitoring.pool_health_daily --replace < pool_health.sql
--
-- ============================================================================
-- Integration Notes:
-- ============================================================================
-- 1. Allowed filters (from creator_allowed_profile_v):
--    - NULL or empty arrays = "allow all" for that dimension
--    - Non-empty arrays = restrict to only those values
--    - Applied FIRST in the filtering pipeline
--
-- 2. HARD restrictions (from active_creator_caption_restrictions_v):
--    - Blocks specific captions from the pool
--    - Applied AFTER allowed filters
--    - Only enforcement='HARD' restrictions are counted here
--    - SOFT restrictions are handled at selection time, not in pool sizing
--
-- 3. Case normalization:
--    - All string comparisons use LOWER() for case-insensitivity
--    - Applies to: category, price_tier, keyword patterns
--
-- 4. Recent usage tracking:
--    - Requires recent_caption_usage_v view to exist
--    - If view is missing, run create_view_recent_caption_usage_v_if_missing.sql
--    - Fallback view returns empty result set, preventing errors
--
-- 5. Performance optimization:
--    - Table clustered by page_name for efficient filtering
--    - Views use indexed columns where available
--    - Consider materializing for large caption pools (>100K captions)
--
-- ============================================================================
-- Troubleshooting:
-- ============================================================================
-- Error: "Table not found: recent_caption_usage_v"
--   Solution: Run create_view_recent_caption_usage_v_if_missing.sql
--
-- Error: "Column not found: caption_restrictions_enabled"
--   Solution: Ensure feature_enabled column exists in creator_allowed_profile
--
-- Unexpected zero pool sizes:
--   Check: 1) allowed filters are not too restrictive
--          2) HARD restrictions are not blocking entire categories
--          3) is_active = TRUE on creators, captions, and restrictions
--
-- Pool sizes don't match expectations:
--   Debug: Run individual CTEs (ppv_pools, bump_pools) separately
--          Add LIMIT 100 to inspect specific caption filtering
-- ============================================================================
