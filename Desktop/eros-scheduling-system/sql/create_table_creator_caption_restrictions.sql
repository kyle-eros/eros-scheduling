-- ============================================================================
-- Table: creator_caption_restrictions
-- Purpose: Store per-creator restrictions for caption filtering
--
-- This table enables granular control over which captions can be used for
-- each creator by supporting:
--   - HARD filters: Complete exclusion via regex patterns, categories, or price tiers
--   - SOFT filters: De-prioritization via scoring penalties
--   - Scope control: Apply to PPV_ONLY, BUMP_ONLY, or ALL content types
--   - Pool size guardrails: Minimum caption pool thresholds
--
-- Optimization Strategy:
--   - PARTITION BY DATE(updated_at): Cost-efficient querying of recent changes
--   - CLUSTER BY page_name, is_active: Fast lookups by creator and active status
--   - Supports versioning for audit trail and rollback capability
--
-- Idempotency: Safe to re-run; uses IF NOT EXISTS
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================

CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions` (
  -- Primary key and identification
  page_name STRING NOT NULL,                     -- Normalized creator identifier (lowercase, no spaces)

  -- Human-readable documentation
  restriction_text STRING,                       -- Business justification and notes (max 5000 chars recommended)

  -- HARD filters: Complete exclusion (processed before pool selection)
  hard_patterns ARRAY<STRING>,                   -- RE2-compliant regex patterns for HARD blocking
                                                 -- Example: ["pussy\\s+play", "scripted.*content", "\\bexplicit\\b"]
                                                 -- These remove captions entirely from candidate pool

  -- SOFT filters: De-prioritization via rank_score penalty
  soft_patterns ARRAY<STRING>,                   -- RE2-compliant regex patterns for SOFT penalty
                                                 -- Example: ["somewhat.*explicit", "borderline"]
                                                 -- These reduce rank_score by 1000 per match but keep captions available

  -- Categorical restrictions
  restricted_categories ARRAY<STRING>,           -- Content categories to exclude (HARD filter)
                                                 -- Example: ["Explicit", "Full Nude", "Fetish-Extreme"]

  restricted_price_tiers ARRAY<STRING>,          -- Price tiers to exclude (HARD filter)
                                                 -- Example: ["luxury", "premium"]

  -- Scope and thresholds
  applies_to_scope STRING,                       -- Where restrictions apply: 'PPV_ONLY' | 'BUMP_ONLY' | 'ALL'
                                                 -- Default: 'ALL' if NULL

  min_ppv_pool INT64,                            -- Minimum PPV caption pool size after filtering
                                                 -- Default: 200 if NULL
                                                 -- Workflow aborts gracefully if pool drops below threshold

  min_bump_pool INT64,                           -- Minimum BUMP caption pool size after filtering
                                                 -- Default: 50 if NULL

  -- Lifecycle management
  is_active BOOL NOT NULL,                       -- Master switch: FALSE disables all restrictions for this creator
  updated_at TIMESTAMP NOT NULL,                 -- Last modification timestamp
  updated_by STRING,                             -- User/service account that last updated this row
                                                 -- Populated from Google Sheets sync or direct BigQuery update

  version INT64 NOT NULL                         -- Monotonic version counter for audit trail
                                                 -- Increment on each update for change tracking
)
PARTITION BY DATE(updated_at)                    -- Partition by day for cost optimization
CLUSTER BY page_name, is_active;                 -- Cluster for fast creator + status lookups

-- Example usage:
-- INSERT INTO `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`
-- (page_name, restriction_text, hard_patterns, restricted_categories, applies_to_scope, is_active, updated_by)
-- VALUES (
--   'creator_alpha',
--   'Exclude explicit content and luxury tier per brand guidelines',
--   ['pussy\\s+play', '\\bexplicit\\b'],
--   ['Explicit', 'Full Nude'],
--   'ALL',
--   TRUE,
--   'admin@example.com'
-- );
