# Caption Selection Procedure - Implementation & Deployment Guide

**Date:** 2025-10-31
**Status:** READY FOR PRODUCTION DEPLOYMENT
**Target:** EROS Scheduling System - BigQuery Deployment

---

## Quick Start

### Step 1: Review the Fixed Procedure
```bash
cat /Users/kylemerriman/Desktop/eros-scheduling-system/select_captions_for_creator_FIXED.sql
```

### Step 2: Deploy to BigQuery

```bash
# Using bq CLI (recommended)
bq query \
  --use_legacy_sql=false \
  < /Users/kylemerriman/Desktop/eros-scheduling-system/select_captions_for_creator_FIXED.sql

# OR using Cloud Console
# 1. Go to BigQuery Console
# 2. Select project: of-scheduler-proj
# 3. Dataset: eros_scheduling_brain
# 4. Create new query
# 5. Paste entire SQL file
# 6. Click "Run"
```

### Step 3: Verify Deployment
```sql
-- Check UDF exists
SELECT
  routine_name,
  routine_type,
  data_type
FROM `of-scheduler-proj`.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES
WHERE routine_name = 'wilson_sample';

-- Check procedure exists
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'test-creator',
  'Budget-Conscious',
  1,
  1,
  1,
  1
);
```

---

## What Was Fixed

### The 6 Critical Fixes

| # | Issue | Location | Status |
|---|-------|----------|--------|
| 1 | CROSS JOIN cold-start | Lines 69-84 | ✅ FIXED |
| 2 | Session settings | Removed entirely | ✅ FIXED |
| 3 | Schema corrections | Lines 48-60 | ✅ FIXED |
| 4 | Restrictions view | Lines 99-118 | ✅ FIXED |
| 5 | Budget penalties | Lines 121-152 | ✅ FIXED |
| 6 | UDF migration | Lines 1-46 | ✅ FIXED |

---

## Detailed Technical Overview

### Architecture

The procedure follows a 7-step processing pipeline:

```
Input Parameters
    ↓
[STEP 1] Recent Pattern History (Recency Tracking)
    ├─ COALESCE fix handles cold-start
    └─ Returns: recent_categories, recent_price_tiers, recent_urgency_flags
    ↓
[STEP 2] Creator Restrictions (View Integration)
    ├─ active_creator_caption_restrictions_v
    └─ Returns: restricted_categories, restricted_price_tiers, hard_patterns
    ↓
[STEP 3] Weekly Usage & Budget Penalties (NEW)
    ├─ Count category/urgency usage
    ├─ Apply progressive penalties (-1.0, -0.5, -0.3, -0.15, 0.0)
    └─ Returns: penalty scores per category
    ↓
[STEP 4] Available Captions Pool (Filtering)
    ├─ Filter by performance score
    ├─ Apply restriction checks
    ├─ Exclude cooldown captions (7-day)
    └─ Returns: candidate caption pool
    ↓
[STEP 5] Thompson Sampling Scoring (NEW UDF)
    ├─ Call persisted wilson_sample() UDF
    ├─ Calculate diversity bonus
    ├─ Apply segment multiplier
    └─ Returns: scored captions
    ↓
[STEP 6] Final Ranking (Window Functions)
    ├─ Calculate final_score with formula:
    │  score = (thompson * 0.70 + diversity * 0.15 +
    │          historical_emv/100 * 0.15 + penalty * 0.10) * segment_mult
    ├─ ROW_NUMBER() by price_tier
    └─ Returns: ranked captions
    ↓
[STEP 7] Output Selection (Tier Quotas)
    ├─ Select top N from each price_tier
    ├─ Respect num_budget, num_mid, num_premium, num_bump quotas
    └─ Returns: final caption selection
    ↓
Output Results
```

### Data Flow

```sql
recency (0-1 rows)
    ↓
rp (1 row with arrays)
    ↓
restr (0-1 rows)
    ↓
weekly_usage (0-many rows)
    ↓
budget_penalties (0-many rows)
    ↓
pool (many rows - all available captions)
    ↓
scored (many rows - with Thompson scores)
    ↓
ranked (many rows - with tier ranking)
    ↓
final selection (num_budget + num_mid + num_premium + num_bump rows)
```

---

## Configuration Parameters

### Procedure Inputs

```sql
normalized_page_name STRING
  → Creator identifier (e.g., 'jadebri')
  → Used for filtering and personalization

behavioral_segment STRING
  → 'High-Value/Price-Insensitive'  → 1.25x premium multiplier
  → 'Budget-Conscious'               → 1.15x budget/mid multiplier
  → Other values                     → 1.0x (no multiplier)

num_budget_needed INT64
  → How many budget-tier captions to select
  → Range: 0-50 (typical: 3-8)

num_mid_needed INT64
  → How many mid-tier captions to select
  → Range: 0-50 (typical: 5-15)

num_premium_needed INT64
  → How many premium-tier captions to select
  → Range: 0-50 (typical: 8-20)

num_bump_needed INT64
  → How many bump captions to select
  → Range: 0-20 (typical: 2-5)
```

### Tuning Parameters

```sql
DECLARE exploration_rate FLOAT64 DEFAULT 0.20;
  → Controls Thompson Sampling exploration
  → 0.0 = pure exploitation (use proven winners)
  → 0.2 = balanced (recommended)
  → 1.0 = pure exploration (try everything equally)
  → Adjust based on: caption pool size, content saturation

DECLARE pattern_diversity_weight FLOAT64 DEFAULT 0.15;
  → Weight for pattern variety in scoring
  → 0.0 = ignore diversity (risk: repetitive content)
  → 0.15 = balanced (recommended)
  → 0.5 = strong diversity preference
  → Adjust based on: audience engagement patterns

DECLARE max_urgent_per_week INT64 DEFAULT 5;
  → Maximum urgency captions per 7-day period
  → Typical range: 3-7
  → Higher = more aggressive marketing
  → Lower = more subtle approach

DECLARE max_per_category INT64 DEFAULT 20;
  → Maximum captions per category per 7-day period
  → Typical range: 15-25
  → Prevents category saturation
```

---

## Budget Penalty System

### How Penalties Work

```
Weekly Usage Tracking:
├─ Count captions by category AND urgency
├─ Example: B/G + Urgent captions used 4 times this week
└─ max_urgent_per_week = 5

Penalty Calculation:
├─ times_used >= max        → penalty = -1.0  (EXCLUDE)
├─ times_used >= 80% * max  → penalty = -0.5  (HEAVY)
├─ times_used >= 60% * max  → penalty = -0.15 (LIGHT)
├─ times_used < 60% * max   → penalty = 0.0   (NONE)
└─ Example: 4/5 = 80% → apply -0.5 penalty

Score Impact:
├─ Normal score = (thompson * 0.70 + diversity * 0.15 + emv/100 * 0.15)
├─ With budget_penalty = (... + budget_penalty * 0.10) * segment_mult
└─ Example: 0.85 score → 0.85 - (0.5 * 0.10) = 0.80 (reduced by 5.9%)

Hard Exclusion:
├─ budget_penalty <= -1.0
├─ final_score = NULL (filtered out in WHERE clause)
└─ Caption not selectable at all
```

### Penalty Table Reference

For max_urgent_per_week = 5 and max_per_category = 20:

| Usage | % of Max | Penalty | Effect | Example |
|-------|----------|---------|--------|---------|
| 0-2   | 0-40%    | 0.0     | No reduction | 1st/2nd usage |
| 2-3   | 40-60%   | 0.0     | No reduction | 2nd/3rd usage |
| 3-4   | 60-80%   | -0.15   | -1.5% score | 3rd/4th usage |
| 4-5   | 80-100%  | -0.5    | -5% score | 4th/5th usage |
| 5+    | 100%+    | -1.0    | **EXCLUDE** | 6th+ usage |

---

## Integration Points

### Database Dependencies

1. **`active_caption_assignments` table**
   ```sql
   - caption_id (INT64): Links to caption_bank
   - page_name (STRING): Creator identifier
   - is_active (BOOL): Active flag
   - scheduled_send_date (DATE): Date tracking
   ```

2. **`caption_bank` table**
   ```sql
   - caption_id (INT64): Primary key
   - caption_text (STRING): Content
   - price_tier (STRING): 'budget' | 'mid' | 'premium' | 'bump'
   - content_category (STRING): Topic/category
   - has_urgency (BOOL): Urgency flag
   - avg_revenue (FLOAT64): Historical EMV
   ```

3. **`caption_bandit_stats` table**
   ```sql
   - caption_id (INT64): Links to caption_bank
   - page_name (STRING): Creator identifier
   - successes (INT64): Thompson Sampling alpha
   - failures (INT64): Thompson Sampling beta
   - avg_emv (FLOAT64): Average earning value
   - confidence_lower_bound (FLOAT64): Wilson Score lower
   - confidence_upper_bound (FLOAT64): Wilson Score upper
   ```

4. **`available_captions` table**
   ```sql
   - caption_id (INT64): Primary key
   - caption_text (STRING): Content
   - price_tier (STRING): Pricing tier
   - content_category (STRING): Category
   - has_urgency (BOOL): Urgency flag
   - overall_performance_score (FLOAT64): Quality metric
   - avg_revenue (FLOAT64): Historical EMV
   ```

5. **`active_creator_caption_restrictions_v` view**
   ```sql
   - page_name (STRING): Creator identifier
   - restricted_categories (ARRAY<STRING>): Forbidden categories
   - restricted_price_tiers (ARRAY<STRING>): Forbidden tiers
   - hard_patterns (ARRAY<STRING>): Forbidden regex patterns
   ```

### Required Indexes

```sql
-- Performance critical indexes
CREATE INDEX idx_active_assignments_page_date
  ON active_caption_assignments(page_name, is_active, scheduled_send_date);

CREATE INDEX idx_bandit_stats_page_caption
  ON caption_bandit_stats(page_name, caption_id);

CREATE INDEX idx_caption_bank_tier_category
  ON caption_bank(price_tier, content_category);

-- Optional but recommended
CREATE INDEX idx_active_assignments_caption_id
  ON active_caption_assignments(caption_id, is_active);
```

---

## Sample Execution & Expected Output

### Test Call

```sql
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'jadebri',
  'High-Value/Price-Insensitive',
  5,    -- num_budget_needed
  8,    -- num_mid_needed
  12,   -- num_premium_needed
  3     -- num_bump_needed
);
```

### Expected Output Schema

```sql
column_name          data_type              description
─────────────────────────────────────────────────────
caption_id           INT64                  Unique caption identifier
caption_text         STRING                 Caption content
price_tier           STRING                 'budget'|'mid'|'premium'|'bump'
content_category     STRING                 Content topic
has_urgency          BOOL                   Urgency flag
final_score          FLOAT64                Combined ranking score
debug_info STRUCT
  ├─ thompson_score          FLOAT64        Thompson Sampling score (0-1)
  ├─ diversity_bonus         FLOAT64        Pattern variety bonus
  ├─ segment_multiplier      FLOAT64        Behavioral segment multiplier
  ├─ successes               INT64          Thompson alpha parameter
  ├─ failures                INT64          Thompson beta parameter
  ├─ confidence_lower        FLOAT64        Wilson Score lower bound
  ├─ confidence_upper        FLOAT64        Wilson Score upper bound
  └─ budget_penalty          FLOAT64        Category/urgency penalty
```

### Example Output

```
Row  caption_id  price_tier  final_score  debug_info.thompson_score
───────────────────────────────────────────────────────────────────
1    12345       premium     0.782        0.85
2    23456       premium     0.756        0.82
3    34567       mid         0.721        0.78
4    45678       premium     0.715        0.81
5    56789       budget      0.698        0.75
...
```

---

## Performance Tuning

### Query Optimization

1. **Index Strategy**
   - Add indexes on frequently filtered columns
   - Partition tables by page_name or scheduled_send_date
   - Consider clustered indexes on (page_name, caption_id)

2. **Materialization**
   - Pre-calculate weekly_usage in a scheduled job
   - Store results in `weekly_usage_cache` table
   - Update every 6 hours (before peak times)

3. **Query Hints**
   - Use `@{SCRIPT_TYPE="STANDARD_SQL"}` for optimization
   - Consider table snapshots for large datasets
   - Use APPROX_* functions for quick estimates

### Execution Time Baseline

| Creator Size | Captions | Est. Time | Target |
|--------------|----------|-----------|--------|
| Small        | <100     | 300-500ms | <1s    |
| Medium       | 100-1K   | 1-2s      | <5s    |
| Large        | 1K-5K    | 2-5s      | <10s   |
| XL           | 5K+      | 5-15s     | <30s   |

### Optimization Checklist

- [ ] Verify indexes exist
- [ ] Run `ANALYZE TABLE` on large tables
- [ ] Check statistics are up to date
- [ ] Monitor query execution plan
- [ ] Consider materialized views for repeated patterns
- [ ] Monitor slot usage and adjust if needed

---

## Monitoring & Debugging

### Health Check Query

```sql
-- Check procedure execution stats
SELECT
  creation_time,
  last_modified_time,
  routine_type,
  routine_definition
FROM `of-scheduler-proj`.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES
WHERE routine_name = 'select_captions_for_creator'
  AND routine_schema = 'eros_scheduling_brain';

-- Expected: 1 row with type = 'PROCEDURE'
```

### Debugging Query Output

```sql
-- Capture all intermediate stages
DECLARE test_creator STRING DEFAULT 'jadebri';

-- Step 1: Check recent patterns
SELECT DISTINCT
  'recency' AS stage,
  COUNT(*) AS pattern_count
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE page_name = test_creator
  AND is_active = TRUE
  AND scheduled_send_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);

-- Step 2: Check available pool
SELECT DISTINCT
  'available_captions' AS stage,
  COUNT(*) AS caption_count,
  COUNT(DISTINCT price_tier) AS tier_count
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions`
WHERE overall_performance_score > 0;

-- Step 3: Check restrictions
SELECT DISTINCT
  'restrictions' AS stage,
  COUNT(*) AS restriction_count
FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
WHERE page_name = test_creator;

-- Step 4: Check bandit stats
SELECT DISTINCT
  'bandit_stats' AS stage,
  COUNT(*) AS stats_count,
  MIN(successes) AS min_successes,
  MAX(successes) AS max_successes,
  AVG(avg_emv) AS mean_emv
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`
WHERE page_name = test_creator;
```

### Troubleshooting Common Issues

**Problem:** Procedure returns 0 rows
```sql
-- 1. Check if creator has any captions
SELECT COUNT(DISTINCT caption_id)
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions`
WHERE overall_performance_score > 0;

-- 2. Check restrictions aren't over-filtering
SELECT restricted_categories, restricted_price_tiers
FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
WHERE page_name = 'your-creator';

-- 3. Check if all captions in cooldown
SELECT COUNT(DISTINCT caption_id)
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE page_name = 'your-creator'
  AND is_active = TRUE
  AND scheduled_send_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
```

**Problem:** Same caption returned multiple times
```sql
-- 1. Check for duplicates in available_captions
SELECT caption_id, COUNT(*) AS cnt
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions`
GROUP BY caption_id
HAVING cnt > 1;

-- 2. Verify procedure WHERE clause filtering
-- (Should eliminate duplicates)
```

**Problem:** Slow execution (>10 seconds)
```sql
-- 1. Analyze query execution plan
EXPLAIN
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
  'jadebri',
  'Budget-Conscious',
  5, 8, 12, 3
);

-- 2. Check if indexes are used
-- Look for "Full Scan" warnings in output

-- 3. Check table sizes
SELECT
  table_name,
  size_bytes / POW(10,9) AS size_gb,
  row_count
FROM `of-scheduler-proj`.eros_scheduling_brain.__TABLES__
ORDER BY size_bytes DESC;
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Code review completed
- [ ] All fixes documented
- [ ] Validation tests prepared
- [ ] Team members notified
- [ ] Rollback plan documented

### Deployment Steps

1. **Test Environment**
   - [ ] Deploy to test dataset first
   - [ ] Execute against test creator
   - [ ] Verify output correctness
   - [ ] Check execution time < 10s
   - [ ] Run all validation queries

2. **Production - Phase 1 (5 creators)**
   - [ ] Deploy UDF (wilson_sample)
   - [ ] Deploy procedure
   - [ ] Execute against 5 test creators
   - [ ] Monitor for 2 hours
   - [ ] Verify correct results

3. **Production - Phase 2 (20% roll-out)**
   - [ ] Deploy to 20% of active creators
   - [ ] Monitor metrics for 24 hours
   - [ ] Check EMV trends
   - [ ] Check error rates
   - [ ] Gather feedback

4. **Production - Phase 3 (100% roll-out)**
   - [ ] Deploy to remaining creators
   - [ ] Continue monitoring for 1 week
   - [ ] Compare metrics to baseline

### Post-Deployment

- [ ] Document final deployment time
- [ ] Update runbooks
- [ ] Archive old procedure
- [ ] Schedule monitoring review (1 week, 1 month)
- [ ] Plan next optimization cycle

---

## Rollback Plan

If issues occur in production:

```sql
-- Step 1: Identify affected creators
SELECT DISTINCT page_name
FROM `of-scheduler-proj.eros_scheduling_brain.audit_log`
WHERE action = 'CAPTION_SELECTION'
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND status = 'ERROR';

-- Step 2: Revert to previous procedure (if archived)
-- Option A: Restore from backup
ALTER TABLE active_caption_assignments
  RESTORE TABLE TO SNAPSHOT FROM '2025-10-30';

-- Option B: Use previous procedure version
-- Deploy old select_captions_for_creator_v1 temporarily

-- Step 3: Notify affected creators
SELECT DISTINCT page_name, error_message
FROM `of-scheduler-proj.eros_scheduling_brain.audit_log`
WHERE action = 'CAPTION_SELECTION'
  AND status = 'ERROR'
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY created_at DESC;

-- Step 4: Investigate root cause
-- Review error logs in Cloud Logging
```

---

## Success Metrics

Monitor these KPIs post-deployment:

| Metric | Target | Check Frequency |
|--------|--------|-----------------|
| Procedure execution time | <5s median | Every 1h |
| Error rate | <0.1% | Every 6h |
| Caption diversity | >50 unique/week | Daily |
| Budget penalty compliance | 100% | Daily |
| EMV uplift | >0% (no regression) | Daily |
| Creator satisfaction | No complaints | Weekly |

---

## Files Reference

| File | Purpose | Lines |
|------|---------|-------|
| select_captions_for_creator_FIXED.sql | Main procedure + UDF | 323 |
| CAPTION_SELECTION_FIX_REPORT.md | Detailed fix documentation | 400+ |
| IMPLEMENTATION_GUIDE.md | This file - deployment guide | 500+ |

---

## Support Contacts

- **SQL Issues:** Query Optimization Agent
- **Deployment Issues:** Database Admin
- **Performance Issues:** Cloud Performance Team
- **Business Logic:** Product Manager

---

## Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-10-31 | 1.0 | Initial release with all fixes | Query Optimization Agent |

---

**Last Updated:** 2025-10-31
**Next Review:** 2025-11-07 (post-deployment monitoring)
