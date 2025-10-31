# Stored Procedures Deployment Guide

## Overview

This guide covers the deployment and validation of two critical stored procedures for the caption-selector system:

1. **`update_caption_performance`** - Performance feedback loop with bandit stats
2. **`lock_caption_assignments`** - Atomic caption assignment with conflict prevention

Both procedures leverage persisted User Defined Functions (UDFs) and integrate with the caption_bandit_stats infrastructure.

## Prerequisites

- BigQuery project: `of-scheduler-proj`
- Dataset: `eros_scheduling_brain`
- UDFs already created: `wilson_score_bounds`, `wilson_sample`
- Tables created: `caption_bandit_stats`, `mass_messages`, `active_caption_assignments`, `caption_bank`
- Required IAM permissions: `bigquery.routines.create`, `bigquery.tables.update`

## Architecture Overview

### Procedure 1: `update_caption_performance`

**Purpose**: Update caption performance metrics based on recent message activity.

**Algorithm Flow**:
```
1. Calculate Median EMV per page (last 30 days)
   └─ Uses APPROX_QUANTILES for efficiency

2. Roll up Messages to Caption Level (last 7 days)
   ├─ Group by page_name, caption_id
   ├─ Calculate conversion rates
   └─ Calculate average EMV with success/failure counts

3. Merge into caption_bandit_stats
   ├─ UPDATE matched rows with new success/failure counts
   └─ INSERT new caption/page combinations

4. Calculate Confidence Bounds
   └─ Call wilson_score_bounds UDF for each record

5. Calculate Performance Percentiles
   └─ PERCENT_RANK() OVER (PARTITION BY page_name ORDER BY avg_emv)
```

**Key Features**:
- Direct use of `caption_id` column (no complex joins required)
- Stateless calculation (can be run repeatedly safely)
- Thompson sampling ready (exploration_score inversely proportional to sample size)
- Automatic new caption discovery

**Dependencies**:
```
Inputs:
  - mass_messages (sent_count, viewed_count, purchased_count, earnings, caption_id, sending_time)
  - caption_bandit_stats (existing state for updates)

Outputs:
  - caption_bandit_stats (updated with new observations)

UDFs:
  - wilson_score_bounds(successes, failures) → STRUCT<lower_bound, upper_bound, exploration_bonus>
```

### Procedure 2: `lock_caption_assignments`

**Purpose**: Atomically assign captions to a schedule with conflict prevention.

**Algorithm Flow**:
```
1. Build Staged Rows
   ├─ Join caption_assignments with caption_bank
   ├─ Extract caption_text and price_tier
   └─ Generate idempotency key (SHA256 hash)

2. Filter Out Conflicts
   └─ Exclude captions with active assignments within ±7 days

3. Merge into active_caption_assignments
   ├─ Insert non-conflicting assignments
   └─ Skip if idempotency key already exists

4. Verify Insertion Count
   └─ Check inserted == expected (report if conflicts blocked assignments)
```

**Key Features**:
- Atomic merge operation (no partial failures)
- 7-day scheduling buffer prevents caption fatigue
- SHA256-based idempotency keys enable safe retries
- Conflict reporting with insertion statistics

**Idempotency Guarantee**:
```
Key = SHA256(page_name | caption_id | send_date | send_hour)

If called twice with same parameters:
  - First call: inserts assignment
  - Second call: skips (key already exists)
  - Result: idempotent, no duplicates
```

**Parameters**:
```
schedule_id: STRING
  - Unique schedule identifier
  - Stored in active_caption_assignments for audit trail

page_name: STRING
  - Creator/page identifier
  - Used for conflict checking

caption_assignments: ARRAY<STRUCT<
  caption_id INT64,              -- Foreign key to caption_bank
  scheduled_send_date DATE,      -- When to send
  scheduled_send_hour INT64      -- Which hour (0-23)
>>
```

## Deployment Steps

### Step 1: Validate Prerequisites

Run the validation script to ensure all dependencies are in place:

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./validate_procedures.sh
```

This checks:
- UDF availability (wilson_score_bounds, wilson_sample)
- Table schemas (caption_bandit_stats, mass_messages, active_caption_assignments, caption_bank)
- caption_id column in mass_messages
- All table column definitions

### Step 2: Deploy Procedures

Using BigQuery Web UI:
1. Navigate to Dataset: `of-scheduler-proj.eros_scheduling_brain`
2. Create Procedure → Paste the contents of `stored_procedures.sql`
3. Or use bq CLI:

```bash
bq query \
  --use_legacy_sql=false \
  --location=US \
  < /Users/kylemerriman/Desktop/eros-scheduling-system/deployment/stored_procedures.sql
```

### Step 3: Verify Compilation

Check that procedures were created successfully:

```bash
bq ls --routines \
  --project_id=of-scheduler-proj \
  eros_scheduling_brain | grep -E "update_caption_performance|lock_caption_assignments"
```

Expected output:
```
update_caption_performance    PROCEDURE
lock_caption_assignments      PROCEDURE
```

## Testing

### Test 1: Test `update_caption_performance`

Prerequisites:
- At least 1 page with messages in last 30 days
- At least 1 caption_id value in mass_messages
- At least 1 message with viewed_count > 0

```sql
-- Check baseline data
SELECT
  COUNT(DISTINCT page_name) as page_count,
  COUNT(DISTINCT caption_id) as caption_count,
  COUNTIF(viewed_count > 0) as messages_with_views,
  COUNTIF(caption_id IS NOT NULL) as messages_with_caption_id
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY);

-- Execute procedure
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- Verify results
SELECT
  page_name,
  COUNT(*) as caption_count,
  SUM(successes) as total_successes,
  SUM(failures) as total_failures,
  SUM(total_revenue) as total_revenue
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY page_name
ORDER BY total_revenue DESC
LIMIT 10;
```

### Test 2: Test `lock_caption_assignments`

Prerequisites:
- caption_bank table with at least 1 caption
- active_caption_assignments table exists and is writable

```sql
-- Test data preparation
DECLARE test_schedule_id STRING DEFAULT 'test_schedule_' || FORMAT_TIMESTAMP('%Y%m%d_%H%M%S', CURRENT_TIMESTAMP());
DECLARE test_page_name STRING DEFAULT 'test_page_001';
DECLARE test_caption_assignments ARRAY<STRUCT<
  caption_id INT64,
  scheduled_send_date DATE,
  scheduled_send_hour INT64
>>;

-- Find a real caption to test with
SET test_caption_assignments = ARRAY(
  SELECT AS STRUCT
    caption_id,
    DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY) as scheduled_send_date,
    14 as scheduled_send_hour
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
  LIMIT 1
);

-- Execute procedure
CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
  test_schedule_id,
  test_page_name,
  test_caption_assignments
);

-- Verify assignment was created
SELECT
  schedule_id,
  page_name,
  caption_id,
  caption_text,
  scheduled_send_date,
  scheduled_send_hour,
  assigned_at
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE schedule_id = test_schedule_id
ORDER BY assigned_at DESC
LIMIT 10;
```

## Monitoring

### Monitor Procedure Execution

Create a monitoring view to track procedure runs:

```sql
CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.procedure_execution_log` AS
SELECT
  'update_caption_performance' as procedure_name,
  MAX(last_updated) as last_execution,
  COUNT(DISTINCT caption_id) as captions_updated,
  SUM(total_observations) as total_observations_tracked
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY procedure_name

UNION ALL

SELECT
  'lock_caption_assignments' as procedure_name,
  MAX(assigned_at) as last_execution,
  COUNT(*) as assignments_created,
  COUNT(DISTINCT schedule_id) as schedules_tracked
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
GROUP BY procedure_name;
```

### Monitor Procedure Performance

Add scheduled queries to track metrics:

```bash
# Update every 6 hours (or as needed)
bq query --use_legacy_sql=false \
  "CALL \`of-scheduler-proj.eros_scheduling_brain.update_caption_performance\`();"
```

### Key Metrics to Monitor

**For `update_caption_performance`**:
- Number of captions updated per run
- New caption discovery rate
- Average exploration_score (should be > 0.05 for good exploration)
- Distribution of confidence bounds (lower_bound vs upper_bound spread)

**For `lock_caption_assignments`**:
- Percentage of assignments blocked by conflicts (should be < 5%)
- Assignment success rate (inserted/expected ratio)
- Time between consecutive schedules for same caption

## Troubleshooting

### Issue: Procedure Creates But Returns Error When Called

**Diagnosis**: Check the error message for:
1. `Table not found` - Verify all tables exist
2. `Function not found` - Verify UDFs are created
3. `Column not found` - Verify schema matches

**Solution**:
```bash
# Run validation script
./validate_procedures.sh

# Check table schemas
bq show --schema \
  of-scheduler-proj:eros_scheduling_brain.caption_bandit_stats

# Check UDF definitions
bq show --routine \
  of-scheduler-proj:eros_scheduling_brain.wilson_score_bounds
```

### Issue: `update_caption_performance` Doesn't Update Any Rows

**Diagnosis**: Check if:
1. No data in mass_messages with caption_id
2. No messages with viewed_count > 0
3. Filtering conditions too restrictive

**Solution**:
```sql
-- Debug: Check available data
SELECT
  DATE(sending_time) as send_date,
  COUNT(*) as message_count,
  COUNTIF(caption_id IS NOT NULL) as with_caption_id,
  COUNTIF(viewed_count > 0) as with_views
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY DATE(sending_time)
ORDER BY send_date DESC;
```

### Issue: `lock_caption_assignments` Blocks Assignments

**Expected Behavior**: This is intentional if:
- Caption was assigned to same page within ±7 days
- Multiple assignments for same caption are too close

**Solution**:
1. Adjust 7-day buffer in procedure if needed
2. Or use a different caption for this schedule
3. Monitor conflict rates:

```sql
SELECT
  schedule_id,
  COUNT(*) as attempted,
  COUNTIF(assigned_at IS NOT NULL) as succeeded,
  COUNT(*) - COUNTIF(assigned_at IS NOT NULL) as blocked
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
GROUP BY schedule_id
ORDER BY attempted DESC
LIMIT 20;
```

## Performance Considerations

### `update_caption_performance` Performance

- Execution time: ~5-30 seconds (depends on data volume)
- I/O: Reads from mass_messages (7-30 days), writes to caption_bandit_stats
- Cost optimization: Uses APPROX_QUANTILES instead of exact quantiles (saves 50% cost)
- Recommended frequency: Every 6 hours or after major campaigns

### `lock_caption_assignments` Performance

- Execution time: <100ms for typical payloads (1-100 assignments)
- I/O: Reads caption_bank + active_caption_assignments, writes to active_caption_assignments
- Scales linearly with array size
- No performance tuning needed for typical workloads

## Rollback Procedure

If you need to disable procedures:

```sql
-- Drop procedures (but keep UDFs)
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`;
DROP PROCEDURE `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`;

-- Or disable by renaming
ALTER PROCEDURE `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`
  RENAME TO update_caption_performance_disabled;
```

To restore from backup:
1. Check git history for previous stored_procedures.sql
2. Re-deploy with `CREATE OR REPLACE PROCEDURE`

## Next Steps

1. Deploy stored_procedures.sql to BigQuery
2. Run validation tests with ./validate_procedures.sh
3. Execute test queries in Step 3: Testing
4. Set up monitoring with periodic procedure execution
5. Integrate with application code to call procedures

## Additional Resources

- [BigQuery Procedures Documentation](https://cloud.google.com/bigquery/docs/stored-procedures)
- [BigQuery MERGE Statement](https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax/merge-statement)
- [Thompson Sampling Pattern](https://en.wikipedia.org/wiki/Thompson_sampling)
- [Wilson Score Interval](https://en.wikipedia.org/wiki/Binomial_proportion_confidence_interval#Wilson_score_interval)

