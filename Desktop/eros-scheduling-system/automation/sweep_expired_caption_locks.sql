-- =============================================================================
-- EROS SCHEDULING SYSTEM - EXPIRED CAPTION LOCKS CLEANUP
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Hourly cleanup of expired caption locks to prevent table bloat
-- Schedule: Every 1 hour
-- =============================================================================

CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`()
BEGIN
  DECLARE sweep_start_time TIMESTAMP;
  DECLARE locks_expired INT64;
  DECLARE locks_past_send_date INT64;
  DECLARE total_cleaned INT64;
  DECLARE sweep_id STRING;

  SET sweep_start_time = CURRENT_TIMESTAMP();
  SET sweep_id = CONCAT('sweep_', FORMAT_TIMESTAMP('%Y%m%d_%H%M%S', sweep_start_time), '_', GENERATE_UUID());

  -- Create temporary table to track what we're cleaning
  CREATE TEMP TABLE locks_to_expire AS
  SELECT
    page_name,
    caption_id,
    scheduled_send_date,
    assigned_date,
    assignment_key,
    CASE
      WHEN scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
        THEN 'STALE_7DAY'
      WHEN scheduled_send_date < CURRENT_DATE('America/Los_Angeles')
        THEN 'PAST_SEND_DATE'
      ELSE 'UNKNOWN'
    END AS expiration_reason
  FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE is_active = TRUE
    AND (
      -- Expire locks older than 7 days from scheduled date
      scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
      -- Expire locks where scheduled date has passed
      OR scheduled_send_date < CURRENT_DATE('America/Los_Angeles')
    );

  -- Count by expiration reason
  SET locks_expired = (
    SELECT COUNT(*) FROM locks_to_expire
    WHERE expiration_reason = 'STALE_7DAY'
  );

  SET locks_past_send_date = (
    SELECT COUNT(*) FROM locks_to_expire
    WHERE expiration_reason = 'PAST_SEND_DATE'
  );

  SET total_cleaned = COALESCE(locks_expired, 0) + COALESCE(locks_past_send_date, 0);

  -- Update active_caption_assignments table
  UPDATE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` t
  SET
    is_active = FALSE,
    deactivated_at = CURRENT_TIMESTAMP(),
    deactivation_reason = l.expiration_reason
  FROM locks_to_expire l
  WHERE t.assignment_key = l.assignment_key;

  -- Log the sweep operation
  BEGIN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
      (sweep_id, sweep_time, locks_expired_stale, locks_expired_past_date, total_locks_cleaned, sweep_duration_seconds)
    VALUES
      (
        sweep_id,
        sweep_start_time,
        locks_expired,
        locks_past_send_date,
        total_cleaned,
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), sweep_start_time, SECOND)
      );
  EXCEPTION WHEN ERROR THEN
    -- Create table if it doesn't exist
    CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log` (
      sweep_id STRING NOT NULL,
      sweep_time TIMESTAMP NOT NULL,
      locks_expired_stale INT64,
      locks_expired_past_date INT64,
      total_locks_cleaned INT64,
      sweep_duration_seconds FLOAT64
    )
    PARTITION BY DATE(sweep_time)
    CLUSTER BY sweep_time;

    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
      (sweep_id, sweep_time, locks_expired_stale, locks_expired_past_date, total_locks_cleaned, sweep_duration_seconds)
    VALUES
      (
        sweep_id,
        sweep_start_time,
        locks_expired,
        locks_past_send_date,
        total_cleaned,
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), sweep_start_time, SECOND)
      );
  END;

  -- Alert if cleanup volume is unusually high (more than 1000 locks)
  IF total_cleaned > 1000 THEN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
      (alert_time, alert_level, alert_source, alert_message, job_id)
    VALUES
      (
        CURRENT_TIMESTAMP(),
        'WARNING',
        'lock_cleanup',
        FORMAT('Unusually high lock cleanup volume: %d locks expired (%d stale, %d past send date)',
               total_cleaned, locks_expired, locks_past_send_date),
        sweep_id
      );
  END IF;

  -- Check for lock table bloat (too many active locks)
  DECLARE active_lock_count INT64;
  SET active_lock_count = (
    SELECT COUNT(*)
    FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
    WHERE is_active = TRUE
  );

  IF active_lock_count > 10000 THEN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
      (alert_time, alert_level, alert_source, alert_message, job_id)
    VALUES
      (
        CURRENT_TIMESTAMP(),
        'CRITICAL',
        'lock_cleanup',
        FORMAT('Active lock table bloat detected: %d active locks. Consider reviewing scheduling frequency.',
               active_lock_count),
        sweep_id
      );
  ELSIF active_lock_count > 5000 THEN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
      (alert_time, alert_level, alert_source, alert_message, job_id)
    VALUES
      (
        CURRENT_TIMESTAMP(),
        'WARNING',
        'lock_cleanup',
        FORMAT('Active lock count growing: %d active locks. Monitor for potential issues.',
               active_lock_count),
        sweep_id
      );
  END IF;

  -- Drop temp table
  DROP TABLE locks_to_expire;

  -- Return summary
  SELECT
    sweep_id,
    total_cleaned AS locks_cleaned,
    locks_expired AS stale_7day_locks,
    locks_past_send_date AS past_date_locks,
    active_lock_count AS remaining_active_locks,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), sweep_start_time, SECOND) AS duration_seconds
  ;

END;

-- =============================================================================
-- SUPPORTING TABLES SCHEMA
-- =============================================================================

-- Lock Sweep Log Table
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log` (
  sweep_id STRING NOT NULL,
  sweep_time TIMESTAMP NOT NULL,
  locks_expired_stale INT64,
  locks_expired_past_date INT64,
  total_locks_cleaned INT64,
  sweep_duration_seconds FLOAT64
)
PARTITION BY DATE(sweep_time)
CLUSTER BY sweep_time;

-- Update active_caption_assignments to support deactivation tracking
-- Note: Run this ALTER TABLE statement separately if these columns don't exist
-- ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
-- ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP,
-- ADD COLUMN IF NOT EXISTS deactivation_reason STRING;

-- =============================================================================
-- USAGE EXAMPLE
-- =============================================================================
-- Manual execution:
-- CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
--
-- Scheduled execution (configured in BigQuery scheduled queries):
-- Schedule: every 1 hours
-- Query: CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
-- =============================================================================

-- =============================================================================
-- MONITORING QUERIES
-- =============================================================================

-- Check recent sweep history
-- SELECT
--   sweep_time,
--   total_locks_cleaned,
--   locks_expired_stale,
--   locks_expired_past_date,
--   sweep_duration_seconds
-- FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
-- WHERE sweep_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
-- ORDER BY sweep_time DESC
-- LIMIT 100;

-- Check current active lock count by creator
-- SELECT
--   page_name,
--   COUNT(*) AS active_locks,
--   MIN(scheduled_send_date) AS earliest_schedule,
--   MAX(scheduled_send_date) AS latest_schedule,
--   COUNT(DISTINCT caption_id) AS unique_captions
-- FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
-- WHERE is_active = TRUE
-- GROUP BY page_name
-- ORDER BY active_locks DESC;

-- Find locks that should have been cleaned but weren't
-- SELECT
--   page_name,
--   caption_id,
--   scheduled_send_date,
--   assigned_date,
--   DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), scheduled_send_date, DAY) AS days_overdue,
--   is_active
-- FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
-- WHERE is_active = TRUE
--   AND scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
-- ORDER BY days_overdue DESC
-- LIMIT 100;
