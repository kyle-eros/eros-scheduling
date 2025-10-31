# Infrastructure Integration Guide
## Caption Bandit Stats System

**Date**: 2025-10-31
**Status**: INFRASTRUCTURE PHASE COMPLETE
**Next Phase**: Application Integration

---

## Overview

The foundational database infrastructure for the caption-selector system has been successfully created and validated. This guide provides instructions for integrating the infrastructure into the application.

---

## Infrastructure Components

### 1. caption_bandit_stats Table
**Purpose**: Central repository for caption performance metrics

**Location**: `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`

**Key Features**:
- Partitioned by `last_updated` (DATE) for efficient time-range queries
- Clustered by `page_name`, `caption_id`, `last_used` for optimal performance
- Supports 15 metrics per caption-page combination
- Row-level granularity for fine-grained analysis

### 2. wilson_score_bounds() UDF
**Purpose**: Calculate 95% confidence interval using Wilson Score method

**Input Parameters**:
- `successes INT64`: Count of successful observations
- `failures INT64`: Count of failed observations

**Output Structure**:
```sql
STRUCT<
  lower_bound FLOAT64,      -- Lower confidence bound (0.0-1.0)
  upper_bound FLOAT64,      -- Upper confidence bound (0.0-1.0)
  exploration_bonus FLOAT64 -- Inverse sqrt(n+1) for exploration weight
>
```

**Usage Example**:
```sql
SELECT
  caption_id,
  page_name,
  b.lower_bound,
  b.upper_bound,
  b.exploration_bonus
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` stats
CROSS JOIN UNNEST([
  `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
    stats.successes,
    stats.failures
  )
]) b
WHERE page_name = 'homepage'
```

### 3. wilson_sample() UDF
**Purpose**: Generate Thompson samples from Wilson confidence intervals

**Input Parameters**:
- `successes INT64`: Count of successful observations
- `failures INT64`: Count of failed observations

**Output**:
- `FLOAT64`: Random sample from [lower_bound, upper_bound]

**Usage Example**:
```sql
SELECT
  caption_id,
  page_name,
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(successes, failures) as sample_value
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE page_name = 'homepage'
ORDER BY sample_value DESC
LIMIT 1
```

---

## Integration Patterns

### Pattern 1: Initialize Caption Stats
When a new caption is added to the system:

```sql
INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  (caption_id, page_name, successes, failures, total_observations,
   total_revenue, avg_conversion_rate, avg_emv, last_updated)
VALUES
  (NEW_CAPTION_ID, 'page_name', 1, 1, 0, 0.0, 0.0, 0.0, CURRENT_TIMESTAMP());
```

### Pattern 2: Record Observation
When a caption is shown and a success/failure occurs:

```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
SET
  successes = successes + 1,  -- Increment on success; skip on failure
  total_observations = total_observations + 1,
  total_revenue = total_revenue + REVENUE_VALUE,
  avg_emv = total_revenue / NULLIF(total_observations, 0),
  last_emv_observed = LATEST_EMV_VALUE,
  last_used = CURRENT_TIMESTAMP(),
  last_updated = CURRENT_TIMESTAMP()
WHERE caption_id = CAPTION_ID
  AND page_name = 'page_name';
```

### Pattern 3: Thompson Sampling Selection
When selecting the best caption for a user:

```sql
WITH caption_samples AS (
  SELECT
    caption_id,
    page_name,
    `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
      successes, failures
    ) as thompson_sample
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  WHERE page_name = 'target_page'
    AND successes + failures > 0
)
SELECT
  caption_id,
  page_name,
  thompson_sample
FROM caption_samples
ORDER BY thompson_sample DESC
LIMIT 1;
```

### Pattern 4: Calculate Performance Percentiles
Update performance rankings:

```sql
WITH ranked_captions AS (
  SELECT
    caption_id,
    page_name,
    successes,
    failures,
    CAST(successes AS FLOAT64) / NULLIF(successes + failures, 0) as win_rate,
    ROW_NUMBER() OVER (
      PARTITION BY page_name
      ORDER BY (CAST(successes AS FLOAT64) / NULLIF(successes + failures, 0)) DESC
    ) as rank,
    COUNT(*) OVER (PARTITION BY page_name) as total_captions
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
)
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
SET performance_percentile = CAST(
  100.0 * (total_captions - rank) / total_captions AS INT64
)
FROM ranked_captions rc
WHERE caption_bandit_stats.caption_id = rc.caption_id
  AND caption_bandit_stats.page_name = rc.page_name;
```

---

## Performance Optimization Tips

### 1. Indexing Strategy
The table uses clustering instead of traditional indexes:
- Queries filtering by `page_name` are automatically optimized
- Queries filtering by `caption_id` benefit from clustering
- Time-range queries on `last_updated` use partitioning
- Combination queries (page + caption + time) are highly optimized

### 2. Query Optimization
**Good - Will scan fewer blocks**:
```sql
WHERE page_name = 'homepage'
  AND DATE(last_updated) >= CURRENT_DATE() - 30
```

**Avoid - Will scan entire table**:
```sql
WHERE 1 = 1  -- No filter
WHERE CAST(successes AS FLOAT64) / (successes + failures) > 0.5  -- Complex calc
```

### 3. Batch Operations
For high-volume updates:

```sql
-- Batch insert observations
INSERT INTO `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
  (caption_id, page_name, successes, failures, ...)
VALUES
  (101, 'page1', 1, 1, ...),
  (102, 'page1', 1, 1, ...),
  (103, 'page1', 1, 1, ...);  -- Batch up to 10,000 rows
```

### 4. Partition Pruning
Always filter by date range when possible:

```sql
SELECT *
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE DATE(last_updated) = CURRENT_DATE()  -- Automatically prunes partitions
```

---

## Monitoring and Alerting

### Key Metrics to Monitor

1. **Data Staleness**
```sql
SELECT
  page_name,
  MAX(last_updated) as latest_update,
  CURRENT_TIMESTAMP() - MAX(last_updated) as age_hours
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY page_name
HAVING CURRENT_TIMESTAMP() - MAX(last_updated) > INTERVAL 24 HOUR
ORDER BY age_hours DESC;
```

2. **Observation Growth Rate**
```sql
SELECT
  DATE(last_updated) as observation_date,
  page_name,
  SUM(total_observations) as total_obs,
  COUNT(DISTINCT caption_id) as unique_captions,
  COUNT(*) as row_count
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE DATE(last_updated) >= CURRENT_DATE() - 30
GROUP BY observation_date, page_name
ORDER BY observation_date DESC, page_name;
```

3. **Caption Utilization**
```sql
SELECT
  page_name,
  COUNT(DISTINCT caption_id) as total_captions,
  COUNTIF(total_observations = 0) as unused_captions,
  COUNTIF(total_observations > 0) as active_captions,
  MIN(total_observations) as min_observations,
  MAX(total_observations) as max_observations,
  AVG(total_observations) as avg_observations
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
GROUP BY page_name;
```

### Alert Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| Data staleness | > 24 hours | Alert to Engineering |
| Observation rate | < 10/hour | Review caption selection logic |
| Unused captions | > 30% of total | Review caption strategy |
| Partition age | > 90 days | Archive to cold storage |

---

## Troubleshooting

### Issue: UDF Returns NULL
**Cause**: Function call with invalid parameters (e.g., negative values)
**Solution**: Validate inputs before calling
```sql
WHERE successes >= 0 AND failures >= 0
```

### Issue: wilson_sample Results Always Similar
**Cause**: Too few observations (wide confidence bounds)
**Solution**: Check successes + failures > 10 for meaningful variation

### Issue: Queries Scanning Entire Table
**Cause**: Not filtering by partitioning/clustering columns
**Solution**: Always include WHERE clauses with page_name and/or date range

### Issue: Table Growing Too Large
**Cause**: Insufficient cleanup of old data
**Solution**: Implement partition expiration (set to 90 days recommended)
```sql
ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
SET OPTIONS(
  partition_expiration_ms=7776000000  -- 90 days
);
```

---

## Deployment Checklist

- [x] caption_bandit_stats table created
- [x] wilson_score_bounds UDF created
- [x] wilson_sample UDF created
- [x] All components tested and validated
- [ ] Application code updated to use new components
- [ ] Monitoring queries deployed
- [ ] Alert rules configured
- [ ] Documentation updated
- [ ] Team training completed
- [ ] Production deployment scheduled

---

## Files and References

| File | Purpose |
|------|---------|
| `bigquery_infrastructure_setup.sql` | SQL creation scripts and tests |
| `validate_infrastructure.sh` | Validation script |
| `INFRASTRUCTURE_VALIDATION_REPORT.md` | Detailed test results |
| `INFRASTRUCTURE_INTEGRATION_GUIDE.md` | This file - integration guide |

---

## Support and Questions

For questions about the infrastructure:

1. Review the INFRASTRUCTURE_VALIDATION_REPORT.md for detailed component information
2. Check SQL examples in this guide for integration patterns
3. Run validate_infrastructure.sh to verify system health
4. Review BigQuery documentation for advanced optimization techniques

---

**Last Updated**: 2025-10-31
**Status**: READY FOR APPLICATION INTEGRATION
