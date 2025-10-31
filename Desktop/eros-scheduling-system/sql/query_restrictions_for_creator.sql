-- ============================================================================
-- Query: query_restrictions_for_creator.sql
-- Purpose: Retrieve caption restrictions for a specific creator
--
-- This parameterized query is the primary entrypoint for workflows to fetch
-- restriction rules for a given creator page.
--
-- Parameters:
--   @page_name (STRING): Normalized creator identifier (lowercase, no spaces)
--
-- Returns:
--   - 0 rows: No active restrictions for this creator (fail-open behavior)
--   - 1 row: Active restriction configuration with all rules and thresholds
--
-- Integration Points:
--   - Called by caption-selector agent at workflow start
--   - Called by onlyfans-orchestrator for dry-run mode
--   - Used by monitoring queries for restriction coverage analysis
--
-- Performance:
--   - Clustered by page_name for sub-millisecond lookups
--   - View automatically filters to is_active = TRUE
--   - LIMIT 1 prevents accidental duplicate processing
--
-- Example Execution:
--   DECLARE page_name STRING DEFAULT 'creator_alpha';
--   -- then run this query
-- ============================================================================

-- Returns one row with arrays for the given page
SELECT
  page_name,
  applies_to_scope,
  min_ppv_pool,
  min_bump_pool,
  hard_patterns,
  soft_patterns,
  restricted_categories,
  restricted_price_tiers
FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
WHERE page_name = @page_name
LIMIT 1;

-- Expected Result Structure:
-- +-------------+------------------+--------------+---------------+----------------------+--------------------+-------------------------+--------------------------+
-- | page_name   | applies_to_scope | min_ppv_pool | min_bump_pool | hard_patterns        | soft_patterns      | restricted_categories   | restricted_price_tiers   |
-- +-------------+------------------+--------------+---------------+----------------------+--------------------+-------------------------+--------------------------+
-- | creator_a   | ALL              | 200          | 50            | ["pussy\\s+play"]    | ["borderline"]     | ["Explicit"]            | ["luxury"]               |
-- +-------------+------------------+--------------+---------------+----------------------+--------------------+-------------------------+--------------------------+

-- Usage in Workflow:
-- 1. Execute this query with @page_name parameter
-- 2. If 0 rows returned: No restrictions, proceed with normal caption selection
-- 3. If 1 row returned: Apply filters per the returned rule arrays
-- 4. HARD filters: Exclude captions matching hard_patterns, restricted_categories, restricted_price_tiers
-- 5. SOFT filters: Reduce rank_score by 1000 for captions matching soft_patterns
-- 6. Validate pool size >= thresholds after HARD filtering
