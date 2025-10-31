# Stored Procedures Deployment Checklist

## Pre-Deployment Verification

- [ ] BigQuery project access confirmed: `of-scheduler-proj`
- [ ] Dataset exists: `eros_scheduling_brain`
- [ ] IAM permissions verified:
  - [ ] bigquery.routines.create
  - [ ] bigquery.routines.delete
  - [ ] bigquery.tables.update
  - [ ] bigquery.tables.get
- [ ] gcloud CLI installed and authenticated
- [ ] bq CLI available and working
- [ ] Have backup of current procedures (if any)

## Dependency Verification

### UDFs Required
- [ ] `wilson_score_bounds` function exists
  ```bash
  bq show --routine of-scheduler-proj:eros_scheduling_brain.wilson_score_bounds
  ```
- [ ] `wilson_sample` function exists
  ```bash
  bq show --routine of-scheduler-proj:eros_scheduling_brain.wilson_sample
  ```

### Tables Required
- [ ] `caption_bandit_stats` table exists
  ```bash
  bq show of-scheduler-proj:eros_scheduling_brain.caption_bandit_stats
  ```
- [ ] `mass_messages` table exists with `caption_id` column
  ```bash
  bq show --schema of-scheduler-proj:eros_scheduling_brain.mass_messages | grep caption_id
  ```
- [ ] `active_caption_assignments` table exists
  ```bash
  bq show of-scheduler-proj:eros_scheduling_brain.active_caption_assignments
  ```
- [ ] `caption_bank` table exists
  ```bash
  bq show of-scheduler-proj:eros_scheduling_brain.caption_bank
  ```

## Pre-Deployment Data Validation

- [ ] At least 1 message with `caption_id` in `mass_messages`
  ```sql
  SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE caption_id IS NOT NULL LIMIT 1;
  ```
- [ ] At least 1 message with `viewed_count > 0`
  ```sql
  SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE viewed_count > 0 LIMIT 1;
  ```
- [ ] At least 1 caption in `caption_bank`
  ```sql
  SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` LIMIT 1;
  ```
- [ ] `active_caption_assignments` table is empty or has manageable size

## Deployment Steps

### Step 1: Run Validation Script
- [ ] Execute: `./validate_procedures.sh`
- [ ] All checks passed?
  - [ ] UDFs verified
  - [ ] Tables verified
  - [ ] Schema compatibility confirmed
  - [ ] caption_id availability confirmed

### Step 2: Deploy Procedures
- [ ] Option A: Deploy via BigQuery Web UI
  - [ ] Navigate to `of-scheduler-proj.eros_scheduling_brain`
  - [ ] Click "Create Procedure"
  - [ ] Paste contents of `stored_procedures.sql`
  - [ ] Review and execute

- [ ] Option B: Deploy via bq CLI
  ```bash
  bq query \
    --use_legacy_sql=false \
    --location=US \
    < /Users/kylemerriman/Desktop/eros-scheduling-system/deployment/stored_procedures.sql
  ```

### Step 3: Verify Compilation
- [ ] Both procedures created successfully
  ```bash
  bq ls --routines --project_id=of-scheduler-proj eros_scheduling_brain | \
    grep -E "update_caption_performance|lock_caption_assignments"
  ```
- [ ] Expected output:
  ```
  update_caption_performance    PROCEDURE
  lock_caption_assignments      PROCEDURE
  ```

## Testing Phase

### Test 1: Test `update_caption_performance`
- [ ] Run test queries from `test_procedures.sql` (Section 4 & 5)
- [ ] Verify data exists for testing
- [ ] Execute procedure:
  ```sql
  CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
  ```
- [ ] Check results:
  ```sql
  SELECT page_name, COUNT(*) as captions
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  GROUP BY page_name;
  ```
- [ ] Expected: At least 1 row per page with captions

### Test 2: Test `lock_caption_assignments`
- [ ] Prepare test data:
  ```sql
  DECLARE test_schedule_id STRING DEFAULT 'test_' || FORMAT_TIMESTAMP('%Y%m%d_%H%M%S', CURRENT_TIMESTAMP());
  DECLARE test_page_name STRING DEFAULT 'test_page';
  DECLARE test_assignments ARRAY<STRUCT<
    caption_id INT64,
    scheduled_send_date DATE,
    scheduled_send_hour INT64
  >> DEFAULT [
    STRUCT(
      (SELECT caption_id FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` LIMIT 1),
      DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY),
      14
    )
  ];
  ```
- [ ] Execute procedure:
  ```sql
  CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
    test_schedule_id, test_page_name, test_assignments
  );
  ```
- [ ] Verify results:
  ```sql
  SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE schedule_id = test_schedule_id;
  ```
- [ ] Expected: At least 1 assignment created

### Test 3: Run Full Test Suite
- [ ] Execute all tests from `test_procedures.sql`
- [ ] Verify PASS status for:
  - [ ] Syntax validation tests (Section 1)
  - [ ] Dependency validation tests (Section 2)
  - [ ] UDF functionality tests (Section 3)
  - [ ] Data availability tests (Section 4)
  - [ ] Procedure behavior tests (Section 5)
  - [ ] Integration validation tests (Section 6)

## Post-Deployment Monitoring

### Immediate Checks (First Hour)
- [ ] Check BigQuery operation logs for errors
  ```bash
  gcloud logging read "resource.type=bigquery_resource" \
    --limit=50 --format=json | jq '.[] | select(.severity=="ERROR")'
  ```
- [ ] Verify no unexpected errors in application logs
- [ ] Monitor query execution times (should be <60 seconds)

### First 24 Hours
- [ ] Set up Cloud Monitoring alerts:
  - [ ] Procedure execution failures
  - [ ] Abnormal execution times
  - [ ] High cost queries
- [ ] Review caption_bandit_stats updates
  - [ ] New captions discovered
  - [ ] Confidence bounds calculated
  - [ ] Performance percentiles assigned
- [ ] Review active_caption_assignments updates
  - [ ] No unexpected blocking rate
  - [ ] Schedule IDs tracked correctly

### Ongoing Monitoring
- [ ] Create scheduled queries for periodic execution:
  ```bash
  # Run update_caption_performance every 6 hours
  bq query --use_legacy_sql=false \
    "CALL \`of-scheduler-proj.eros_scheduling_brain.update_caption_performance\`();"
  ```
- [ ] Set up Cloud Monitoring dashboard
- [ ] Review performance metrics weekly

## Rollback Plan

If issues arise, follow this sequence:

### Option 1: Disable Without Data Loss (Recommended)
```sql
-- Rename procedures to disable them
ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`
  RENAME TO update_caption_performance_disabled;

ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`
  RENAME TO lock_caption_assignments_disabled;
```

### Option 2: Full Removal
```sql
-- Drop procedures
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`;

-- Keep UDFs and tables intact for re-deployment
```

### Option 3: Restore from Backup
1. Identify previous working version in git history
2. Deploy that version:
   ```bash
   git show PREVIOUS_COMMIT:deployment/stored_procedures.sql | \
     bq query --use_legacy_sql=false
   ```

## Success Criteria

Deployment is successful when ALL of the following are true:

- [ ] Both procedures created without compilation errors
- [ ] All dependency UDFs and tables verified
- [ ] `update_caption_performance` executes and populates `caption_bandit_stats`
- [ ] `lock_caption_assignments` executes and creates assignments
- [ ] Test suite runs with all PASS status
- [ ] No error logs in BigQuery operation history
- [ ] Query performance within expected bounds (<60 seconds)
- [ ] Application code successfully calls procedures
- [ ] Monitoring and alerting configured

## Documentation Checklist

- [ ] PROCEDURES_DEPLOYMENT_GUIDE.md reviewed
- [ ] test_procedures.sql reviewed and understood
- [ ] Schema alignment verified in SCHEMA_ALIGNMENT_QUICK_REFERENCE.md
- [ ] Team trained on procedure usage
- [ ] Runbook created for emergency procedures
- [ ] Disaster recovery plan documented

## Sign-Off

- [ ] DBA reviewed and approved
- [ ] QA testing completed
- [ ] Operations team briefed
- [ ] Monitoring configured
- [ ] Rollback plan documented

**Deployment Date**: _______________

**Deployed By**: _______________

**Verified By**: _______________

**Notes**:

