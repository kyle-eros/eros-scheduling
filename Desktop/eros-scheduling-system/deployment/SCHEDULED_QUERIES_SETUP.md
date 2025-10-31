# SCHEDULED QUERIES CONFIGURATION GUIDE

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Date:** 2025-10-31

---

## Overview

The EROS Scheduling System requires 3 scheduled queries to run automatically. These CANNOT be configured in SQL and must be set up via:
1. BigQuery Console (recommended for first-time setup)
2. bq CLI (provided script)
3. BigQuery Data Transfer Service API

**IMPORTANT:** Scheduled queries are NOT part of the DDL deployment. They must be configured separately.

---

## Prerequisites

Before configuring scheduled queries:

1. ✅ Infrastructure deployed (UDFs, tables)
2. ✅ Stored procedures deployed
3. ✅ Necessary service account permissions
4. ✅ BigQuery Data Transfer API enabled

---

## Method 1: BigQuery Console (Recommended)

### Step-by-Step Instructions

#### Query 1: update_caption_performance

1. Navigate to: https://console.cloud.google.com/bigquery/scheduled-queries?project=of-scheduler-proj
2. Click **+ CREATE SCHEDULED QUERY**
3. Configure:

**Query:**
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
```

**Configuration:**
- Name: `EROS - Update Caption Performance`
- Schedule: `every 6 hours`
- Location: `US`
- Destination:
  - Project: `of-scheduler-proj`
  - Dataset: `eros_scheduling_brain`
  - Table: (none - procedure doesn't return results)
- Advanced Options:
  - Maximum bytes billed: `10737418240` (10 GB)
  - Query timeout: `300` seconds

4. Click **SAVE**

---

#### Query 2: run_daily_automation

1. Click **+ CREATE SCHEDULED QUERY**
2. Configure:

**Query:**
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  CURRENT_DATE('America/Los_Angeles')
);
```

**Configuration:**
- Name: `EROS - Daily Automation`
- Schedule: `every day 03:05`
- Time zone: `America/Los_Angeles (PST)`
- Location: `US`
- Destination:
  - Project: `of-scheduler-proj`
  - Dataset: `eros_scheduling_brain`
  - Table: (none)
- Advanced Options:
  - Maximum bytes billed: `10737418240` (10 GB)
  - Query timeout: `600` seconds (10 minutes)

3. Click **SAVE**

---

#### Query 3: sweep_expired_caption_locks

1. Click **+ CREATE SCHEDULED QUERY**
2. Configure:

**Query:**
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
```

**Configuration:**
- Name: `EROS - Sweep Expired Caption Locks`
- Schedule: `every 1 hours`
- Location: `US`
- Destination:
  - Project: `of-scheduler-proj`
  - Dataset: `eros_scheduling_brain`
  - Table: (none)
- Advanced Options:
  - Maximum bytes billed: `1073741824` (1 GB)
  - Query timeout: `60` seconds

3. Click **SAVE**

---

## Method 2: bq CLI Script

### Quick Setup

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./configure_scheduled_queries.sh
```

This script will create all 3 scheduled queries automatically.

### Manual CLI Commands

If the script doesn't work, create each scheduled query manually:

#### Query 1: update_caption_performance

```bash
bq mk \
  --transfer_config \
  --project_id=of-scheduler-proj \
  --data_source=scheduled_query \
  --display_name="EROS - Update Caption Performance" \
  --target_dataset=eros_scheduling_brain \
  --schedule="every 6 hours" \
  --params='{
    "query":"CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND"
  }' \
  --location=US
```

#### Query 2: run_daily_automation

```bash
bq mk \
  --transfer_config \
  --project_id=of-scheduler-proj \
  --data_source=scheduled_query \
  --display_name="EROS - Daily Automation" \
  --target_dataset=eros_scheduling_brain \
  --schedule="every day 03:05" \
  --schedule_timezone="America/Los_Angeles" \
  --params='{
    "query":"CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE(\"America/Los_Angeles\"));",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND"
  }' \
  --location=US
```

#### Query 3: sweep_expired_caption_locks

```bash
bq mk \
  --transfer_config \
  --project_id=of-scheduler-proj \
  --data_source=scheduled_query \
  --display_name="EROS - Sweep Expired Caption Locks" \
  --target_dataset=eros_scheduling_brain \
  --schedule="every 1 hours" \
  --params='{
    "query":"CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND"
  }' \
  --location=US
```

---

## Verification

After creating scheduled queries, verify they're configured correctly:

### List All Scheduled Queries

```bash
bq ls --transfer_config --project_id=of-scheduler-proj --data_source=scheduled_query
```

### View Specific Query Configuration

```bash
# Get the config ID from the list command above
bq show --transfer_config [CONFIG_ID]
```

### Check Scheduled Query Run History

```bash
bq ls --transfer_run --transfer_config=[CONFIG_ID]
```

---

## Monitoring

### Monitor Execution via Console

1. Navigate to: https://console.cloud.google.com/bigquery/scheduled-queries?project=of-scheduler-proj
2. Click on each scheduled query to view:
   - Run history
   - Success/failure status
   - Execution time
   - Bytes processed
   - Errors (if any)

### Monitor Execution via SQL

```sql
-- Check recent job runs
SELECT
  job_id,
  job_name,
  job_start_time,
  job_end_time,
  job_status,
  creators_processed,
  creators_failed,
  error_message,
  job_duration_seconds
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY job_start_time DESC;
```

```sql
-- Check for alerts
SELECT
  alert_time,
  alert_level,
  alert_source,
  alert_message,
  job_id
FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
WHERE alert_level IN ('WARNING', 'CRITICAL')
  AND acknowledged = FALSE
ORDER BY alert_time DESC;
```

---

## Troubleshooting

### Common Issues

#### Issue: Scheduled query fails with "Procedure not found"

**Solution:** Deploy stored procedures first
```bash
# Verify procedures exist
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | grep -E "(update_caption|run_daily|sweep_expired)"
```

#### Issue: Scheduled query fails with "Permission denied"

**Solution:** Grant necessary permissions to the service account
```bash
# Find the service account
gcloud projects get-iam-policy of-scheduler-proj

# Grant BigQuery Data Editor role
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:[SERVICE_ACCOUNT_EMAIL]" \
  --role="roles/bigquery.dataEditor"
```

#### Issue: Scheduled query times out

**Solution:** Increase timeout in configuration or optimize query
```bash
# Update timeout
bq update --transfer_config [CONFIG_ID] --params='{"query_timeout_ms":600000}'
```

#### Issue: Scheduled query skipped

**Cause:** Previous run still in progress

**Solution:** Check run history and consider adjusting schedule frequency

---

## Schedule Management

### Pause a Scheduled Query

```bash
bq update --transfer_config [CONFIG_ID] --no-update_credentials --disabled=true
```

### Resume a Scheduled Query

```bash
bq update --transfer_config [CONFIG_ID] --no-update_credentials --disabled=false
```

### Update Schedule

```bash
bq update --transfer_config [CONFIG_ID] --schedule="every 12 hours"
```

### Delete Scheduled Query

```bash
bq rm --transfer_config [CONFIG_ID]
```

---

## Cost Management

### Estimated Monthly Costs

Based on typical usage (100 creators, 1M messages/month):

| Scheduled Query | Frequency | Est. Cost/Run | Monthly Cost |
|----------------|-----------|---------------|--------------|
| update_caption_performance | Every 6 hours (120/month) | $0.05 | $6.00 |
| run_daily_automation | Daily (30/month) | $0.02 | $0.60 |
| sweep_expired_caption_locks | Hourly (720/month) | $0.01 | $7.20 |
| **TOTAL** | | | **~$13.80** |

### Cost Optimization Tips

1. **Adjust frequency based on usage:**
   - If caption usage is low, reduce update_caption_performance to every 12 hours
   - If no active scheduling, pause run_daily_automation

2. **Set maximum bytes billed:**
   - Already configured in console/CLI commands above
   - Prevents runaway costs from unexpected data growth

3. **Monitor query performance:**
   ```sql
   SELECT
     job_name,
     AVG(job_duration_seconds) AS avg_duration,
     COUNT(*) AS run_count
   FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
   WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
   GROUP BY job_name;
   ```

---

## Testing

### Manual Test Runs

Before enabling scheduled queries, test each procedure manually:

```sql
-- Test update_caption_performance
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- Verify results
SELECT COUNT(*) AS stats_rows
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;

-- Test run_daily_automation
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  CURRENT_DATE('America/Los_Angeles')
);

-- Check job log
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
ORDER BY job_start_time DESC
LIMIT 1;

-- Test sweep_expired_caption_locks
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();

-- Check sweep log
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
ORDER BY sweep_time DESC
LIMIT 1;
```

---

## Alerting Setup

### Email Notifications

Configure email alerts for scheduled query failures:

1. Navigate to: https://console.cloud.google.com/bigquery/scheduled-queries?project=of-scheduler-proj
2. Click on each scheduled query
3. Click **EMAIL NOTIFICATIONS**
4. Add email addresses (e.g., kyle@erosops.com)
5. Select notification preferences:
   - ✅ On failure
   - ✅ On success (optional, can be noisy)
   - ✅ On skip

### Cloud Monitoring Alerts

Create uptime checks for scheduled query execution:

```bash
# Create alert policy for failed runs
gcloud alpha monitoring policies create \
  --notification-channels=[CHANNEL_ID] \
  --display-name="EROS Scheduled Query Failures" \
  --condition-display-name="Query failures in last hour" \
  --condition-expression='
    resource.type = "bigquery_project"
    AND metric.type = "bigquery.googleapis.com/query/execution_times"
    AND metadata.user_labels.status = "failure"
  '
```

---

## Best Practices

1. **Start with manual testing:** Run each procedure manually before scheduling
2. **Monitor for 24 hours:** Check run history and logs after initial setup
3. **Set up alerting early:** Configure email notifications on day 1
4. **Review logs weekly:** Check etl_job_runs and automation_alerts tables
5. **Optimize schedules:** Adjust frequency based on actual data update patterns
6. **Document changes:** Log any schedule or configuration changes
7. **Test rollback:** Ensure you can pause/disable queries quickly if needed

---

## Support

- BigQuery Console: https://console.cloud.google.com/bigquery?project=of-scheduler-proj
- Scheduled Queries: https://console.cloud.google.com/bigquery/scheduled-queries?project=of-scheduler-proj
- Documentation: https://cloud.google.com/bigquery/docs/scheduling-queries
- Support: kyle@erosops.com

---

**Last Updated:** 2025-10-31
**Maintained By:** EROS Engineering Team
