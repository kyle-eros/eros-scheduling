-- ============================================================================
-- View: active_creator_caption_restrictions_v
-- Purpose: Simplified interface to active creator restrictions with defaults
--
-- This view serves as the primary query interface for the caption filtering
-- workflow, providing:
--   - Only active restrictions (is_active = TRUE)
--   - Default pool size thresholds if NULL in base table
--   - Clean column projection without audit metadata
--
-- Benefits:
--   - Consumers don't need to handle NULL threshold values
--   - Automatic filtering of inactive restrictions
--   - Stable interface if base table schema evolves
--   - Query optimization opportunity via view materialization (future)
--
-- Default Values:
--   - min_ppv_pool: 200 (sufficient for weekly PPV schedule)
--   - min_bump_pool: 50 (sufficient for daily bump messages)
--
-- Usage: SELECT * FROM this view WHERE page_name = @page_name LIMIT 1;
-- ============================================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v` AS
SELECT
  -- Creator identification
  page_name,

  -- Scope control
  applies_to_scope,                              -- 'PPV_ONLY' | 'BUMP_ONLY' | 'ALL'

  -- Pool size guardrails with defaults
  COALESCE(min_ppv_pool, 200) AS min_ppv_pool,   -- Default: 200 captions for PPV pool
  COALESCE(min_bump_pool, 50) AS min_bump_pool,  -- Default: 50 captions for BUMP pool

  -- Filter definitions (arrays may be NULL if no restrictions in that category)
  hard_patterns,                                 -- ARRAY<STRING> of RE2 patterns for HARD exclusion
  soft_patterns,                                 -- ARRAY<STRING> of RE2 patterns for SOFT penalty
  restricted_categories,                         -- ARRAY<STRING> of content categories to exclude
  restricted_price_tiers                         -- ARRAY<STRING> of price tiers to exclude

FROM `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`

-- Only return active restrictions (master switch)
WHERE is_active = TRUE;

-- Query Examples:
-- 1. Get restrictions for specific creator:
--    SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
--    WHERE page_name = 'creator_alpha' LIMIT 1;
--
-- 2. List all creators with active restrictions:
--    SELECT page_name, applies_to_scope, ARRAY_LENGTH(hard_patterns) AS hard_pattern_count
--    FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
--    ORDER BY page_name;
--
-- 3. Find creators with restrictive hard patterns (>5 patterns):
--    SELECT page_name, ARRAY_LENGTH(hard_patterns) AS pattern_count
--    FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
--    WHERE ARRAY_LENGTH(hard_patterns) > 5
--    ORDER BY pattern_count DESC;
