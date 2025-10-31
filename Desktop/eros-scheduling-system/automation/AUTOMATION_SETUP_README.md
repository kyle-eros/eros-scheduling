# EROS Scheduling System - Automation Setup Guide

## Overview

This directory contains production-ready automation scripts and configurations for the EROS Scheduling System. The automation orchestrates daily schedule generation, performance feedback loops, and maintenance tasks across all active creators.

**Project:** `of-scheduler-proj`
**Dataset:** `eros_scheduling_brain`
**Timezone:** `America/Los_Angeles`

---

## Architecture

### Automation Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    EROS AUTOMATION PIPELINE                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                │
│  │ Performance Loop │      │ Daily Automation │                │
│  │   Every 6 Hours  │      │  Daily @ 3:05 AM │                │
│  └────────┬─────────┘      └────────┬─────────┘                │
│           │                          │                           │
│           v                          v                           │
│  ┌────────────────────────────────────────────┐                │
│  │   update_caption_performance()              │                │
│  │   - Updates metrics from mass_messages      │                │
│  │   - Calculates Wilson confidence bounds     │                │
│  │   - Updates performance percentiles         │                │
│  └────────────────────────────────────────────┘                │
│                                                                   │
│  ┌────────────────────────────────────────────┐                │
│  │   run_daily_automation()                    │                │
│  │   - Analyzes each active creator            │                │
│  │   - Checks saturation levels                │                │
│  │   - Queues schedule generation              │                │
│  │   - Triggers lock cleanup                   │                │
│  │   - Logs results and errors                 │                │
│  └────────────────────────────────────────────┘                │
│                                                                   │
│  ┌──────────────────┐                                           │
│  │   Lock Cleanup   │                                           │
│  │   Every 1 Hour   │                                           │
│  └────────┬─────────┘                                           │
│           │                                                      │
│           v                                                      │
│  ┌────────────────────────────────────────────┐                │
│  │   sweep_expired_caption_locks()             │                │
│  │   - Deactivates expired locks               │                │
│  │   - Monitors table bloat                    │                │
│  │   - Generates alerts if needed              │                │
│  └────────────────────────────────────────────┘                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files in This Directory

| File | Purpose | Type |
|------|---------|------|
| `run_daily_automation.sql` | Main orchestrator procedure | SQL Procedure |
| `sweep_expired_caption_locks.sql` | Lock cleanup procedure | SQL Procedure |
| `scheduled_queries_config.yaml` | BigQuery scheduled query definitions | Configuration |
| `deploy_scheduled_queries.sh` | Automated deployment script | Bash Script |
| `automation_health_check.sql` | Monitoring and health check queries | SQL Queries |
| `alerts_config.yaml` | Alert rules and notification configuration | Configuration |
| `AUTOMATION_SETUP_README.md` | This file | Documentation |

---

## Quick Start

### Prerequisites

1. **Google Cloud SDK** installed and authenticated
   ```bash
   gcloud auth login
   gcloud config set project of-scheduler-proj
   ```

2. **BigQuery Permissions** - Your service account needs:
   - `bigquery.jobs.create`
   - `bigquery.datasets.get`
   - `bigquery.tables.get`, `bigquery.tables.update`
   - `bigquery.routines.get`, `bigquery.routines.call`
   - `bigquery.transfers.update` (for scheduled queries)

3. **Infrastructure Deployed** - Ensure these are already deployed:
   - `caption_bandit_stats` table
   - `mass_messages` table
   - `caption_bank` table
   - `active_caption_assignments` table
   - `update_caption_performance` procedure
   - `analyze_creator_performance` procedure

### Deployment Steps

#### Step 1: Deploy Stored Procedures

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/automation

# Deploy the orchestrator procedure
bq query --use_legacy_sql=false < run_daily_automation.sql

# Deploy the cleanup procedure
bq query --use_legacy_sql=false < sweep_expired_caption_locks.sql
```

#### Step 2: Verify Procedures

```bash
# List all procedures in the dataset
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain

# Should show:
# - run_daily_automation
# - sweep_expired_caption_locks
# - update_caption_performance
# - analyze_creator_performance
# - lock_caption_assignments
```

#### Step 3: Create Supporting Tables

The procedures will auto-create their supporting tables on first run, but you can pre-create them:

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

#### Step 4: Test Procedures Manually

```bash
# Test the orchestrator (dry run with today's date)
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.run_daily_automation\`(CURRENT_DATE('America/Los_Angeles'))"

# Test lock cleanup
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks\`()"

# Check results
bq query --use_legacy_sql=false \
  "SELECT * FROM \`of-scheduler-proj.eros_scheduling_brain.etl_job_runs\` ORDER BY job_start_time DESC LIMIT 5"
```

#### Step 5: Deploy Scheduled Queries

```bash
# Review what will be deployed (dry run)
./deploy_scheduled_queries.sh --dry-run

# Deploy all scheduled queries
./deploy_scheduled_queries.sh

# Or deploy with automatic confirmation
./deploy_scheduled_queries.sh --force
```

#### Step 6: Verify Scheduled Queries

```bash
# List all scheduled queries
bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj

# Should show:
# - EROS: Caption Performance Updates (every 6 hours)
# - EROS: Daily Schedule Generation (every day 03:05)
# - EROS: Caption Lock Cleanup (every 1 hours)
```

---

## Scheduled Query Details

### 1. Caption Performance Updates

**Procedure:** `update_caption_performance()`
**Schedule:** Every 6 hours
**Purpose:** Updates caption performance metrics based on recent message history

**What it does:**
- Calculates median EMV per page
- Rolls up message data to caption level
- Updates success/failure counts
- Recalculates Wilson confidence bounds
- Updates performance percentiles

**Monitoring:**
```sql
SELECT
  MAX(last_updated) AS last_update,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) AS hours_stale
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
```

**Alert if:** Last update > 8 hours ago (critical at 12 hours)

---

### 2. Daily Schedule Generation

**Procedure:** `run_daily_automation(execution_date)`
**Schedule:** Every day at 3:05 AM America/Los_Angeles
**Purpose:** Orchestrates daily schedule generation for all active creators

**What it does:**
1. Gets list of active creators (from last 30 days of messages)
2. For each creator:
   - Calls `analyze_creator_performance()`
   - Checks saturation levels
   - Queues schedule generation if needed
3. Cleans up expired locks
4. Logs all results and errors
5. Generates alerts on failures

**Circuit Breaker:** Stops processing after 5 consecutive failures

**Monitoring:**
```sql
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation'
ORDER BY job_start_time DESC
LIMIT 5;
```

**Alert if:**
- Job status = 'FAILED'
- No run in 28+ hours
- High failure rate (>10% creators)

---

### 3. Caption Lock Cleanup

**Procedure:** `sweep_expired_caption_locks()`
**Schedule:** Every 1 hour
**Purpose:** Prevents lock table bloat by deactivating expired locks

**What it does:**
- Deactivates locks past scheduled send date
- Deactivates stale locks (>7 days old)
- Logs cleanup statistics
- Alerts on high volume or table bloat

**Monitoring:**
```sql
SELECT
  COUNT(*) AS active_lock_count
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE is_active = TRUE;
```

**Alert if:**
- Active lock count > 5,000 (warning at 10,000 critical)
- Cleanup not run in 2+ hours
- Unusually high cleanup volume (>1000 locks)

---

## Monitoring and Health Checks

### Health Check Dashboard

Run the comprehensive health check:

```bash
bq query --use_legacy_sql=false < automation_health_check.sql
```

This executes 10 monitoring queries:

1. **Daily Automation Status** - Success/failure rates last 7 days
2. **Performance Feedback Health** - Data freshness by creator
3. **Lock Cleanup Efficiency** - Cleanup statistics and trends
4. **Active Lock Table Status** - Current saturation levels
5. **Creator Failure Analysis** - Identifies problematic creators
6. **Alerts Summary** - Recent alerts by severity
7. **System Health Scorecard** - Overall pass/fail status
8. **Execution Time Trends** - Performance over 30 days
9. **Stale Data Detection** - Creators with outdated metrics
10. **Queue Status** - Schedule generation queue monitoring

### Quick Health Check

```sql
-- Overall system health
WITH metrics AS (
  SELECT
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(),
      (SELECT MAX(job_start_time) FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
       WHERE job_name = 'daily_automation'), HOUR) AS hours_since_automation,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(),
      (SELECT MAX(last_updated) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`), HOUR) AS hours_since_performance,
    (SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
     WHERE is_active = TRUE) AS active_locks
)
SELECT
  CASE WHEN hours_since_automation <= 28 THEN '✓' ELSE '✗' END AS daily_automation,
  CASE WHEN hours_since_performance <= 8 THEN '✓' ELSE '✗' END AS performance_updates,
  CASE WHEN active_locks <= 10000 THEN '✓' ELSE '✗' END AS lock_table,
  hours_since_automation,
  hours_since_performance,
  active_locks
FROM metrics;
```

---

## Alerting

### Alert Configuration

The `alerts_config.yaml` file defines all alert rules with three severity levels:

- **CRITICAL** - Requires immediate action (paging)
- **WARNING** - Should be investigated (Slack/email)
- **INFO** - Informational only (optional)

### Setting Up Alerts

**Option 1: Cloud Monitoring (Recommended)**

1. Create log-based metrics:
   ```bash
   gcloud logging metrics create eros_automation_failures \
     --description="EROS automation failures" \
     --log-filter='resource.type="bigquery_project"
       AND protoPayload.methodName="jobservice.insert"
       AND protoPayload.serviceData.jobCompletedEvent.job.jobStatus.error.message=~".*run_daily_automation.*"'
   ```

2. Create alert policies in Cloud Console:
   - Go to Monitoring > Alerting
   - Create policy based on log metrics
   - Configure notification channels

**Option 2: Query automation_alerts Table**

Build a Cloud Function or script that polls the alerts table:

```python
from google.cloud import bigquery

def check_alerts():
    client = bigquery.Client()
    query = """
    SELECT alert_level, alert_source, alert_message
    FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
    WHERE acknowledged = FALSE
      AND alert_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    ORDER BY alert_time DESC
    """

    results = client.query(query).result()

    for row in results:
        if row.alert_level == 'CRITICAL':
            send_pagerduty_alert(row)
        elif row.alert_level == 'WARNING':
            send_slack_alert(row)
```

**Option 3: Email Reports**

Create a Data Studio dashboard and schedule email delivery:
- Daily summary at 9 AM
- Critical alerts immediately

---

## Troubleshooting

### Issue: Daily automation fails

**Check:**
```sql
SELECT job_id, error_message, creators_failed
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation' AND job_status = 'FAILED'
ORDER BY job_start_time DESC LIMIT 1;
```

**Common causes:**
- Missing dependencies (procedures, tables)
- BigQuery quota exceeded
- Permission issues
- Data quality problems in source tables

**Resolution:**
1. Check error message in `etl_job_runs`
2. Review `creator_processing_errors` for specific failures
3. Verify all required procedures exist
4. Check BigQuery quotas

---

### Issue: Performance updates stale

**Check:**
```sql
SELECT MAX(last_updated) AS last_update,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) AS hours_stale
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
```

**Common causes:**
- Scheduled query disabled
- Query execution failures
- Empty `mass_messages` table
- BigQuery slot contention

**Resolution:**
1. Verify scheduled query is enabled:
   ```bash
   bq ls --transfer_config --transfer_location=us
   ```
2. Check scheduled query execution history in BigQuery console
3. Manually trigger update:
   ```sql
   CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
   ```

---

### Issue: Lock table bloat

**Check:**
```sql
SELECT
  is_active,
  COUNT(*) AS lock_count,
  MIN(scheduled_send_date) AS earliest_date,
  MAX(scheduled_send_date) AS latest_date
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
GROUP BY is_active;
```

**Common causes:**
- Lock cleanup not running
- Cleanup scheduled query disabled
- Logic error in cleanup procedure

**Resolution:**
1. Check cleanup scheduled query status
2. Review `lock_sweep_log` for recent runs
3. Manually run cleanup:
   ```sql
   CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
   ```
4. Verify locks are being deactivated (check `is_active = FALSE` count)

---

### Issue: Circuit breaker triggered

**Check:**
```sql
SELECT page_name, error_message, COUNT(*) AS error_count
FROM `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
WHERE error_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY page_name, error_message
ORDER BY error_count DESC;
```

**Common causes:**
- Systematic data quality issue
- Missing data for multiple creators
- Broken dependency

**Resolution:**
1. Identify common error pattern
2. Fix root cause (data, procedure, etc.)
3. Re-run automation manually
4. Consider adjusting circuit breaker threshold if needed

---

## Maintenance

### Regular Tasks

**Daily:**
- Review `etl_job_runs` for failures
- Check unacknowledged critical alerts

**Weekly:**
- Review health check dashboard
- Analyze execution time trends
- Check lock cleanup efficiency

**Monthly:**
- Review and tune alert thresholds
- Analyze creator failure patterns
- Performance optimization review
- Capacity planning

### Capacity Planning

Monitor these metrics for growth trends:

```sql
-- Data volume trends
SELECT
  DATE(job_start_time) AS date,
  AVG(creators_processed) AS avg_creators,
  AVG(job_duration_seconds) AS avg_duration_sec
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation'
  AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY date
ORDER BY date DESC;
```

**Plan for scaling if:**
- Creator count growing >20% per month
- Execution time approaching 10 minutes
- Lock table consistently >8,000 active locks

---

## Advanced Configuration

### Adjusting Schedules

To modify scheduled query timing:

```bash
# Get the transfer config ID
bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj

# Update the schedule
bq update --transfer_config <config_id> --schedule="every 4 hours"
```

### Circuit Breaker Tuning

Edit `run_daily_automation.sql`:

```sql
DECLARE circuit_breaker_threshold INT64 DEFAULT 5;  -- Adjust this value
```

Lower = more sensitive (stops sooner)
Higher = more tolerant (processes more before stopping)

### Saturation Threshold

Edit `run_daily_automation.sql`:

```sql
IF COALESCE(saturation_pct, 0) < 80 THEN  -- Adjust this threshold
```

Lower = schedule more frequently
Higher = allow more caption reuse

### Lock Expiration

Edit `sweep_expired_caption_locks.sql`:

```sql
scheduled_send_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
-- Change INTERVAL 7 DAY to adjust expiration window
```

---

## Integration with External Systems

### Schedule Builder Integration

The automation queues schedule generation but doesn't execute it. Integrate with your Python schedule builder:

```python
from google.cloud import bigquery

def process_schedule_queue():
    client = bigquery.Client()

    # Get pending schedules
    query = """
    SELECT page_name, execution_date, saturation_pct
    FROM `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue`
    WHERE status = 'PENDING'
      AND execution_date = CURRENT_DATE('America/Los_Angeles')
    ORDER BY queued_at
    """

    results = client.query(query).result()

    for row in results:
        try:
            # Mark as processing
            update_status(row.page_name, 'PROCESSING')

            # Run your schedule builder
            schedule_id = generate_schedule(row.page_name, row.execution_date)

            # Mark as completed
            update_status(row.page_name, 'COMPLETED', schedule_id)

        except Exception as e:
            # Mark as failed
            update_status(row.page_name, 'FAILED', error=str(e))
```

### Notification Channels

Configure notification channels in `alerts_config.yaml` and implement notification logic:

- **Email:** SMTP or SendGrid integration
- **Slack:** Webhook URL
- **PagerDuty:** Integration key
- **Google Chat:** Webhook URL

---

## Security Considerations

### Service Account Permissions

Use principle of least privilege. Required permissions:

```yaml
roles:
  - bigquery.dataEditor  # For procedures that modify tables
  - bigquery.jobUser     # To run queries
  - bigquery.user        # To list jobs and datasets
```

### Secrets Management

Never commit credentials. Use:
- Cloud Secret Manager for API keys
- IAM service accounts for GCP authentication
- Environment variables for configuration

### Audit Logging

Enable BigQuery audit logs:
```bash
gcloud logging read "resource.type=bigquery_project" --limit 10
```

---

## Performance Optimization

### Query Optimization

All procedures use:
- Partitioned tables for efficient queries
- Clustered columns for common filters
- Temporary tables to avoid repeated subqueries
- Batch operations instead of row-by-row

### Cost Optimization

Monitor BigQuery costs:
```sql
-- Query costs (last 30 days)
SELECT
  user_email,
  SUM(total_bytes_processed) / POW(10, 12) AS tb_processed,
  SUM(total_bytes_processed) / POW(10, 12) * 5 AS estimated_cost_usd
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND state = 'DONE'
  AND job_type = 'QUERY'
GROUP BY user_email
ORDER BY tb_processed DESC;
```

### Scaling Considerations

Current design handles:
- 100+ active creators
- 10,000+ captions per creator
- 1M+ messages per month

For larger scale, consider:
- Splitting processing by creator cohorts
- Implementing parallel processing
- Using BigQuery BI Engine for dashboards

---

## Support and Contacts

**System Owner:** Data Engineering Team
**On-Call:** DevOps Team
**Escalation:** Platform Engineering Manager

**Useful Resources:**
- BigQuery Documentation: https://cloud.google.com/bigquery/docs
- Scheduled Queries Guide: https://cloud.google.com/bigquery/docs/scheduling-queries
- Monitoring Guide: https://cloud.google.com/bigquery/docs/monitoring

---

## Changelog

### Version 1.0 (2025-10-31)
- Initial automation package release
- Daily orchestrator procedure
- Lock cleanup procedure
- Scheduled query configurations
- Monitoring and alerting framework

---

## Next Steps

After deployment:

1. Monitor first few automated runs closely
2. Set up alerting channels and test notifications
3. Create Data Studio dashboard for daily monitoring
4. Document any creator-specific edge cases
5. Schedule weekly review meetings
6. Plan for scale and optimization

**Ready to deploy? Start with Step 1 of the Quick Start guide above!**
