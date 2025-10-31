-- =============================================================================
-- EROS SCHEDULING SYSTEM - AUTOMATION HEALTH CHECK DASHBOARD
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Comprehensive monitoring queries for automation health
-- =============================================================================

-- =============================================================================
-- QUERY 1: DAILY AUTOMATION STATUS (LAST 7 DAYS)
-- =============================================================================
-- Shows success/failure rates and execution metrics for daily automation

SELECT
  DATE(job_start_time, 'America/Los_Angeles') AS execution_date,
  job_status,
  COUNT(*) AS run_count,
  AVG(job_duration_seconds) AS avg_duration_seconds,
  MAX(job_duration_seconds) AS max_duration_seconds,
  SUM(creators_processed) AS total_creators_processed,
  SUM(creators_failed) AS total_creators_failed,
  ROUND(SAFE_DIVIDE(SUM(creators_failed), SUM(creators_processed)) * 100, 2) AS failure_rate_pct,
  MAX(job_start_time) AS last_run_time
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation'
  AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY execution_date, job_status
ORDER BY execution_date DESC, job_status;

-- =============================================================================
-- QUERY 2: PERFORMANCE FEEDBACK LOOP HEALTH
-- =============================================================================
-- Monitors the update_caption_performance procedure and data freshness

WITH latest_updates AS (
  SELECT
    page_name,
    COUNT(*) AS caption_count,
    MIN(last_updated) AS oldest_update,
    MAX(last_updated) AS newest_update,
    AVG(total_observations) AS avg_observations,
    AVG(successes + failures) AS avg_trials
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  GROUP BY page_name
)
SELECT
  page_name,
  caption_count,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), oldest_update, HOUR) AS oldest_data_age_hours,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), newest_update, HOUR) AS newest_data_age_hours,
  ROUND(avg_observations, 1) AS avg_observations,
  ROUND(avg_trials, 1) AS avg_trials,
  CASE
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), newest_update, HOUR) > 12 THEN 'STALE'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), newest_update, HOUR) > 8 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS health_status
FROM latest_updates
ORDER BY newest_data_age_hours DESC;

-- =============================================================================
-- QUERY 3: LOCK CLEANUP EFFICIENCY
-- =============================================================================
-- Monitors caption lock cleanup operations

WITH cleanup_stats AS (
  SELECT
    DATE(sweep_time, 'America/Los_Angeles') AS sweep_date,
    COUNT(*) AS sweep_count,
    SUM(total_locks_cleaned) AS total_cleaned,
    AVG(total_locks_cleaned) AS avg_cleaned_per_sweep,
    MAX(total_locks_cleaned) AS max_cleaned,
    AVG(sweep_duration_seconds) AS avg_duration_seconds
  FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
  WHERE sweep_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY sweep_date
)
SELECT
  sweep_date,
  sweep_count,
  total_cleaned,
  ROUND(avg_cleaned_per_sweep, 1) AS avg_cleaned_per_sweep,
  max_cleaned AS max_cleaned_single_sweep,
  ROUND(avg_duration_seconds, 2) AS avg_duration_seconds,
  CASE
    WHEN avg_cleaned_per_sweep > 100 THEN 'HIGH_VOLUME'
    WHEN avg_cleaned_per_sweep > 50 THEN 'MODERATE'
    ELSE 'NORMAL'
  END AS cleanup_volume
FROM cleanup_stats
ORDER BY sweep_date DESC;

-- =============================================================================
-- QUERY 4: ACTIVE LOCK TABLE STATUS
-- =============================================================================
-- Current state of active caption assignments

WITH lock_stats AS (
  SELECT
    page_name,
    COUNT(*) AS active_lock_count,
    COUNT(DISTINCT caption_id) AS unique_captions_locked,
    MIN(scheduled_send_date) AS earliest_scheduled,
    MAX(scheduled_send_date) AS latest_scheduled,
    DATE_DIFF(MAX(scheduled_send_date), MIN(scheduled_send_date), DAY) AS schedule_span_days
  FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE is_active = TRUE
  GROUP BY page_name
),
total_captions AS (
  SELECT
    page_name,
    COUNT(*) AS total_available_captions
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  GROUP BY page_name
)
SELECT
  ls.page_name,
  ls.active_lock_count,
  ls.unique_captions_locked,
  tc.total_available_captions,
  ROUND(SAFE_DIVIDE(ls.unique_captions_locked, tc.total_available_captions) * 100, 1) AS saturation_pct,
  ls.earliest_scheduled,
  ls.latest_scheduled,
  ls.schedule_span_days,
  CASE
    WHEN SAFE_DIVIDE(ls.unique_captions_locked, tc.total_available_captions) > 0.8 THEN 'CRITICAL'
    WHEN SAFE_DIVIDE(ls.unique_captions_locked, tc.total_available_captions) > 0.6 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS saturation_status
FROM lock_stats ls
LEFT JOIN total_captions tc USING (page_name)
ORDER BY saturation_pct DESC;

-- =============================================================================
-- QUERY 5: CREATOR-LEVEL FAILURE ANALYSIS
-- =============================================================================
-- Identifies creators with recurring failures

SELECT
  page_name,
  COUNT(DISTINCT DATE(error_time)) AS days_with_errors,
  COUNT(*) AS total_errors,
  MAX(error_time) AS last_error_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(error_time), HOUR) AS hours_since_last_error,
  ARRAY_AGG(DISTINCT error_message LIMIT 3) AS sample_error_messages
FROM `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
WHERE error_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND page_name != 'SYSTEM_CLEANUP'
GROUP BY page_name
HAVING COUNT(*) >= 3
ORDER BY total_errors DESC, last_error_time DESC
LIMIT 20;

-- =============================================================================
-- QUERY 6: AUTOMATION ALERTS SUMMARY
-- =============================================================================
-- Recent alerts grouped by severity and source

WITH recent_alerts AS (
  SELECT
    alert_level,
    alert_source,
    COUNT(*) AS alert_count,
    MAX(alert_time) AS last_alert_time,
    ARRAY_AGG(alert_message ORDER BY alert_time DESC LIMIT 3) AS recent_messages,
    COUNTIF(acknowledged = FALSE) AS unacknowledged_count
  FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
  WHERE alert_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  GROUP BY alert_level, alert_source
)
SELECT
  alert_level,
  alert_source,
  alert_count,
  last_alert_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_alert_time, MINUTE) AS minutes_since_last,
  unacknowledged_count,
  recent_messages[OFFSET(0)] AS most_recent_message
FROM recent_alerts
ORDER BY
  CASE alert_level
    WHEN 'CRITICAL' THEN 1
    WHEN 'WARNING' THEN 2
    ELSE 3
  END,
  alert_count DESC;

-- =============================================================================
-- QUERY 7: SYSTEM HEALTH SCORECARD
-- =============================================================================
-- Overall health metrics with pass/fail indicators

WITH metrics AS (
  SELECT
    -- Daily automation health
    TIMESTAMP_DIFF(
      CURRENT_TIMESTAMP(),
      (SELECT MAX(job_start_time) FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
       WHERE job_name = 'daily_automation'),
      HOUR
    ) AS hours_since_daily_automation,

    -- Performance feedback health
    TIMESTAMP_DIFF(
      CURRENT_TIMESTAMP(),
      (SELECT MAX(last_updated) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`),
      HOUR
    ) AS hours_since_performance_update,

    -- Lock cleanup health
    TIMESTAMP_DIFF(
      CURRENT_TIMESTAMP(),
      (SELECT MAX(sweep_time) FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`),
      HOUR
    ) AS hours_since_lock_cleanup,

    -- Active lock count
    (SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
     WHERE is_active = TRUE) AS active_lock_count,

    -- Recent failures
    (SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
     WHERE job_name = 'daily_automation'
       AND job_status = 'FAILED'
       AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS failed_jobs_7d,

    -- Unacknowledged critical alerts
    (SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
     WHERE alert_level = 'CRITICAL'
       AND acknowledged = FALSE
       AND alert_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) AS critical_alerts_24h
)
SELECT
  'Daily Automation' AS check_name,
  CASE WHEN hours_since_daily_automation <= 28 THEN 'PASS' ELSE 'FAIL' END AS status,
  FORMAT('%d hours ago', hours_since_daily_automation) AS detail,
  'Should run within 28 hours' AS threshold
FROM metrics

UNION ALL

SELECT
  'Performance Updates' AS check_name,
  CASE WHEN hours_since_performance_update <= 8 THEN 'PASS' ELSE 'FAIL' END AS status,
  FORMAT('%d hours ago', hours_since_performance_update) AS detail,
  'Should run within 8 hours' AS threshold
FROM metrics

UNION ALL

SELECT
  'Lock Cleanup' AS check_name,
  CASE WHEN hours_since_lock_cleanup <= 2 THEN 'PASS' ELSE 'FAIL' END AS status,
  FORMAT('%d hours ago', hours_since_lock_cleanup) AS detail,
  'Should run within 2 hours' AS threshold
FROM metrics

UNION ALL

SELECT
  'Active Lock Count' AS check_name,
  CASE WHEN active_lock_count <= 10000 THEN 'PASS' ELSE 'FAIL' END AS status,
  FORMAT('%d active locks', active_lock_count) AS detail,
  'Should be under 10,000' AS threshold
FROM metrics

UNION ALL

SELECT
  'Recent Failures' AS check_name,
  CASE WHEN failed_jobs_7d = 0 THEN 'PASS' ELSE 'WARN' END AS status,
  FORMAT('%d failures in 7 days', failed_jobs_7d) AS detail,
  'Zero failures expected' AS threshold
FROM metrics

UNION ALL

SELECT
  'Critical Alerts' AS check_name,
  CASE WHEN critical_alerts_24h = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  FORMAT('%d unacknowledged', critical_alerts_24h) AS detail,
  'Zero critical alerts expected' AS threshold
FROM metrics

ORDER BY
  CASE status
    WHEN 'FAIL' THEN 1
    WHEN 'WARN' THEN 2
    ELSE 3
  END;

-- =============================================================================
-- QUERY 8: EXECUTION TIME TRENDS
-- =============================================================================
-- Track automation execution times over the last 30 days

SELECT
  DATE(job_start_time, 'America/Los_Angeles') AS execution_date,
  job_name,
  AVG(job_duration_seconds) AS avg_duration_seconds,
  MIN(job_duration_seconds) AS min_duration_seconds,
  MAX(job_duration_seconds) AS max_duration_seconds,
  STDDEV(job_duration_seconds) AS stddev_duration_seconds,
  COUNT(*) AS execution_count
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_status IN ('SUCCESS', 'COMPLETED_WITH_ERRORS')
GROUP BY execution_date, job_name
ORDER BY execution_date DESC, job_name;

-- =============================================================================
-- QUERY 9: STALE DATA DETECTION
-- =============================================================================
-- Find creators with outdated performance metrics

SELECT
  page_name,
  COUNT(*) AS caption_count,
  MAX(last_updated) AS last_update_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) AS hours_stale,
  MAX(last_used) AS last_used_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_used), DAY) AS days_since_use,
  AVG(total_observations) AS avg_observations
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY page_name
HAVING TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) > 12
ORDER BY hours_stale DESC;

-- =============================================================================
-- QUERY 10: SCHEDULE GENERATION QUEUE STATUS
-- =============================================================================
-- Monitor the schedule generation queue for stuck items

SELECT
  status,
  COUNT(*) AS queue_count,
  MIN(queued_at) AS oldest_queued,
  MAX(queued_at) AS newest_queued,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MIN(queued_at), HOUR) AS oldest_age_hours,
  ARRAY_AGG(page_name ORDER BY queued_at LIMIT 5) AS sample_pages
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue`
WHERE execution_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
GROUP BY status
ORDER BY
  CASE status
    WHEN 'FAILED' THEN 1
    WHEN 'PROCESSING' THEN 2
    WHEN 'PENDING' THEN 3
    ELSE 4
  END;

-- =============================================================================
-- USAGE NOTES
-- =============================================================================
-- These queries can be run individually or combined into a monitoring dashboard
-- Recommended: Create a Data Studio or Looker dashboard pointing to these queries
-- Set up automated alerting based on the health scorecard (Query 7)
-- =============================================================================
