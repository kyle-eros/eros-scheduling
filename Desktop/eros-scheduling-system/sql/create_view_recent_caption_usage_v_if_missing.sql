-- ============================================================================
-- View: recent_caption_usage_v (fallback creation if missing)
-- Purpose: Create empty fallback view to prevent pool_health.sql errors
-- Dataset: of-scheduler-proj.eros_scheduling_brain
-- ============================================================================
-- This script checks if recent_caption_usage_v exists in INFORMATION_SCHEMA.
-- If the view doesn't exist (recent usage tracking not deployed), it creates
-- a fallback view that returns an empty result set with the expected schema.
-- This prevents errors in pool_health.sql when recent usage filtering is enabled.
-- ============================================================================

-- Check if view exists and create fallback if missing
BEGIN
  -- Attempt to query the view metadata
  DECLARE view_exists BOOL DEFAULT FALSE;

  SET view_exists = (
    SELECT COUNT(*) > 0
    FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.VIEWS`
    WHERE table_name = 'recent_caption_usage_v'
  );

  -- If view doesn't exist, create empty fallback
  IF NOT view_exists THEN
    EXECUTE IMMEDIATE '''
      CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.recent_caption_usage_v` AS
      SELECT
        CAST(NULL AS STRING) AS page_name,
        CAST(NULL AS STRING) AS caption_id,
        CAST(NULL AS TIMESTAMP) AS last_used_at,
        CAST(NULL AS INT64) AS usage_count,
        CAST(NULL AS INT64) AS days_since_last_use
      FROM (SELECT 1) WHERE FALSE
    ''';
    -- Description: Fallback view for recent caption usage tracking (not deployed). Returns empty result set to prevent errors in pool_health.sql.
  END IF;
END;

-- ============================================================================
-- Usage Notes:
-- ============================================================================
-- 1. This script is safe to run multiple times (idempotent)
-- 2. If recent_caption_usage_v already exists, this script does nothing
-- 3. If the view doesn't exist, it creates a fallback that returns zero rows
-- 4. The fallback view has the expected schema:
--    - page_name: Creator identifier
--    - caption_id: Caption identifier
--    - last_used_at: Timestamp of last usage
--    - usage_count: Number of times used
--    - days_since_last_use: Days since last usage
-- 5. This prevents pool_health.sql from failing when recent usage exclusion
--    is enabled but the tracking system hasn't been deployed yet
-- 6. When actual recent_caption_usage_v is deployed, drop this fallback:
--    DROP VIEW IF EXISTS `of-scheduler-proj.eros_scheduling_brain.recent_caption_usage_v`;
--
-- Running this script:
--   bq query --use_legacy_sql=false < create_view_recent_caption_usage_v_if_missing.sql
--
-- Verifying the view exists:
--   SELECT table_name, ddl
--   FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.VIEWS`
--   WHERE table_name = 'recent_caption_usage_v'
-- ============================================================================
