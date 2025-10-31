-- ============================================================================
-- Script: seed_feature_flag_caption_restrictions.sql
-- Purpose: Initialize or update the caption_restrictions_enabled feature flag
--
-- This script safely creates or updates the master feature flag for the
-- Creator Caption Restrictions feature using a MERGE operation.
--
-- Behavior:
--   - First run: Inserts flag with is_enabled = TRUE
--   - Subsequent runs: Updates is_enabled and updated_at if flag exists
--   - Idempotent: Safe to run multiple times without side effects
--
-- Default State: TRUE (enabled)
-- To disable: Manually UPDATE the row or re-run with modified source value
--
-- Deployment: Run this after creating the feature_flags table
-- Rollback: UPDATE is_enabled = FALSE or DELETE the row
-- ============================================================================

MERGE `of-scheduler-proj.eros_scheduling_brain.feature_flags` T
USING (
  SELECT
    'caption_restrictions_enabled' AS flag,  -- Flag identifier
    TRUE AS is_enabled                       -- Default: enabled (change to FALSE for disabled default)
) S
ON T.flag = S.flag                           -- Match on flag name

-- If flag already exists, update its state and timestamp
WHEN MATCHED THEN
  UPDATE SET
    is_enabled = S.is_enabled,               -- Sync state from source
    updated_at = CURRENT_TIMESTAMP()         -- Record update time
                                             -- updated_by remains unchanged (preserves last operator)

-- If flag doesn't exist, insert new row
WHEN NOT MATCHED THEN
  INSERT (flag, is_enabled, updated_at)
  VALUES (S.flag, S.is_enabled, CURRENT_TIMESTAMP());

-- Expected Result: 1 row inserted or updated
-- Verification Query:
-- SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
-- WHERE flag = 'caption_restrictions_enabled';
