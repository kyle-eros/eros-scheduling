-- ============================================================================
-- Table: caption_filter_audit_log
-- Purpose: Comprehensive audit trail for caption filtering decisions
--
-- This table records every caption exclusion or de-prioritization action,
-- enabling detailed analysis of:
--   - Which rules are most restrictive
--   - Pool size impact over time
--   - Creator-specific filtering patterns
--   - Rule effectiveness and potential over-filtering
--
-- Use Cases:
--   - Debugging pool exhaustion issues
--   - Monitoring filter hit rates per creator/rule
--   - Identifying patterns that may be too aggressive
--   - Compliance reporting and justification
--
-- Optimization Strategy:
--   - PARTITION BY DATE(filtered_at): Time-series queries by date range
--   - CLUSTER BY page_name, workflow_id: Fast lookups by creator and workflow
--   - No compression on caption_text for full forensic capability
--
-- Idempotency: Safe to re-run; uses IF NOT EXISTS
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================

CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log` (
  -- Workflow context
  workflow_id STRING,                            -- Unique workflow execution ID for correlation
  schedule_id STRING,                            -- Schedule instance being processed
  page_name STRING,                              -- Creator identifier (normalized)

  -- Caption details
  caption_id STRING,                             -- Unique caption identifier from caption pool
  caption_text STRING,                           -- Full caption text (for forensic analysis)
                                                 -- Truncate to 5000 chars if extremely long to control storage

  content_category STRING,                       -- Caption's content category (e.g., "Explicit", "Softcore")
  price_tier STRING,                             -- Caption's price tier (e.g., "standard", "luxury")

  -- Filter decision
  rule_type STRING,                              -- Type of rule that triggered action:
                                                 -- 'PATTERN_HARD'  : hard_patterns regex match
                                                 -- 'PATTERN_SOFT'  : soft_patterns regex match
                                                 -- 'CATEGORY'      : restricted_categories match
                                                 -- 'PRICE_TIER'    : restricted_price_tiers match

  rule_value STRING,                             -- Specific pattern/category/tier that triggered
                                                 -- Example: "pussy\\s+play" or "Explicit"

  enforcement STRING,                            -- Action taken: 'HARD' (excluded) | 'SOFT' (penalized)

  stage STRING,                                  -- Pipeline stage where filter applied:
                                                 -- 'candidate_pool' : Initial pool construction
                                                 -- 'bucket70'       : 70/20/10 bucket allocation (if applicable)
                                                 -- 'bucket20'
                                                 -- 'bucket10'

  -- Metadata
  filtered_at TIMESTAMP NOT NULL,                -- When the filter action occurred

  -- Pool impact metrics
  total_pool_before_filter INT64,                -- Caption pool size before this filter
  total_pool_after_filter INT64                  -- Caption pool size after this filter
                                                 -- Delta = (before - after) gives direct impact
)
PARTITION BY DATE(filtered_at)                   -- Partition by day for cost-efficient time-series queries
CLUSTER BY page_name, workflow_id;               -- Cluster for fast creator + workflow lookups

-- Example usage:
-- INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log`
-- (workflow_id, schedule_id, page_name, caption_id, caption_text, content_category, price_tier,
--  rule_type, rule_value, enforcement, stage, total_pool_before_filter, total_pool_after_filter)
-- VALUES (
--   'wf_20250129_001',
--   'sched_20250129_creator_alpha',
--   'creator_alpha',
--   'cap_12345',
--   'Check out this pussy play content...',
--   'Explicit',
--   'standard',
--   'PATTERN_HARD',
--   'pussy\\s+play',
--   'HARD',
--   'candidate_pool',
--   1500,
--   1499
-- );
