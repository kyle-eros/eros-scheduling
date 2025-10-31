# EROS Scheduling System - Operational Runbook

**Version:** 1.0
**Last Updated:** 2025-10-31
**Owner:** DevOps Team
**Status:** Production Ready

---

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring and Alerting](#monitoring-and-alerting)
3. [Incident Response](#incident-response)
4. [Rollback Procedures](#rollback-procedures)
5. [Performance Tuning](#performance-tuning)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Maintenance Tasks](#maintenance-tasks)
8. [Emergency Contacts](#emergency-contacts)

---

## Daily Operations

### Morning Health Check (10 minutes)

**Frequency:** Every weekday at 9:00 AM PT

```bash
# 1. Check system health
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
bq query --use_legacy_sql=false < monitor_deployment.sql

# 2. Review error logs
grep ERROR /var/log/eros/application/eros_$(date +%Y%m%d).log | tail -20

# 3. Check query costs (last 24 hours)
bq query --use_legacy_sql=false "
SELECT
    DATE(creation_time) as date,
    COUNT(*) as query_count,
    SUM(total_bytes_billed)/1024/1024/1024 as gb_billed,
    SUM(total_bytes_billed)/1024/1024/1024*0.005 as cost_usd
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    AND statement_type = 'SELECT'
GROUP BY date
ORDER BY date DESC
"

# 4. Check caption assignment stats
bq query --use_legacy_sql=false "
SELECT
    COUNT(*) as total_assignments,
    COUNT(DISTINCT caption_id) as unique_captions,
    COUNT(DISTINCT account_id) as unique_accounts
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
WHERE assigned_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
"

# 5. Check for expired locks
bq query --use_legacy_sql=false "
SELECT COUNT(*) as expired_locks
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_locks\`
WHERE expires_at < CURRENT_TIMESTAMP()
"
```

**Expected Results:**
- System health score: >90/100
- Error count: <10 in last 24 hours
- Daily query cost: <$15
- No expired locks

**Actions if Failed:**
- Health score <90: Review failed checks and investigate
- Error count >10: Review error logs for patterns
- Daily cost >$15: Check for runaway queries
- Expired locks >0: Run cleanup procedure (see Maintenance)

---

### Weekly Schedule Generation

**Frequency:** Every Monday at 10:00 AM PT

```bash
# 1. Set environment
export EROS_PROJECT_ID="of-scheduler-proj"
export EROS_DATASET="eros_scheduling_brain"

# 2. Get active creators
cd /Users/kylemerriman/Desktop/eros-scheduling-system/python

# 3. Generate schedules
python schedule_builder.py \
    --page-name jadebri \
    --start-date $(date -d "next Monday" +%Y-%m-%d) \
    --output schedules/jadebri_$(date +%Y%m%d).csv

# Repeat for all active creators

# 4. Export to Google Sheets
python sheets_export_client.py --schedule-id <schedule_id>

# 5. Verify exports
ls -lh schedules/*$(date +%Y%m%d).csv
```

**Success Criteria:**
- All CSV files generated
- No error messages
- Files sizes >1KB
- Google Sheets updated successfully

---

## Monitoring and Alerting

### Key Metrics to Monitor

#### System Health Metrics

| Metric | Threshold | Alert Level | Action |
|--------|-----------|-------------|--------|
| Query execution time | >30s | Warning | Investigate slow queries |
| Query execution time | >60s | Critical | Check for query complexity issues |
| Daily query cost | >$15 | Warning | Review query patterns |
| Daily query cost | >$25 | Critical | Investigate runaway queries |
| Error rate | >5/hour | Warning | Check error logs |
| Error rate | >20/hour | Critical | Investigate system issues |
| Duplicate assignments | >0 | Critical | Check race condition handling |

#### Business Metrics

| Metric | Threshold | Alert Level | Action |
|--------|-----------|-------------|--------|
| Schedule generation failures | >2/day | Warning | Review creator data |
| Caption selection failures | >5/day | Warning | Check caption bank |
| Export failures | >3/day | Critical | Check Google Sheets API |
| Average EMV | Drops >15% | Warning | Review caption performance |

### Monitoring Queries

#### Real-Time Health Check
```sql
-- Run every 5 minutes via scheduled query
SELECT
    CURRENT_TIMESTAMP() as check_time,

    -- Query performance
    (SELECT COUNT(*)
     FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
     WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
         AND total_slot_ms > 60000) as slow_queries,

    -- Error count
    (SELECT COUNT(*)
     FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
     WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
         AND error_result IS NOT NULL) as query_errors,

    -- Active locks
    (SELECT COUNT(*)
     FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_locks\`
     WHERE expires_at > CURRENT_TIMESTAMP()) as active_locks,

    -- Recent assignments
    (SELECT COUNT(*)
     FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
     WHERE assigned_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)) as recent_assignments
```

#### Daily Performance Report
```sql
-- Run daily at 8:00 AM PT
WITH daily_stats AS (
    SELECT
        DATE(creation_time) as date,
        COUNT(*) as total_queries,
        AVG(total_slot_ms)/1000 as avg_execution_seconds,
        SUM(total_bytes_billed)/1024/1024/1024 as gb_billed,
        SUM(total_bytes_billed)/1024/1024/1024*0.005 as cost_usd,
        COUNTIF(error_result IS NOT NULL) as error_count
    FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE DATE(creation_time) = CURRENT_DATE() - 1
    GROUP BY date
)
SELECT
    date,
    total_queries,
    ROUND(avg_execution_seconds, 2) as avg_execution_seconds,
    ROUND(gb_billed, 2) as gb_billed,
    ROUND(cost_usd, 2) as cost_usd,
    error_count,
    CASE
        WHEN cost_usd > 25 THEN 'CRITICAL'
        WHEN cost_usd > 15 THEN 'WARNING'
        ELSE 'OK'
    END as status
FROM daily_stats
```

### Alert Notifications

#### Setting Up Alerts

**Using BigQuery Scheduled Queries:**

1. Create scheduled query for health checks
2. Configure email notifications
3. Set alert thresholds

```bash
# Create scheduled query
bq mk --transfer_config \
    --project_id="${EROS_PROJECT_ID}" \
    --data_source=scheduled_query \
    --display_name="EROS Health Check" \
    --schedule="every 5 minutes" \
    --notification_pubsub_topic="projects/${EROS_PROJECT_ID}/topics/eros-alerts" \
    --params='{
        "query":"<health_check_query>",
        "destination_table_name_template":"health_checks",
        "write_disposition":"WRITE_APPEND"
    }'
```

**Email Alerts:**
```bash
# Configure Cloud Monitoring alerts
gcloud alpha monitoring policies create \
    --notification-channels="${NOTIFICATION_CHANNEL_ID}" \
    --display-name="EROS High Query Cost" \
    --condition-display-name="Daily cost > $15" \
    --condition-threshold-value=15 \
    --condition-threshold-duration=3600s
```

---

## Incident Response

### Incident Severity Levels

| Level | Description | Response Time | Escalation |
|-------|-------------|---------------|------------|
| P0 - Critical | Complete system outage | 15 minutes | Immediate |
| P1 - High | Partial outage, data loss | 30 minutes | 1 hour |
| P2 - Medium | Degraded performance | 2 hours | 4 hours |
| P3 - Low | Minor issues, cosmetic | Next business day | - |

### Incident Response Procedures

#### P0: System Outage

**Symptoms:**
- Cannot connect to BigQuery
- All queries failing
- Deployment scripts fail

**Immediate Actions:**
1. Check GCP status: https://status.cloud.google.com/
2. Verify authentication: `gcloud auth list`
3. Check project billing: `gcloud billing projects describe ${EROS_PROJECT_ID}`
4. Review error logs

**Recovery Steps:**
```bash
# 1. Verify system access
gcloud auth list
gcloud config get-value project

# 2. Check BigQuery status
bq ls ${EROS_PROJECT_ID}:${EROS_DATASET}

# 3. If accessible, check for locks
bq query --use_legacy_sql=false "
SELECT COUNT(*) FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_locks\`
WHERE expires_at > CURRENT_TIMESTAMP()
"

# 4. Clear all locks if needed
bq query --use_legacy_sql=false "
DELETE FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_locks\`
WHERE TRUE
"

# 5. Test basic functionality
cd /Users/kylemerriman/Desktop/eros-scheduling-system/tests
./run_validation_tests.sh
```

#### P1: Data Corruption

**Symptoms:**
- Duplicate caption assignments
- Negative values in stats
- Missing schedule data

**Immediate Actions:**
1. Stop all scheduled jobs
2. Create emergency backup
3. Assess corruption extent

**Recovery Steps:**
```bash
# 1. Emergency backup
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./backup_tables.sh

# 2. Check data integrity
bq query --use_legacy_sql=false "
SELECT
    'caption_bandit_stats' as table_name,
    COUNT(*) as corrupt_records
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bandit_stats\`
WHERE total_views < 0 OR engagement_count < 0

UNION ALL

SELECT
    'duplicate_assignments' as table_name,
    COUNT(*) as corrupt_records
FROM (
    SELECT caption_id, account_id, COUNT(*) as cnt
    FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
    GROUP BY caption_id, account_id
    HAVING cnt > 1
)
"

# 3. If corruption confirmed, rollback
./rollback.sh
```

#### P2: Performance Degradation

**Symptoms:**
- Queries taking >30s
- High BigQuery costs
- Slow schedule generation

**Immediate Actions:**
1. Identify slow queries
2. Check for table scans
3. Review query patterns

**Recovery Steps:**
```bash
# 1. Find slow queries
bq query --use_legacy_sql=false "
SELECT
    job_id,
    creation_time,
    query,
    total_slot_ms/1000 as execution_seconds,
    total_bytes_billed/1024/1024/1024 as gb_billed
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    AND total_slot_ms > 60000
ORDER BY total_slot_ms DESC
LIMIT 10
"

# 2. Cancel long-running queries if needed
bq cancel <job_id>

# 3. Review table clustering
bq show --schema --format=prettyjson \
    ${EROS_PROJECT_ID}:${EROS_DATASET}.caption_bandit_stats

# 4. Run optimization
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./deploy_phase2.sh  # Re-run optimizations
```

### Incident Communication Template

```
Subject: [EROS] P<X> Incident - <Brief Description>

Incident ID: INC-<YYYYMMDD>-<NNN>
Severity: P<X>
Status: <Investigating|Mitigating|Resolved>
Start Time: YYYY-MM-DD HH:MM:SS PT
Detection Method: <Monitoring|User Report|etc>

IMPACT:
- Affected Systems:
- Affected Users:
- Business Impact:

CURRENT STATUS:
- Root Cause: <Under investigation|Identified|etc>
- Actions Taken:
  1.
  2.

NEXT STEPS:
-
-
-

ETA for Resolution:

Updates will be provided every [15|30|60] minutes.

Contact: <On-call engineer>
```

---

## Rollback Procedures

### When to Rollback

Rollback immediately if:
- Data corruption detected
- >50% queries failing
- Duplicate caption assignments detected
- Critical business logic error
- Unplanned schema changes

### Rollback Execution

#### Quick Rollback (5 minutes)
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment

# Use latest backup
./rollback.sh

# Or specify backup timestamp
./rollback.sh 2025-10-31_143022
```

#### Rollback Steps

The rollback script automatically:
1. ✅ Verifies backup exists
2. ✅ Requires confirmation (type "ROLLBACK")
3. ✅ Creates pre-rollback snapshot
4. ✅ Disables scheduled queries
5. ✅ Clears caption locks
6. ✅ Restores tables from backup
7. ✅ Verifies data integrity
8. ✅ Sends alert notifications

#### Post-Rollback Validation

```bash
# 1. Check table counts
bq query --use_legacy_sql=false "
SELECT
    'caption_bank' as table_name,
    COUNT(*) as row_count
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bank\`

UNION ALL

SELECT
    'caption_bandit_stats' as table_name,
    COUNT(*) as row_count
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bandit_stats\`

UNION ALL

SELECT
    'active_caption_assignments' as table_name,
    COUNT(*) as row_count
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
"

# 2. Run validation tests
cd /Users/kylemerriman/Desktop/eros-scheduling-system/tests
./run_validation_tests.sh

# 3. Test basic functionality
python test_schedule_builder.py
```

#### Re-enabling System

After successful rollback:
```bash
# 1. Monitor for 30 minutes
# 2. Re-enable scheduled queries (manual in console)
# 3. Test schedule generation for 1 creator
# 4. Gradually increase load
# 5. Document incident in post-mortem
```

---

## Performance Tuning

### Query Optimization

#### Slow Query Analysis
```sql
-- Find expensive queries
SELECT
    user_email,
    query,
    total_slot_ms/1000 as execution_seconds,
    total_bytes_processed/1024/1024/1024 as gb_processed,
    total_bytes_billed/1024/1024/1024*0.005 as cost_usd,
    cache_hit
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time) = CURRENT_DATE()
    AND total_bytes_billed > 1024*1024*1024  -- >1GB
ORDER BY total_bytes_billed DESC
LIMIT 20
```

#### Optimization Techniques

**1. Add Clustering:**
```sql
-- Recreate table with clustering
CREATE OR REPLACE TABLE \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bandit_stats_optimized\`
PARTITION BY DATE(last_updated)
CLUSTER BY caption_id, wilson_score_lower_bound
AS SELECT * FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bandit_stats\`
```

**2. Use Materialized Views:**
```sql
-- Create materialized view for frequent queries
CREATE MATERIALIZED VIEW \`${EROS_PROJECT_ID}.${EROS_DATASET}.top_captions_mv\`
PARTITION BY DATE(last_updated)
AS
SELECT
    caption_id,
    total_views,
    engagement_count,
    wilson_score_lower_bound,
    last_updated
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bandit_stats\`
WHERE total_views >= 30
    AND wilson_score_lower_bound >= 0.5
```

**3. Enable Query Caching:**
```bash
# Set cache preferences
bq query --use_cache=true --use_legacy_sql=false "<query>"
```

### Cost Optimization

#### Cost Reduction Strategies

**1. Partition Pruning:**
```sql
-- BAD: Scans entire table
SELECT * FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`

-- GOOD: Uses partition pruning
SELECT * FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
WHERE DATE(assigned_at) >= CURRENT_DATE() - 7
```

**2. Column Projection:**
```sql
-- BAD: Selects all columns
SELECT * FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bank\`

-- GOOD: Selects only needed columns
SELECT caption_id, caption_text, category
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_bank\`
```

**3. Query Result Caching:**
- Enable caching for repeated queries
- Use scheduled queries for aggregations
- Cache frequently accessed data in materialized views

### Performance Benchmarks

| Operation | Target | Current | Action if Exceeded |
|-----------|--------|---------|-------------------|
| Caption selection | <2s | ~1.5s | Check clustering |
| Schedule generation | <10s | ~8s | Optimize queries |
| Performance analysis | <5s | ~3s | Add indexes |
| Full orchestration | <30s | ~24s | Review parallelization |

---

## Troubleshooting Guide

### Common Issues

#### Issue: "Dataset not found"
```bash
# Check dataset exists
bq ls ${EROS_PROJECT_ID}:

# Create if missing
bq mk --dataset ${EROS_PROJECT_ID}:${EROS_DATASET}
```

#### Issue: "Permission denied"
```bash
# Check current authentication
gcloud auth list

# Re-authenticate
gcloud auth login
gcloud auth application-default login

# Verify project access
gcloud projects get-iam-policy ${EROS_PROJECT_ID}
```

#### Issue: "Duplicate caption assignments"
```bash
# Find duplicates
bq query --use_legacy_sql=false "
SELECT caption_id, account_id, COUNT(*) as count
FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
GROUP BY caption_id, account_id
HAVING count > 1
"

# Remove duplicates (keep most recent)
bq query --use_legacy_sql=false "
DELETE FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
WHERE (caption_id, account_id, assigned_at) NOT IN (
    SELECT caption_id, account_id, MAX(assigned_at)
    FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
    GROUP BY caption_id, account_id
)
"
```

#### Issue: "Query timeout"
```bash
# Check query execution time
bq query --use_legacy_sql=false "
SELECT job_id, total_slot_ms/1000 as seconds
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY total_slot_ms DESC
LIMIT 5
"

# Increase timeout
bq query --max_wait_time=300 --use_legacy_sql=false "<query>"
```

#### Issue: "High costs"
```bash
# Identify expensive operations
bq query --use_legacy_sql=false "
SELECT
    user_email,
    query,
    total_bytes_billed/1024/1024/1024*0.005 as cost_usd
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time) = CURRENT_DATE()
ORDER BY total_bytes_billed DESC
LIMIT 10
"

# Set billing limits (requires project owner)
# Go to: https://console.cloud.google.com/bigquery/quotas
```

---

## Maintenance Tasks

### Daily Tasks
- ✅ Review health check dashboard
- ✅ Check error logs
- ✅ Monitor query costs

### Weekly Tasks
- ✅ Generate creator schedules
- ✅ Review performance metrics
- ✅ Clean up expired locks
- ✅ Rotate logs

### Monthly Tasks
- ✅ Review capacity planning
- ✅ Update documentation
- ✅ Test rollback procedures
- ✅ Security audit

### Quarterly Tasks
- ✅ Disaster recovery drill
- ✅ Performance optimization review
- ✅ Cost optimization analysis
- ✅ Update runbook

### Maintenance Scripts

#### Clean Up Expired Locks
```bash
# Run daily via cron
bq query --use_legacy_sql=false "
DELETE FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.caption_locks\`
WHERE expires_at < CURRENT_TIMESTAMP()
"
```

#### Archive Old Assignments
```bash
# Run weekly
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`${EROS_PROJECT_ID}.${EROS_DATASET}.archived_assignments_$(date +%Y%m%d)\`
AS
SELECT * FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
WHERE assigned_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);

DELETE FROM \`${EROS_PROJECT_ID}.${EROS_DATASET}.active_caption_assignments\`
WHERE assigned_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);
"
```

#### Log Rotation
```bash
# Run daily via cron
source /Users/kylemerriman/Desktop/eros-scheduling-system/deployment/logging_config.sh
rotate_logs
rotate_audit_logs
```

---

## Emergency Contacts

### On-Call Rotation

| Day | Primary | Secondary | Manager |
|-----|---------|-----------|---------|
| Mon-Fri 9-5 PT | DevOps Team | Engineering | Tech Lead |
| After hours | On-call Engineer | Backup On-call | Manager |
| Weekends | On-call Engineer | Backup On-call | Manager |

### Escalation Path

1. **L1 - On-Call Engineer** (15 min response)
   - Initial investigation
   - Standard troubleshooting
   - Execute runbook procedures

2. **L2 - Senior Engineer** (30 min response)
   - Complex issues
   - Code changes required
   - Performance optimization

3. **L3 - Engineering Manager** (1 hour response)
   - System architecture decisions
   - Resource allocation
   - Vendor escalation

4. **L4 - CTO/VP Engineering** (2 hour response)
   - Business-critical outages
   - Customer communication
   - Executive decision needed

### Contact Information

```
PRIMARY CONTACT:
- Slack: #eros-incidents
- Email: devops@company.com
- Phone: [REDACTED]

ESCALATION:
- Engineering Manager: [REDACTED]
- Tech Lead: [REDACTED]
- CTO: [REDACTED]

VENDORS:
- Google Cloud Support: https://cloud.google.com/support
- Support Case Priority: P1 for outages
```

---

## Appendix

### Useful Commands Reference

```bash
# Check system status
bq query --use_legacy_sql=false < monitor_deployment.sql

# View recent errors
grep ERROR /var/log/eros/application/*.log | tail -50

# Check query costs
bq ls -j -a --max_results=10 ${EROS_PROJECT_ID}

# Export schedule
python schedule_builder.py --page-name <name> --start-date <date>

# Run tests
cd tests && ./run_validation_tests.sh

# Deploy updates
cd deployment && ./deploy_idempotent.sh --dry-run

# Rollback
cd deployment && ./rollback.sh

# Rotate logs
source deployment/logging_config.sh && rotate_logs
```

### Log Locations

```
Application Logs: /var/log/eros/application/
Deployment Logs:  /var/log/eros/deployment/
Audit Logs:       /var/log/eros/audit/
Performance Logs: /var/log/eros/performance/
```

### Important URLs

- GCP Console: https://console.cloud.google.com/
- BigQuery Console: https://console.cloud.google.com/bigquery
- Cloud Logging: https://console.cloud.google.com/logs
- Cloud Monitoring: https://console.cloud.google.com/monitoring
- Status Page: https://status.cloud.google.com/

---

**Document History:**

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2025-10-31 | 1.0 | DevOps Team | Initial creation |

**Review Schedule:** Quarterly (Jan, Apr, Jul, Oct)
