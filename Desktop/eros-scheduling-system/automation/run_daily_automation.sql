-- =============================================================================
-- EROS SCHEDULING SYSTEM - DAILY AUTOMATION ORCHESTRATOR
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Orchestrate daily schedule generation for all active creators
-- Schedule: Daily at 3:05 AM America/Los_Angeles
-- =============================================================================

CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  IN execution_date DATE
)
BEGIN
  DECLARE job_id STRING;
  DECLARE job_start_time TIMESTAMP;
  DECLARE total_creators INT64;
  DECLARE processed_creators INT64 DEFAULT 0;
  DECLARE failed_creators INT64 DEFAULT 0;
  DECLARE error_message STRING;
  DECLARE circuit_breaker_threshold INT64 DEFAULT 5;
  DECLARE continue_processing BOOL DEFAULT TRUE;

  -- Generate unique job ID
  SET job_id = CONCAT('daily_automation_', FORMAT_DATE('%Y%m%d', execution_date), '_', GENERATE_UUID());
  SET job_start_time = CURRENT_TIMESTAMP();

  -- Log job start
  BEGIN
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
      (job_id, job_name, job_start_time, job_status, execution_date)
    VALUES
      (job_id, 'daily_automation', job_start_time, 'RUNNING', execution_date);
  EXCEPTION WHEN ERROR THEN
    -- If etl_job_runs doesn't exist, create it on the fly
    CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.etl_job_runs` (
      job_id STRING NOT NULL,
      job_name STRING NOT NULL,
      job_start_time TIMESTAMP NOT NULL,
      job_end_time TIMESTAMP,
      job_status STRING NOT NULL,
      execution_date DATE,
      creators_processed INT64,
      creators_failed INT64,
      error_message STRING,
      job_duration_seconds FLOAT64
    );

    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
      (job_id, job_name, job_start_time, job_status, execution_date)
    VALUES
      (job_id, 'daily_automation', job_start_time, 'RUNNING', execution_date);
  END;

  -- Get list of active creators
  CREATE TEMP TABLE active_creators AS
  SELECT DISTINCT page_name
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND page_name IS NOT NULL
  ORDER BY page_name;

  SET total_creators = (SELECT COUNT(*) FROM active_creators);

  -- Early exit if no active creators
  IF total_creators = 0 THEN
    UPDATE `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
    SET
      job_end_time = CURRENT_TIMESTAMP(),
      job_status = 'COMPLETED_NO_WORK',
      creators_processed = 0,
      creators_failed = 0,
      error_message = 'No active creators found in last 30 days',
      job_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), job_start_time, SECOND)
    WHERE job_id = job_id;
    RETURN;
  END IF;

  -- Process each creator with circuit breaker pattern
  BEGIN
    DECLARE creator_cursor CURSOR FOR
      SELECT page_name FROM active_creators;
    DECLARE current_page_name STRING;
    DECLARE creator_error STRING;

    OPEN creator_cursor;

    creator_loop: LOOP
      FETCH creator_cursor INTO current_page_name;

      -- Exit conditions
      IF NOT continue_processing THEN
        LEAVE creator_loop;
      END IF;

      BEGIN
        -- Step 1: Analyze creator performance
        CALL `of-scheduler-proj.eros_scheduling_brain.analyze_creator_performance`(
          current_page_name,
          execution_date
        );

        -- Step 2: Check saturation levels
        -- This is a safety check to avoid over-scheduling
        DECLARE saturation_pct FLOAT64;
        SET saturation_pct = (
          SELECT
            SAFE_DIVIDE(
              COUNT(DISTINCT caption_id),
              (SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
               WHERE page_name = current_page_name OR page_name IS NULL)
            ) * 100
          FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
          WHERE page_name = current_page_name
            AND is_active = TRUE
            AND scheduled_send_date >= execution_date
        );

        -- Step 3: Trigger schedule generation if not saturated
        -- Note: Actual schedule generation happens via external Python script
        -- This procedure logs the readiness for schedule generation
        IF COALESCE(saturation_pct, 0) < 80 THEN
          INSERT INTO `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue`
            (page_name, execution_date, saturation_pct, queued_at, status)
          VALUES
            (current_page_name, execution_date, saturation_pct, CURRENT_TIMESTAMP(), 'PENDING');
        END IF;

        SET processed_creators = processed_creators + 1;

      EXCEPTION WHEN ERROR THEN
        -- Log individual creator failure
        SET creator_error = @@error.message;
        SET failed_creators = failed_creators + 1;

        INSERT INTO `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
          (job_id, page_name, execution_date, error_message, error_time)
        VALUES
          (job_id, current_page_name, execution_date, creator_error, CURRENT_TIMESTAMP());

        -- Circuit breaker: stop processing if too many failures
        IF failed_creators >= circuit_breaker_threshold THEN
          SET error_message = FORMAT('Circuit breaker triggered: %d consecutive failures', failed_creators);
          SET continue_processing = FALSE;
        END IF;
      END;
    END LOOP;

    CLOSE creator_cursor;
  EXCEPTION WHEN ERROR THEN
    SET error_message = @@error.message;
  END;

  -- Step 4: Cleanup expired locks
  BEGIN
    CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
  EXCEPTION WHEN ERROR THEN
    -- Don't fail the entire job if cleanup fails
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
      (job_id, page_name, execution_date, error_message, error_time)
    VALUES
      (job_id, 'SYSTEM_CLEANUP', execution_date, @@error.message, CURRENT_TIMESTAMP());
  END;

  -- Step 5: Log final job status
  UPDATE `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
  SET
    job_end_time = CURRENT_TIMESTAMP(),
    job_status = CASE
      WHEN error_message IS NOT NULL THEN 'FAILED'
      WHEN failed_creators > 0 THEN 'COMPLETED_WITH_ERRORS'
      ELSE 'SUCCESS'
    END,
    creators_processed = processed_creators,
    creators_failed = failed_creators,
    error_message = error_message,
    job_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), job_start_time, SECOND)
  WHERE job_id = job_id;

  -- Step 6: Send alerts if there were failures
  IF error_message IS NOT NULL OR failed_creators > 0 THEN
    -- Insert into alerts table for external monitoring
    INSERT INTO `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
      (alert_time, alert_level, alert_source, alert_message, job_id)
    VALUES
      (
        CURRENT_TIMESTAMP(),
        CASE WHEN error_message IS NOT NULL THEN 'CRITICAL' ELSE 'WARNING' END,
        'daily_automation',
        FORMAT('Job completed with issues: %d/%d creators failed. %s',
               failed_creators, total_creators, COALESCE(error_message, 'See error log for details')),
        job_id
      );
  END IF;

  -- Drop temp tables
  DROP TABLE IF EXISTS active_creators;

  -- Return summary
  SELECT
    job_id,
    total_creators,
    processed_creators,
    failed_creators,
    error_message,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), job_start_time, SECOND) AS duration_seconds
  ;

END;

-- =============================================================================
-- SUPPORTING TABLES SCHEMA
-- =============================================================================
-- These tables will be created automatically if they don't exist

-- ETL Job Runs Log
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.etl_job_runs` (
  job_id STRING NOT NULL,
  job_name STRING NOT NULL,
  job_start_time TIMESTAMP NOT NULL,
  job_end_time TIMESTAMP,
  job_status STRING NOT NULL,
  execution_date DATE,
  creators_processed INT64,
  creators_failed INT64,
  error_message STRING,
  job_duration_seconds FLOAT64
)
PARTITION BY DATE(job_start_time)
CLUSTER BY job_name, job_status;

-- Creator Processing Errors Log
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors` (
  job_id STRING NOT NULL,
  page_name STRING NOT NULL,
  execution_date DATE,
  error_message STRING,
  error_time TIMESTAMP NOT NULL
)
PARTITION BY DATE(error_time)
CLUSTER BY job_id, page_name;

-- Schedule Generation Queue
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue` (
  page_name STRING NOT NULL,
  execution_date DATE NOT NULL,
  saturation_pct FLOAT64,
  queued_at TIMESTAMP NOT NULL,
  processed_at TIMESTAMP,
  status STRING NOT NULL,  -- PENDING, PROCESSING, COMPLETED, FAILED
  schedule_id STRING,
  error_message STRING
)
PARTITION BY execution_date
CLUSTER BY status, page_name;

-- Automation Alerts
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.automation_alerts` (
  alert_id STRING DEFAULT GENERATE_UUID(),
  alert_time TIMESTAMP NOT NULL,
  alert_level STRING NOT NULL,  -- INFO, WARNING, CRITICAL
  alert_source STRING NOT NULL,
  alert_message STRING,
  job_id STRING,
  acknowledged BOOL DEFAULT FALSE,
  acknowledged_at TIMESTAMP,
  acknowledged_by STRING
)
PARTITION BY DATE(alert_time)
CLUSTER BY alert_level, alert_source, acknowledged;

-- =============================================================================
-- USAGE EXAMPLE
-- =============================================================================
-- Manual execution for today:
-- CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE('America/Los_Angeles'));
--
-- Scheduled execution (configured in BigQuery scheduled queries):
-- Schedule: every day 03:05 America/Los_Angeles
-- Query: CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE('America/Los_Angeles'));
-- =============================================================================
