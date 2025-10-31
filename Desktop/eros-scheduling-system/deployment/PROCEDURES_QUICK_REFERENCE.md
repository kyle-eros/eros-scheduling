# Stored Procedures Quick Reference

## At-a-Glance Summary

Two BigQuery stored procedures for the caption-selector system:

| Procedure | Purpose | Frequency | Duration | When to Call |
|-----------|---------|-----------|----------|--------------|
| `update_caption_performance` | Update caption bandit stats from message history | Every 6h | 5-30s | After campaigns, before selection |
| `lock_caption_assignments` | Atomically assign captions to schedule | On-demand | <100ms | When scheduling captions |

---

## Quick Deployment (5 minutes)

```bash
# 1. Validate all dependencies exist
./validate_procedures.sh

# 2. Deploy procedures
bq query --use_legacy_sql=false < stored_procedures.sql

# 3. Verify they exist
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | \
  grep -E "update_caption_performance|lock_caption_assignments"
```

---

## Usage Examples

### Update Caption Performance
```sql
-- Execute procedure
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- Check results
SELECT page_name, COUNT(*) as captions, SUM(total_revenue) as revenue
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY page_name;
```

### Lock Caption Assignments
```sql
-- Define assignments
DECLARE assignments ARRAY<STRUCT<
  caption_id INT64,
  scheduled_send_date DATE,
  scheduled_send_hour INT64
>> DEFAULT [
  STRUCT(1, DATE('2025-11-02'), 14),
  STRUCT(2, DATE('2025-11-03'), 15)
];

-- Execute procedure
CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
  'schedule_20251101',
  'creator_name',
  assignments
);

-- Check results
SELECT caption_id, scheduled_send_date, assignment_key
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE schedule_id = 'schedule_20251101';
```

---

## Common Tasks

### Check Procedure Status
```bash
bq show --routine of-scheduler-proj:eros_scheduling_brain.update_caption_performance
bq show --routine of-scheduler-proj:eros_scheduling_brain.lock_caption_assignments
```

### Run Tests
```bash
# Full test suite
bq query --use_legacy_sql=false < test_procedures.sql

# Just dependency checks
./validate_procedures.sh
```

### Disable Procedures (if needed)
```sql
-- Disable without data loss
ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`
  RENAME TO update_caption_performance_disabled;
```

### Re-enable Procedures
```sql
ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance_disabled`
  RENAME TO update_caption_performance;
```

### Delete Procedures Completely
```sql
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`;
```

---

## Troubleshooting

### Procedure Not Found
```bash
# Check it exists
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | \
  grep update_caption_performance

# If missing, redeploy
bq query --use_legacy_sql=false < stored_procedures.sql
```

### Procedure Errors
```bash
# Check recent queries for errors
bq ls --project_id=of-scheduler-proj --max_results=20 -j | head -20

# See detailed error
bq show -j [JOB_ID]
```

### Data Not Updating
```sql
-- Check if data exists in source tables
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE caption_id IS NOT NULL AND viewed_count > 0
  AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);

-- Check if caption_bandit_stats is getting updated
SELECT MAX(last_updated) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
```

### Assignments Being Blocked
```sql
-- Check conflict rate
SELECT
  COUNT(*) as attempted,
  COUNT(DISTINCT schedule_id) as schedules,
  COUNTIF(assigned_at IS NOT NULL) as assigned
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE assigned_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR);

-- See detailed conflicts by page
SELECT
  page_name,
  caption_id,
  COUNT(*) as assignments_in_range,
  MIN(scheduled_send_date) as earliest,
  MAX(scheduled_send_date) as latest
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE is_active = TRUE
GROUP BY page_name, caption_id
ORDER BY assignments_in_range DESC;
```

---

## Monitoring Commands

### Check Update Frequency
```bash
# See how often update_caption_performance is being run
bq ls --project_id=of-scheduler-proj --max_results=100 -j | \
  grep "update_caption_performance" | head -10
```

### Monitor Execution Time
```sql
-- Check last 10 runs' execution time patterns
SELECT
  job_id,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, SECOND) as age_seconds,
  statement_type
FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE user_email IS NOT NULL
  AND statement_text LIKE '%update_caption_performance%'
ORDER BY creation_time DESC
LIMIT 10;
```

### Check Table Sizes
```sql
SELECT
  'caption_bandit_stats' as table_name,
  COUNT(*) as row_count,
  COUNT(DISTINCT page_name) as pages,
  COUNT(DISTINCT caption_id) as captions,
  SUM(total_revenue) as total_revenue
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
```

---

## Key Points to Remember

1. **Both procedures are idempotent** - Safe to retry or run multiple times
2. **update_caption_performance** needs data with caption_id and viewed_count > 0
3. **lock_caption_assignments** prevents same caption within ±7 days
4. **All timestamps in America/Los_Angeles timezone**
5. **SHA256 idempotency keys** prevent duplicate assignments
6. **Wilson score bounds** enable Thompson sampling for caption selection

---

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| Procedures | `/deployment/stored_procedures.sql` | CREATE OR REPLACE |
| Guide | `/deployment/PROCEDURES_DEPLOYMENT_GUIDE.md` | Full documentation |
| Tests | `/deployment/test_procedures.sql` | 50+ test cases |
| Validation | `/deployment/validate_procedures.sh` | Pre-deploy checks |
| Checklist | `/deployment/PROCEDURES_DEPLOYMENT_CHECKLIST.md` | Step-by-step checklist |
| Report | `/STORED_PROCEDURES_IMPLEMENTATION_REPORT.md` | Complete specifications |

---

## Quick Links

- **Full Guide**: See PROCEDURES_DEPLOYMENT_GUIDE.md
- **Tests**: Run `bq query --use_legacy_sql=false < test_procedures.sql`
- **Validation**: Run `./validate_procedures.sh`
- **Schema**: See SCHEMA_ALIGNMENT_QUICK_REFERENCE.md
- **Help**: See PROCEDURES_DEPLOYMENT_GUIDE.md "Troubleshooting" section

---

## Emergency Procedures

### Rollback (if issues)
```sql
-- Option 1: Rename to disable (data safe)
ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`
  RENAME TO update_caption_performance_disabled;

-- Option 2: Delete (if needed)
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;

-- Option 3: Restore from git
git show COMMIT_HASH:deployment/stored_procedures.sql | bq query --use_legacy_sql=false
```

### Verify Rollback
```bash
bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | \
  grep update_caption_performance
```

---

**Last Updated**: October 31, 2025
**Status**: READY FOR PRODUCTION

For detailed information, see the full documentation in the deployment directory.

