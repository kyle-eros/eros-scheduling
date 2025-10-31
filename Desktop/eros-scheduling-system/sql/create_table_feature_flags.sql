-- ============================================================================
-- Table: feature_flags
-- Purpose: Global feature toggle system for instant enable/disable control
--
-- This table provides a centralized kill-switch mechanism for features across
-- the entire scheduling system, enabling:
--   - Zero-downtime feature rollout (gradual enable)
--   - Instant rollback without code deployment
--   - A/B testing and canary releases
--   - Emergency disable for problematic features
--
-- Key Flags:
--   - 'caption_restrictions_enabled': Master switch for Creator Caption Restrictions
--     When FALSE, all restriction logic is bypassed (fail-open behavior)
--
-- Optimization Strategy:
--   - PARTITION BY DATE(updated_at): Track flag changes over time
--   - CLUSTER BY flag: Fast single-flag lookups (primary access pattern)
--   - Small table size: Full table scan acceptable if needed
--
-- Idempotency: Safe to re-run; uses IF NOT EXISTS
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================

CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.feature_flags` (
  -- Flag identification
  flag STRING NOT NULL,                          -- Unique flag identifier (snake_case convention)
                                                 -- Example: 'caption_restrictions_enabled'

  -- Flag state
  is_enabled BOOL NOT NULL,                      -- TRUE = feature active, FALSE = feature disabled
                                                 -- All consuming workflows MUST respect this value

  -- Audit trail
  updated_at TIMESTAMP NOT NULL,                 -- Last toggle timestamp
  updated_by STRING                              -- User/service account that changed the flag
                                                 -- Populated from admin tools or emergency runbooks
)
PARTITION BY DATE(updated_at)                    -- Partition by day for change history queries
CLUSTER BY flag;                                 -- Cluster for instant flag lookups

-- Example usage:
-- Emergency disable caption restrictions:
-- UPDATE `of-scheduler-proj.eros_scheduling_brain.feature_flags`
-- SET is_enabled = FALSE,
--     updated_at = CURRENT_TIMESTAMP(),
--     updated_by = 'oncall@example.com'
-- WHERE flag = 'caption_restrictions_enabled';

-- Query current state:
-- SELECT is_enabled
-- FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
-- WHERE flag = 'caption_restrictions_enabled';
