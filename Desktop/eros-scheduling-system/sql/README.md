# SQL Code Reference

All BigQuery SQL code for the EROS Scheduling System.

**Dataset**: `of-scheduler-proj.eros_scheduling_brain`
**Location**: US (multi-region)

---

## Directory Structure

```
sql/
├── procedures/      # Stored Procedures (CALL statements)
├── functions/       # User-Defined Functions (SELECT calls)
└── tvfs/           # Table-Valued Functions (FROM clauses)
```

---

## Stored Procedures

**Location**: `sql/procedures/`

Procedures are called with `CALL` statements and perform operations.

### Core Procedures

| File | Purpose | Parameters | Usage Frequency |
|------|---------|------------|-----------------|
| `analyze_creator_performance.sql` | Complete 90-day performance analysis | page_name, OUT report (JSON) | On-demand |
| `select_captions_for_creator.sql` | Thompson Sampling caption selection | page_name, segment, counts | Per schedule |
| `update_caption_performance.sql` | Update bandit stats from messages | None | Every 6 hours |
| `lock_caption_assignments.sql` | Atomic schedule assignment | schedule_id, page_name, assignments | Per schedule |

### Example Usage

```sql
-- Run performance analysis
DECLARE report STRING;
CALL `of-scheduler-proj.eros_scheduling_brain.analyze_creator_performance`(
  'missalexa_paid',
  report
);
SELECT report;

-- Select captions for schedule
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'jade_bri',
  'High-Value/Price-Insensitive',
  2, 3, 2, 1  -- budget, mid, premium, bump counts
);

-- Update performance metrics (scheduled)
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
```

---

## User-Defined Functions (UDFs)

**Location**: `sql/functions/`

Functions are called in SELECT statements and return scalar values.

### Core Functions

| File | Purpose | Input | Output | Usage |
|------|---------|-------|--------|-------|
| `wilson_score_bounds.sql` | Calculate confidence intervals | successes, failures | STRUCT(lower, upper) | Statistical analysis |
| `wilson_sample.sql` | Thompson Sampling draw | successes, failures | FLOAT64 | Caption selection |
| `caption_key.sql` | Generate caption hash key | message_text | STRING | Caption matching |

### Example Usage

```sql
-- Get confidence bounds for conversion rate
SELECT
  caption_id,
  `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
    successes, failures
  ) AS bounds
FROM caption_bandit_stats;

-- Sample from Beta distribution
SELECT
  caption_id,
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
    successes, failures
  ) AS thompson_score
FROM caption_bandit_stats;

-- Generate caption key
SELECT
  `of-scheduler-proj.eros_scheduling_brain.caption_key`(message) AS key
FROM mass_messages;
```

---

## Table-Valued Functions (TVFs)

**Location**: `sql/tvfs/`

TVFs are called in FROM clauses and return table results.

### Analytics TVFs

| File | Purpose | Parameters | Returns |
|------|---------|------------|---------|
| `classify_account_size.sql` | Account tier classification | page_name, lookback_days | Tier, targets, metrics |
| `analyze_behavioral_segments.sql` | Audience segmentation | page_name, lookback_days | Segment, elasticity, entropy |
| `calculate_saturation_score.sql` | Audience fatigue detection | page_name, account_tier | Score, risk, recommendations |
| `analyze_psychological_triggers.sql` | Trigger performance | page_name, lookback_days | Trigger, stats, significance |
| `analyze_content_categories.sql` | Category performance | page_name, lookback_days | Category, trends, sensitivity |
| `analyze_day_of_week.sql` | Day-of-week patterns | page_name, lookback_days | Day, performance, significance |
| `optimize_time_windows.sql` | Best sending times | page_name, lookback_days | Hour, day_type, confidence |
| `calculate_conversion_stats.sql` | Global conversion metrics | page_name, lookback_days | Price tier stats |
| `detect_holiday_effects.sql` | Holiday impact analysis | page_name, lookback_days | Holiday, performance delta |

### Example Usage

```sql
-- Classify account size
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.classify_account_size`(
  'missalexa_paid',
  90
);

-- Analyze behavioral segments
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.analyze_behavioral_segments`(
  'jade_bri',
  90
);

-- Calculate saturation score
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.calculate_saturation_score`(
  'creator_name',
  'LARGE'
);

-- Get top psychological triggers
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.analyze_psychological_triggers`(
  'creator_name',
  90
)
ORDER BY rpr_lift_pct DESC
LIMIT 10;
```

---

## Common Patterns

### 1. Performance Analysis Pipeline

```sql
-- Step 1: Classify account
DECLARE size_tier STRING;
SET size_tier = (
  SELECT size_tier
  FROM `of-scheduler-proj.eros_scheduling_brain.classify_account_size`('page_name', 90)
);

-- Step 2: Check saturation
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.calculate_saturation_score`('page_name', size_tier);

-- Step 3: Get behavioral segment
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.analyze_behavioral_segments`('page_name', 90);
```

### 2. Caption Selection Workflow

```sql
-- Step 1: Update performance metrics
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- Step 2: Select captions
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'page_name',
  'High-Value/Price-Insensitive',
  2, 3, 2, 1
);

-- Step 3: Lock assignments (from application)
CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
  'schedule_id',
  'page_name',
  [STRUCT(123 AS caption_id, '2025-11-01' AS scheduled_send_date, 14 AS scheduled_send_hour)]
);
```

### 3. Comprehensive Creator Analysis

```sql
-- One-shot complete analysis
DECLARE report STRING;
CALL `of-scheduler-proj.eros_scheduling_brain.analyze_creator_performance`(
  'page_name',
  report
);

-- Parse JSON result
SELECT
  JSON_VALUE(report, '$.account_classification.size_tier') AS tier,
  JSON_VALUE(report, '$.behavioral_segment.segment_label') AS segment,
  JSON_VALUE(report, '$.saturation.risk_level') AS saturation_risk
FROM (SELECT report);
```

---

## Performance Considerations

### Query Optimization Tips

1. **Use lookback_days wisely**
   - 30 days: Fast queries, recent trends
   - 90 days: Comprehensive analysis (default)
   - 180 days: Long-term patterns (slower)

2. **Partition pruning**
   - All queries use `sending_time` filter
   - BigQuery auto-prunes partitions
   - Cost savings: ~70%

3. **Result caching**
   - Identical queries cached for 24 hours
   - Use scheduled queries for repeated analysis
   - Cache hit = $0 cost

4. **Batch operations**
   - Update performance once per 6 hours
   - Don't run analyze_creator_performance in loop
   - Use scheduled queries for regular updates

### Cost Estimates

| Operation | Data Scanned | Cost | Frequency |
|-----------|--------------|------|-----------|
| `update_caption_performance` | 15-20 GB | $0.075-0.10 | Every 6 hours |
| `analyze_creator_performance` | 25-30 GB | $0.125-0.15 | On-demand |
| `select_captions_for_creator` | 3-5 GB | $0.015-0.025 | Per schedule |
| `calculate_saturation_score` | 10-15 GB | $0.050-0.075 | Per analysis |

**Total per creator/week**: ~$0.30-0.50

---

## Deployment

### Deploy All SQL

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./deploy_all.sh
```

### Deploy Individual Components

```bash
# Deploy functions
bq query --use_legacy_sql=false < sql/functions/wilson_score_bounds.sql
bq query --use_legacy_sql=false < sql/functions/wilson_sample.sql
bq query --use_legacy_sql=false < sql/functions/caption_key.sql

# Deploy TVFs
for tvf in sql/tvfs/*.sql; do
  echo "Deploying $tvf..."
  bq query --use_legacy_sql=false < "$tvf"
done

# Deploy procedures
for proc in sql/procedures/*.sql; do
  echo "Deploying $proc..."
  bq query --use_legacy_sql=false < "$proc"
done
```

---

## Testing

### Validate Deployment

```sql
-- Check all routines exist
SELECT routine_name, routine_type
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_schema = 'eros_scheduling_brain'
ORDER BY routine_type, routine_name;

-- Test a simple function
SELECT
  `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(10, 5) AS bounds;

-- Test a simple TVF
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.classify_account_size`('test_creator', 30)
LIMIT 1;
```

---

## Troubleshooting

### Common Issues

**Issue**: Function not found
```sql
-- Solution: Check function exists
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'function_name';
```

**Issue**: Parameter type mismatch
```sql
-- Solution: Verify parameter types
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.PARAMETERS`
WHERE specific_schema = 'eros_scheduling_brain' AND specific_name = 'routine_name';
```

**Issue**: Query timeout
```sql
-- Solution: Reduce lookback_days or add WHERE filters
SELECT * FROM tvf_name('page', 30)  -- Use 30 instead of 90
WHERE date_col >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

---

## Best Practices

1. **Always use fully-qualified names**
   - ✅ `of-scheduler-proj.eros_scheduling_brain.function_name`
   - ❌ `function_name`

2. **Use timezone consistently**
   - All temporal analysis uses `America/Los_Angeles`
   - Convert with `DATETIME(timestamp, "America/Los_Angeles")`

3. **Handle NULL values**
   - Use `COALESCE()` for aggregations
   - Use `SAFE_DIVIDE()` for division
   - Check for empty arrays with `ARRAY_LENGTH(arr) > 0`

4. **Test before deploying**
   - Run in development dataset first
   - Verify results with known data
   - Check query execution plan

5. **Monitor costs**
   - Enable query cache
   - Use scheduled queries for repeated analysis
   - Set maximum_bytes_billed limits

---

**Last Updated**: October 31, 2025
**Status**: ✅ Production Ready
