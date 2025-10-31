# BigQuery Infrastructure - Quick Reference Card

**Project:** `of-scheduler-proj` | **Dataset:** `eros_scheduling_brain`

---

## 🚀 Deployment (One Command)

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
bq query --project_id=of-scheduler-proj --use_legacy_sql=false < PRODUCTION_INFRASTRUCTURE.sql
```

**Duration:** ~30-60 seconds
**Creates:** 4 UDFs, 3 tables, 1 view, 4 procedures

---

## ✅ Verification (One Command)

```bash
bq query --project_id=of-scheduler-proj --use_legacy_sql=false < verify_production_infrastructure.sql
```

**Expected:** All 21 tests return `PASS ✓`

---

## 📊 Core Objects Reference

### UDFs (4)
```sql
-- Caption key generation
`of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(message STRING) → STRING

-- Backward compatibility
`of-scheduler-proj.eros_scheduling_brain.caption_key`(message STRING) → STRING

-- Wilson confidence bounds
`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(successes INT64, failures INT64)
  → STRUCT<lower_bound FLOAT64, upper_bound FLOAT64, exploration_bonus FLOAT64>

-- Thompson sampling
`of-scheduler-proj.eros_scheduling_brain.wilson_sample`(successes INT64, failures INT64) → FLOAT64
```

### Tables (3)
```sql
-- Caption performance (90d retention)
`of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  Partition: DATE(last_updated)
  Cluster: page_name, caption_id, last_used

-- Holidays (2024-2030)
`of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
  Partition: YEAR(holiday_date)

-- Export telemetry (90d retention)
`of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
  Partition: DATE(export_timestamp)
  Cluster: page_name, status
```

### Views (1)
```sql
-- Schedule export view
`of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
```

### Procedures (4)
```sql
-- Update caption metrics (run every 6h)
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- Daily orchestration (run daily 03:05 LA)
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE('America/Los_Angeles'));

-- Lock cleanup (run hourly)
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();

-- Caption selection (on-demand)
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'page_name',      -- Creator name
  'Standard',       -- Behavioral segment
  5,                -- Budget tier count
  5,                -- Mid tier count
  3,                -- Premium tier count
  2                 -- Bump tier count
);
```

---

## 🔧 Common Operations

### Check Recent Jobs
```sql
SELECT job_id, job_name, job_status, creators_processed, creators_failed, error_message
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY job_start_time DESC;
```

### Check Alerts
```sql
SELECT alert_time, alert_level, alert_source, alert_message
FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
WHERE alert_level = 'CRITICAL' AND acknowledged = FALSE
ORDER BY alert_time DESC;
```

### Monitor Lock Cleanup
```sql
SELECT sweep_time, total_locks_cleaned, sweep_duration_seconds
FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
WHERE sweep_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY sweep_time DESC;
```

### Caption Performance Stats
```sql
SELECT page_name, COUNT(*) as caption_count, AVG(avg_emv) as avg_emv, AVG(total_observations) as avg_obs
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE DATE(last_updated) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY page_name
ORDER BY caption_count DESC
LIMIT 20;
```

---

## 📅 Scheduled Query Configuration

### Update Caption Performance
- **Schedule:** Every 6 hours (0:00, 6:00, 12:00, 18:00 LA time)
- **Query:**
  ```sql
  CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
  ```

### Daily Automation
- **Schedule:** Daily at 03:05 America/Los_Angeles
- **Query:**
  ```sql
  CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE('America/Los_Angeles'));
  ```

### Lock Cleanup
- **Schedule:** Every 1 hour
- **Query:**
  ```sql
  CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
  ```

---

## 🐛 Troubleshooting

### Problem: Procedure fails with "Table not found"
**Solution:** Check dependency tables exist (see INFRASTRUCTURE_DEPLOYMENT_GUIDE.md)

### Problem: UDF returns NULL unexpectedly
**Solution:** Check input parameters are not NULL; UDFs use SAFE_DIVIDE

### Problem: Circuit breaker triggered
**Solution:** Query `creator_processing_errors` table for error details

### Problem: Performance degradation
**Solution:** Verify partition pruning is used (filter on DATE columns)

---

## 🔄 Quick Rollback

### Remove All Infrastructure
```sql
-- WARNING: This deletes data!
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`;
DROP VIEW IF EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`;
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`;
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.wilson_sample`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_key`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`;
```

---

## 📖 Full Documentation

- **Deployment Guide:** `INFRASTRUCTURE_DEPLOYMENT_GUIDE.md`
- **Infrastructure SQL:** `PRODUCTION_INFRASTRUCTURE.sql`
- **Verification Suite:** `verify_production_infrastructure.sql`

---

**Version:** 2.0.0 | **Updated:** 2025-10-31
