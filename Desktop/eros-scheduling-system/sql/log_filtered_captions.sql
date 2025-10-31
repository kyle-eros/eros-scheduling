-- ============================================================================
-- Script: log_filtered_captions.sql
-- Purpose: Bulk insert audit log entries for filtered captions
--
-- This parameterized INSERT statement enables efficient batch logging of all
-- captions filtered during a single workflow execution.
--
-- Parameters:
--   @blocked_rows (ARRAY<STRUCT<...>>): Array of filter event structs
--
-- Struct Definition:
--   STRUCT<
--     workflow_id STRING,
--     schedule_id STRING,
--     page_name STRING,
--     caption_id STRING,
--     caption_text STRING,
--     content_category STRING,
--     price_tier STRING,
--     rule_type STRING,              -- 'PATTERN_HARD' | 'PATTERN_SOFT' | 'CATEGORY' | 'PRICE_TIER'
--     rule_value STRING,             -- Specific pattern/category/tier that matched
--     enforcement STRING,            -- 'HARD' | 'SOFT'
--     stage STRING,                  -- 'candidate_pool' | 'bucket70' | 'bucket20' | 'bucket10'
--     total_pool_before_filter INT64,
--     total_pool_after_filter INT64
--   >
--
-- Performance:
--   - Single INSERT for entire batch (more efficient than row-by-row)
--   - Streaming insert buffer enabled for BigQuery (near-real-time availability)
--   - Partitioned table ensures cost-efficient writes to current date partition
--
-- Example Invocation:
--   See test script for complete example with STRUCT construction
-- ============================================================================

-- Parameterized insert for blocked captions
-- @blocked_rows is an array of structs with complete audit metadata
INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_filter_audit_log`
(
  workflow_id,
  schedule_id,
  page_name,
  caption_id,
  caption_text,
  content_category,
  price_tier,
  rule_type,
  rule_value,
  enforcement,
  stage,
  total_pool_before_filter,
  total_pool_after_filter
)
SELECT
  r.workflow_id,
  r.schedule_id,
  r.page_name,
  r.caption_id,
  r.caption_text,
  r.content_category,
  r.price_tier,
  r.rule_type,
  r.rule_value,
  r.enforcement,
  r.stage,
  r.total_pool_before_filter,
  r.total_pool_after_filter
FROM UNNEST(@blocked_rows) AS r;

-- Expected Result: N rows inserted (where N = ARRAY_LENGTH(@blocked_rows))

-- Workflow Integration:
-- 1. During caption filtering, collect all blocked captions into an array
-- 2. For each blocked caption, create a STRUCT with all required fields
-- 3. Pass the array to this query as @blocked_rows parameter
-- 4. Execute once per workflow stage (candidate_pool, bucket70, etc.)
-- 5. Audit log now contains complete forensic trail for analysis

-- Performance Considerations:
-- - Batch size: Aim for 100-1000 rows per call (balance latency vs. throughput)
-- - For extremely large filter operations (>5000 rows), consider splitting into multiple batches
-- - BigQuery INSERT quota: 100,000 rows/sec per table (unlikely to hit this limit)
