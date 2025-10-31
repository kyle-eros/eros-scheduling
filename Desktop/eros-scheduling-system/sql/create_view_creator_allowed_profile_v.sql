-- ============================================================================
-- View: creator_allowed_profile_v
-- Purpose: Return latest active allowed profile per creator
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================
-- This view provides the current active allowed profile for each creator.
-- It handles multiple historical rows by selecting the most recent active entry.
-- Re-point to canonical source if it exists elsewhere (e.g., master config table).
-- ============================================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile_v` AS
WITH ranked_profiles AS (
  SELECT
    page_name,
    ppv_allowed_categories,
    ppv_allowed_price_tiers,
    bump_allowed_categories,
    bump_allowed_price_tiers,
    is_active,
    feature_enabled,
    created_at,
    updated_at,
    updated_by,
    notes,
    -- Rank by most recent update per page_name
    ROW_NUMBER() OVER (
      PARTITION BY page_name
      ORDER BY updated_at DESC
    ) AS rn
  FROM `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile`
  WHERE is_active = TRUE  -- Only consider active profiles
)
SELECT
  page_name,
  ppv_allowed_categories,
  ppv_allowed_price_tiers,
  bump_allowed_categories,
  bump_allowed_price_tiers,
  is_active,
  feature_enabled,
  created_at,
  updated_at,
  updated_by,
  notes
FROM ranked_profiles
WHERE rn = 1;  -- Take only the most recent active profile per creator
-- Description: Latest active allowed profile per creator. Re-point to canonical source if it exists elsewhere.

-- ============================================================================
-- Usage Notes:
-- ============================================================================
-- 1. This view returns exactly one row per page_name (the most recent active)
-- 2. If no active profile exists for a creator, they won't appear in this view
-- 3. NULL or empty arrays in allowed fields mean "allow all" for that scope
-- 4. Join this view to filter caption pools based on allowed categories/tiers
-- 5. **IMPORTANT**: If a canonical creator config table exists elsewhere in your
--    data warehouse, modify this view to point to that source instead of
--    creator_allowed_profile table
--
-- Example query using this view:
--   SELECT page_name, ppv_allowed_categories
--   FROM `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile_v`
--   WHERE feature_enabled = TRUE
--
-- Integration pattern (from pool_health.sql):
--   LEFT JOIN creator_allowed_profile_v ON creators.page_name = creator_allowed_profile_v.page_name
--   WHERE (creator_allowed_profile_v.ppv_allowed_categories IS NULL
--          OR LOWER(caption.category) IN UNNEST(ARRAY(SELECT LOWER(c) FROM UNNEST(creator_allowed_profile_v.ppv_allowed_categories) AS c)))
-- ============================================================================
