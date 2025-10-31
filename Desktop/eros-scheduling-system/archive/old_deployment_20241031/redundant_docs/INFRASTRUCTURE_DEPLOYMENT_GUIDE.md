# EROS Scheduling System - Production Infrastructure Deployment Guide

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Version:** 2.0.0 (Production-Ready)
**Date:** 2025-10-31

---

## Executive Summary

This guide provides step-by-step instructions for deploying the complete BigQuery infrastructure for the EROS Scheduling System. The infrastructure includes 4 UDFs, 3 core tables, 1 view, and 4 stored procedures, all optimized for production performance.

### Critical Requirements Met ✓

- ✅ All objects use fully-qualified names: `of-scheduler-proj.eros_scheduling_brain.*`
- ✅ All DDL uses `CREATE OR REPLACE` (idempotent, safe to re-run)
- ✅ NO session settings (`@@query_timeout_ms`, `@@maximum_bytes_billed`)
- ✅ All timezone operations use `America/Los_Angeles`
- ✅ `SAFE_DIVIDE` used throughout to prevent division errors
- ✅ All tables partitioned and clustered for optimal query performance

---

## Infrastructure Components

### 1. User-Defined Functions (UDFs) - 4 Total

| UDF Name | Purpose | Performance | Dependencies |
|----------|---------|-------------|--------------|
| `caption_key_v2` | Generate SHA256 hash from message text | < 1ms | None |
| `caption_key` | Backward compatibility wrapper | < 1ms | caption_key_v2 |
| `wilson_score_bounds` | Calculate 95% confidence intervals | < 1ms | None |
| `wilson_sample` | Thompson sampling for bandits | < 1ms | wilson_score_bounds |

### 2. Core Tables - 3 Total

| Table Name | Purpose | Partitioning | Clustering | Update Frequency |
|------------|---------|--------------|------------|------------------|
| `caption_bandit_stats` | Caption performance tracking | `DATE(last_updated)` | `page_name, caption_id, last_used` | Every 6 hours |
| `holiday_calendar` | US holiday tracking | `YEAR(holiday_date)` | None | Annual |
| `schedule_export_log` | Telemetry tracking | `DATE(export_timestamp)` | `page_name, status` | Real-time |

### 3. Views - 1 Total

| View Name | Purpose | Dependencies | Performance |
|-----------|---------|--------------|-------------|
| `schedule_recommendations_messages` | Schedule export view | `schedule_recommendations`, `caption_bank`, `captions`, `caption_bandit_stats` | < 1s per schedule |

### 4. Stored Procedures - 4 Total

| Procedure Name | Purpose | Schedule | Execution Time |
|----------------|---------|----------|----------------|
| `update_caption_performance` | Update caption metrics | Every 6 hours | ~30s for 100K msgs |
| `run_daily_automation` | Daily orchestration | Daily at 03:05 LA | ~30s per 100 creators |
| `sweep_expired_caption_locks` | Lock cleanup | Hourly | ~5s for 10K locks |
| `select_captions_for_creator` | Caption selection | On-demand | ~500ms per creator |

---

## Pre-Deployment Checklist

### System Requirements

- [ ] BigQuery project: `of-scheduler-proj` exists
- [ ] Dataset: `eros_scheduling_brain` exists
- [ ] Permissions: `BigQuery Data Editor` role or higher
- [ ] Network: Access to BigQuery API
- [ ] CLI: `bq` command-line tool installed (optional)

### Dependency Tables (Must Exist Before Deployment)

The following tables are referenced but NOT created by the infrastructure script:

- [ ] `mass_messages` - Source data for caption performance
- [ ] `caption_bank` - Caption library with enriched metadata
- [ ] `caption_bank_enriched` - Extended caption metadata (for TVFs)
- [ ] `captions` - Fallback caption source
- [ ] `schedule_recommendations` - Generated schedule data
- [ ] `active_caption_assignments` - Current caption locks
- [ ] `available_captions` - Caption pool view
- [ ] `active_creator_caption_restrictions_v` - Restriction view
- [ ] `creator_content_inventory` - Content category tracking

**Action Required:** Verify these tables exist before deploying infrastructure.

---

## Deployment Instructions

### Step 1: Deploy Core Infrastructure

**File:** `PRODUCTION_INFRASTRUCTURE.sql`

#### Option A: BigQuery Console (Recommended for First-Time Deployment)

1. Open BigQuery Console: https://console.cloud.google.com/bigquery
2. Select project: `of-scheduler-proj`
3. Open query editor
4. Copy entire contents of `PRODUCTION_INFRASTRUCTURE.sql`
5. Click **RUN**
6. Wait for completion (~30-60 seconds)
7. Verify no errors in query results

#### Option B: Command Line

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment

bq query \
  --project_id=of-scheduler-proj \
  --use_legacy_sql=false \
  --max_rows=0 \
  < PRODUCTION_INFRASTRUCTURE.sql
```

#### Expected Output

```
Query complete (30.2 sec elapsed, 0 B processed)
```

### Step 2: Verify Deployment

**File:** `verify_production_infrastructure.sql`

Run the comprehensive verification suite:

```bash
bq query \
  --project_id=of-scheduler-proj \
  --use_legacy_sql=false \
  < verify_production_infrastructure.sql
```

#### Expected Results

All tests should return `PASS ✓`:

- **Test Suite 1:** Object Existence (4 tests)
- **Test Suite 2:** UDF Functionality (4 tests)
- **Test Suite 3:** Table Schema (4 tests)
- **Test Suite 4:** View Functionality (1 test)
- **Test Suite 5:** Procedure Signatures (4 tests)
- **Test Suite 6:** Data Integrity (2 tests)
- **Test Suite 7:** Timezone Consistency (1 test)
- **Test Suite 8:** Performance Baseline (1 test)

**Total:** 21 tests across 8 categories

### Step 3: Deploy Performance Analyzer (Optional)

**File:** `CORRECTED_analyze_creator_performance_FULL.sql`

This file contains 7 Table-Valued Functions (TVFs) and the main analysis procedure:

```bash
bq query \
  --project_id=of-scheduler-proj \
  --use_legacy_sql=false \
  --max_rows=0 \
  < CORRECTED_analyze_creator_performance_FULL.sql
```

### Step 4: Configure Scheduled Queries

#### 4.1 update_caption_performance - Every 6 Hours

```sql
-- Schedule: Every 6 hours (0:00, 6:00, 12:00, 18:00 America/Los_Angeles)
-- Timeout: 10 minutes
-- Destination: None (updates table in-place)

CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
```

#### 4.2 run_daily_automation - Daily at 03:05 AM

```sql
-- Schedule: Every day at 03:05 America/Los_Angeles
-- Timeout: 30 minutes
-- Destination: None (updates multiple tables)

CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  CURRENT_DATE('America/Los_Angeles')
);
```

#### 4.3 sweep_expired_caption_locks - Every Hour

```sql
-- Schedule: Every 1 hour
-- Timeout: 5 minutes
-- Destination: None (updates table in-place)

CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
```

---

## Post-Deployment Validation

### Manual Testing

#### Test 1: UDF Execution

```sql
-- Test caption_key_v2
SELECT `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`('Test message 123');
-- Expected: 64-character hex string

-- Test wilson_score_bounds
SELECT `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50);
-- Expected: STRUCT with lower_bound, upper_bound, exploration_bonus

-- Test wilson_sample
SELECT `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50);
-- Expected: Random float between 0 and 1
```

#### Test 2: Table Queries

```sql
-- Check caption_bandit_stats schema
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` LIMIT 10;

-- Check holiday_calendar data
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
WHERE EXTRACT(YEAR FROM holiday_date) = 2025
ORDER BY holiday_date;
-- Expected: 20+ holidays for 2025

-- Check schedule_export_log (should be empty initially)
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`;
-- Expected: 0 (no exports yet)
```

#### Test 3: View Access

```sql
-- Verify view structure (may return 0 rows if no schedules exist)
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
LIMIT 10;
```

#### Test 4: Procedure Dry Run (Requires Production Data)

```sql
-- Test select_captions_for_creator (requires caption_bank, available_captions)
-- Replace 'test_creator' with actual page_name from your data
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'test_creator',           -- normalized_page_name
  'Standard',               -- behavioral_segment
  5,                        -- num_budget_needed
  5,                        -- num_mid_needed
  3,                        -- num_premium_needed
  2                         -- num_bump_needed
);
```

---

## Monitoring & Observability

### Key Monitoring Tables

#### 1. ETL Job Runs Log

```sql
-- Check recent automation jobs
SELECT
  job_id,
  job_name,
  job_status,
  execution_date,
  creators_processed,
  creators_failed,
  job_duration_seconds,
  error_message
FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY job_start_time DESC
LIMIT 100;
```

#### 2. Automation Alerts

```sql
-- Check for critical alerts
SELECT
  alert_time,
  alert_level,
  alert_source,
  alert_message,
  acknowledged
FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
WHERE alert_level = 'CRITICAL'
  AND acknowledged = FALSE
ORDER BY alert_time DESC
LIMIT 50;
```

#### 3. Lock Sweep Log

```sql
-- Monitor lock cleanup operations
SELECT
  sweep_time,
  total_locks_cleaned,
  locks_expired_stale,
  locks_expired_past_date,
  sweep_duration_seconds
FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
WHERE sweep_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY sweep_time DESC;
```

### Performance Metrics

#### Caption Selection Performance

```sql
-- Monitor caption selection execution times
SELECT
  page_name,
  COUNT(*) AS selections,
  AVG(execution_time_seconds) AS avg_execution_time,
  MAX(execution_time_seconds) AS max_execution_time,
  COUNTIF(status = 'SUCCESS') AS successful,
  COUNTIF(status = 'FAILED') AS failed
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY page_name
ORDER BY selections DESC
LIMIT 50;
```

#### Table Growth Monitoring

```sql
-- Monitor caption_bandit_stats growth
SELECT
  DATE(last_updated) AS update_date,
  COUNT(*) AS caption_count,
  COUNT(DISTINCT page_name) AS creator_count,
  AVG(total_observations) AS avg_observations,
  AVG(avg_emv) AS avg_emv_across_captions
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY update_date
ORDER BY update_date DESC;
```

---

## Troubleshooting

### Common Issues

#### Issue 1: "Table not found" errors

**Symptom:** Queries fail with "Table of-scheduler-proj.eros_scheduling_brain.XXX not found"

**Cause:** Dependency tables don't exist

**Solution:**
1. Check "Pre-Deployment Checklist" section above
2. Ensure all dependency tables exist
3. Verify table names match exactly (case-sensitive)

#### Issue 2: UDF fails with division by zero

**Symptom:** UDF execution returns error or NULL

**Cause:** Not using `SAFE_DIVIDE` wrapper

**Solution:** All division operations in infrastructure use `SAFE_DIVIDE` - if error persists, check input data validity

#### Issue 3: Procedure fails with "Circuit breaker triggered"

**Symptom:** `run_daily_automation` stops after processing few creators

**Cause:** Multiple creator processing failures

**Solution:**
1. Query `creator_processing_errors` table for error details
2. Fix underlying data issues
3. Re-run automation procedure

```sql
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
WHERE error_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY error_time DESC;
```

#### Issue 4: Holiday calendar not seeded

**Symptom:** `holiday_calendar` table empty or missing 2025 holidays

**Solution:** Re-run infrastructure deployment - `MERGE` statement is idempotent

```sql
-- Verify holiday count
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`
WHERE EXTRACT(YEAR FROM holiday_date) = 2025;
-- Expected: 20+ rows
```

#### Issue 5: Timezone inconsistencies

**Symptom:** Dates/times don't match expected America/Los_Angeles timezone

**Cause:** Query not using timezone parameter

**Solution:** Always use `CURRENT_DATE('America/Los_Angeles')` and `DATETIME(timestamp, 'America/Los_Angeles')`

---

## Rollback Procedures

### Full Rollback (Remove All Infrastructure)

**WARNING:** This will delete ALL infrastructure objects. Use only in emergency.

```sql
-- Drop all procedures
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`;

-- Drop view
DROP VIEW IF EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`;

-- Drop tables (WARNING: This deletes data)
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.holiday_calendar`;
DROP TABLE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`;

-- Drop UDFs
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.wilson_sample`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_key`;
DROP FUNCTION IF EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`;
```

### Partial Rollback (Procedures Only)

```sql
-- Drop only procedures (preserves data)
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`;
DROP PROCEDURE IF EXISTS `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`;
```

---

## Performance Optimization

### Query Performance Benchmarks

| Operation | Expected Time | Optimization |
|-----------|---------------|--------------|
| UDF execution (single call) | < 1ms | Pre-compute where possible |
| Caption selection (200 captions) | ~500ms | Filter pool early, use indexes |
| Performance update (100K messages) | ~30s | Partition pruning, temp tables |
| Daily automation (100 creators) | ~30s | Parallel processing where possible |
| Lock sweep (10K locks) | ~5s | Batch updates, partition pruning |

### Storage Optimization

#### Partition Pruning

Always filter on partitioning columns to reduce scan size:

```sql
-- GOOD: Uses partition pruning
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE DATE(last_updated) >= '2025-10-01';

-- BAD: Full table scan
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE last_updated >= '2025-10-01 00:00:00';
```

#### Clustering Benefits

Filter on clustering columns for optimal performance:

```sql
-- OPTIMAL: Uses both partition and clustering
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE DATE(last_updated) >= '2025-10-01'
  AND page_name = 'specific_creator'
  AND caption_id IN (1, 2, 3);
```

---

## Maintenance Schedule

### Daily Tasks

- [ ] Review `automation_alerts` for CRITICAL alerts
- [ ] Check `etl_job_runs` for failed jobs
- [ ] Verify scheduled queries are running

### Weekly Tasks

- [ ] Review `caption_bandit_stats` growth trends
- [ ] Check `lock_sweep_log` for unusual cleanup volumes
- [ ] Analyze `schedule_export_log` success rates

### Monthly Tasks

- [ ] Update `holiday_calendar` for upcoming months
- [ ] Review and optimize slow queries
- [ ] Archive old data from telemetry tables (> 90 days)

### Annual Tasks

- [ ] Seed next year's holidays in `holiday_calendar`
- [ ] Review partitioning strategy for growing tables
- [ ] Performance audit of all procedures

---

## Cost Optimization

### Query Cost Estimates

| Query Type | Avg Data Scanned | Est. Cost (per run) |
|------------|------------------|---------------------|
| UDF execution | < 1 MB | $0.000005 |
| Caption selection | 10-50 MB | $0.00025 |
| Performance update | 1-5 GB | $0.025 |
| Daily automation | 500 MB - 2 GB | $0.01 |

### Cost Reduction Strategies

1. **Use Partition Pruning:** Always filter on `DATE()` columns
2. **Limit Result Sets:** Use `LIMIT` in development/testing
3. **Batch Operations:** Combine multiple small queries
4. **Cache Results:** Materialize frequently-accessed aggregations
5. **Monitor Slot Usage:** Review BigQuery job metrics

---

## Security Considerations

### Access Control

Recommended IAM roles:

- **Production:** `BigQuery Data Viewer` (read-only)
- **ETL Services:** `BigQuery Data Editor` (read/write)
- **Developers:** `BigQuery User` + dataset-level permissions
- **Admins:** `BigQuery Admin` (full access)

### Data Privacy

- Caption text may contain PII - review before exporting
- `mass_messages` contains revenue data - restrict access
- `schedule_export_log` tracks user activity - GDPR compliance

### Audit Logging

Enable BigQuery audit logs to track:

- Procedure executions
- Data modifications
- Access patterns
- Failed queries

---

## Support & Escalation

### Documentation

- **Infrastructure SQL:** `/deployment/PRODUCTION_INFRASTRUCTURE.sql`
- **Verification Suite:** `/deployment/verify_production_infrastructure.sql`
- **This Guide:** `/deployment/INFRASTRUCTURE_DEPLOYMENT_GUIDE.md`

### Escalation Path

1. **Tier 1:** Check this deployment guide
2. **Tier 2:** Review BigQuery job logs and error messages
3. **Tier 3:** Contact SQL developer team with:
   - Error messages (full text)
   - Query plan (if applicable)
   - Sample data (anonymized)
   - Steps to reproduce

---

## Appendix

### A. Object Naming Conventions

- **Tables:** snake_case, descriptive nouns
- **Views:** snake_case, suffix with context (e.g., `_messages`)
- **Procedures:** snake_case, verb-first (e.g., `update_`, `run_`)
- **UDFs:** snake_case, descriptive function names
- **Columns:** snake_case, clear data types implied

### B. Timezone Reference

All date/time operations use **America/Los_Angeles (Pacific Time)**:

- **PST (Winter):** UTC-8
- **PDT (Summer):** UTC-7
- **Daylight Saving:** 2nd Sunday in March - 1st Sunday in November

### C. Partition Retention

| Table | Partition Column | Retention | Reason |
|-------|------------------|-----------|--------|
| `caption_bandit_stats` | `DATE(last_updated)` | 90 days | Performance metrics decay |
| `holiday_calendar` | `YEAR(holiday_date)` | 6 years | Future planning |
| `schedule_export_log` | `DATE(export_timestamp)` | 90 days | Telemetry analysis |
| `etl_job_runs` | `DATE(job_start_time)` | 90 days | Operational debugging |
| `lock_sweep_log` | `DATE(sweep_time)` | 30 days | Short-term monitoring |

---

## Deployment Sign-Off

**Deployed By:** _____________________
**Date:** _____________________
**Version:** 2.0.0
**Environment:** Production

**Verification Status:**
- [ ] All 21 validation tests passed
- [ ] Scheduled queries configured
- [ ] Monitoring dashboards created
- [ ] Team trained on procedures
- [ ] Rollback plan reviewed

**Approvals:**
- [ ] SQL Developer: _____________________
- [ ] Data Engineer: _____________________
- [ ] Tech Lead: _____________________

---

**Document Version:** 2.0.0
**Last Updated:** 2025-10-31
**Next Review:** 2026-01-31
