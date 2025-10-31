# EROS Automation - Deployment Checklist

## Pre-Deployment Prerequisites

- [ ] **Infrastructure deployed** - All base tables and procedures exist
  - [ ] `caption_bandit_stats` table
  - [ ] `mass_messages` table
  - [ ] `caption_bank` table
  - [ ] `active_caption_assignments` table
  - [ ] `update_caption_performance` procedure
  - [ ] `analyze_creator_performance` procedure
  - [ ] `lock_caption_assignments` procedure

- [ ] **Google Cloud SDK installed and configured**
  ```bash
  gcloud --version
  gcloud auth list
  ```

- [ ] **BigQuery permissions verified**
  - [ ] `bigquery.jobs.create`
  - [ ] `bigquery.datasets.get`
  - [ ] `bigquery.tables.get`, `bigquery.tables.update`
  - [ ] `bigquery.routines.get`, `bigquery.routines.call`
  - [ ] `bigquery.transfers.update`

- [ ] **Project access confirmed**
  ```bash
  gcloud config set project of-scheduler-proj
  bq ls eros_scheduling_brain
  ```

---

## Step 1: Deploy Automation Procedures

### 1.1 Deploy run_daily_automation procedure

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/automation
bq query --use_legacy_sql=false < run_daily_automation.sql
```

**Verify:**
```bash
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | grep run_daily_automation
```

- [ ] Procedure deployed successfully
- [ ] No syntax errors

### 1.2 Deploy sweep_expired_caption_locks procedure

```bash
bq query --use_legacy_sql=false < sweep_expired_caption_locks.sql
```

**Verify:**
```bash
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | grep sweep_expired_caption_locks
```

- [ ] Procedure deployed successfully
- [ ] No syntax errors

---

## Step 2: Create Supporting Tables

Run this SQL to pre-create all supporting tables:

```sql
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

-- Creator Processing Errors
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
  status STRING NOT NULL,
  schedule_id STRING,
  error_message STRING
)
PARTITION BY execution_date
CLUSTER BY status, page_name;

-- Automation Alerts
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.automation_alerts` (
  alert_id STRING DEFAULT GENERATE_UUID(),
  alert_time TIMESTAMP NOT NULL,
  alert_level STRING NOT NULL,
  alert_source STRING NOT NULL,
  alert_message STRING,
  job_id STRING,
  acknowledged BOOL DEFAULT FALSE,
  acknowledged_at TIMESTAMP,
  acknowledged_by STRING
)
PARTITION BY DATE(alert_time)
CLUSTER BY alert_level, alert_source, acknowledged;

-- Lock Sweep Log
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
```

**Verify:**
```bash
bq ls --project_id=of-scheduler-proj eros_scheduling_brain | grep -E "(etl_job_runs|creator_processing_errors|schedule_generation_queue|automation_alerts|lock_sweep_log)"
```

- [ ] All 5 supporting tables created
- [ ] No creation errors

---

## Step 3: Test Procedures

### 3.1 Run automated test suite

```bash
./test_automation.sh
```

- [ ] All tests passed
- [ ] No errors in test output

### 3.2 Manual procedure tests

**Test lock cleanup:**
```bash
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks\`()"
```

- [ ] Executed successfully
- [ ] Results show cleanup summary

**Test performance update:**
```bash
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.update_caption_performance\`()"
```

- [ ] Executed successfully
- [ ] No errors or warnings

**Test daily automation:**
```bash
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.run_daily_automation\`(CURRENT_DATE('America/Los_Angeles'))"
```

- [ ] Executed successfully
- [ ] Job logged in `etl_job_runs` table
- [ ] Check results:
  ```bash
  bq query --use_legacy_sql=false \
    "SELECT * FROM \`of-scheduler-proj.eros_scheduling_brain.etl_job_runs\` ORDER BY job_start_time DESC LIMIT 5"
  ```

---

## Step 4: Deploy Scheduled Queries

### 4.1 Dry run deployment

```bash
./deploy_scheduled_queries.sh --dry-run
```

- [ ] Dry run shows 3 scheduled queries
- [ ] No validation errors
- [ ] Output looks correct

### 4.2 Deploy scheduled queries

```bash
./deploy_scheduled_queries.sh
```

- [ ] Confirmed deployment
- [ ] All 3 queries deployed successfully
- [ ] No deployment errors

### 4.3 Verify scheduled queries

```bash
bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj
```

**Expected queries:**
- [ ] EROS: Caption Performance Updates (every 6 hours)
- [ ] EROS: Daily Schedule Generation (every day 03:05)
- [ ] EROS: Caption Lock Cleanup (every 1 hours)

### 4.4 Check scheduled query details

```bash
bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj --format=json | jq '.'
```

- [ ] All queries have correct schedules
- [ ] All queries are enabled
- [ ] Timezone is America/Los_Angeles

---

## Step 5: Set Up Monitoring

### 5.1 Test health check queries

```bash
bq query --use_legacy_sql=false < automation_health_check.sql
```

- [ ] All 10 health check queries execute successfully
- [ ] Results show current system state

### 5.2 Create monitoring dashboard (optional)

Options:
- [ ] **Data Studio:** Create dashboard from health check queries
- [ ] **Cloud Monitoring:** Set up log-based metrics
- [ ] **Custom dashboard:** Use health check queries

### 5.3 Document monitoring access

- [ ] Dashboard URL documented: ___________________________
- [ ] Access granted to: _________________________________
- [ ] On-call team notified: _____________________________

---

## Step 6: Configure Alerting

### 6.1 Review alerts_config.yaml

```bash
cat alerts_config.yaml
```

- [ ] Alert rules reviewed
- [ ] Thresholds appropriate for system
- [ ] Notification channels identified

### 6.2 Set up notification channels

Choose implementation option:

**Option 1: Cloud Monitoring**
- [ ] Create log-based metrics
- [ ] Create alert policies
- [ ] Configure notification channels
- [ ] Test critical alert

**Option 2: Custom alert processor**
- [ ] Deploy Cloud Function or script
- [ ] Configure polling schedule
- [ ] Set up notification integrations
- [ ] Test alert delivery

**Option 3: Manual monitoring**
- [ ] Schedule daily dashboard review
- [ ] Document manual check process
- [ ] Set up email reports

### 6.3 Test alerting

```sql
-- Generate test alert
INSERT INTO `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
  (alert_time, alert_level, alert_source, alert_message)
VALUES
  (CURRENT_TIMESTAMP(), 'WARNING', 'test', 'Test alert - please acknowledge');
```

- [ ] Alert appears in alerts table
- [ ] Alert notification received (if configured)
- [ ] Alert can be acknowledged

---

## Step 7: Post-Deployment Verification

### 7.1 Monitor first scheduled runs

**Next scheduled runs:**
- Lock cleanup: Within 1 hour
- Performance update: Within 6 hours
- Daily automation: Next day at 3:05 AM LA time

**Verification queries:**

```sql
-- Check recent job runs
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
ORDER BY job_start_time DESC LIMIT 10;

-- Check recent lock cleanups
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
ORDER BY sweep_time DESC LIMIT 10;

-- Check for any alerts
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
WHERE alert_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY alert_time DESC;
```

- [ ] Lock cleanup ran successfully within 1 hour
- [ ] Performance update ran successfully within 6 hours
- [ ] Daily automation scheduled for next run
- [ ] No critical alerts generated

### 7.2 Run comprehensive health check

```bash
bq query --use_legacy_sql=false < automation_health_check.sql
```

**Review all health checks:**
- [ ] Daily automation status: HEALTHY
- [ ] Performance updates: HEALTHY
- [ ] Lock cleanup: HEALTHY
- [ ] Active lock count: Normal (<5000)
- [ ] No stale data detected
- [ ] No unacknowledged critical alerts

---

## Step 8: Documentation and Handoff

### 8.1 Update documentation

- [ ] System architecture documented
- [ ] Runbook created/updated
- [ ] Troubleshooting guide reviewed
- [ ] Alert response procedures documented

### 8.2 Team training

- [ ] Operations team trained on monitoring
- [ ] On-call team trained on troubleshooting
- [ ] Access permissions documented
- [ ] Escalation procedures defined

### 8.3 Schedule follow-ups

- [ ] **Day 1:** Monitor first daily automation run
- [ ] **Day 3:** Review all automated runs
- [ ] **Week 1:** Full health check and optimization review
- [ ] **Month 1:** Performance review and tuning

---

## Step 9: Optional Enhancements

### 9.1 Schedule builder integration

- [ ] Update Python schedule builder to poll `schedule_generation_queue`
- [ ] Implement queue processing logic
- [ ] Update queue status after processing
- [ ] Test end-to-end flow

### 9.2 Advanced monitoring

- [ ] Set up Cloud Monitoring dashboards
- [ ] Configure budget alerts
- [ ] Set up BigQuery quota monitoring
- [ ] Create SLO/SLI metrics

### 9.3 Optimization

- [ ] Review and tune circuit breaker threshold
- [ ] Adjust saturation percentage if needed
- [ ] Optimize query performance if slow
- [ ] Review and adjust lock expiration window

---

## Rollback Plan

If issues occur, rollback procedure:

### Disable scheduled queries

```bash
# Get config IDs
bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj

# Disable each query
bq update --transfer_config <config_id> --no_enable_refresh
```

### Delete scheduled queries (if needed)

```bash
bq rm --transfer_config <config_id>
```

### Manual cleanup

```sql
-- Manually clean up any stuck jobs
UPDATE `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue`
SET status = 'FAILED', error_message = 'Manual rollback'
WHERE status = 'PROCESSING';
```

---

## Support Contacts

**On-Call Team:** ________________________________
**DevOps Lead:** __________________________________
**Data Engineering:** _____________________________
**Escalation:** ___________________________________

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployer | | | |
| Reviewer | | | |
| Approver | | | |

---

## Deployment Log

| Date | Time | Event | Notes |
|------|------|-------|-------|
| | | Procedures deployed | |
| | | Tables created | |
| | | Tests passed | |
| | | Scheduled queries deployed | |
| | | First runs verified | |
| | | Sign-off completed | |

---

**Status:** [ ] Not Started [ ] In Progress [ ] Completed [ ] Rolled Back

**Completion Date:** ___________________

**Notes:**
_____________________________________________________________________________
_____________________________________________________________________________
_____________________________________________________________________________
