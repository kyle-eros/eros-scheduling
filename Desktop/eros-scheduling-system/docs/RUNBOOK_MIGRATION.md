# BigQuery Schema Migration Runbook

**Migration Date:** 2025-10-29
**Dataset:** `of-scheduler-proj.eros_scheduling_brain`
**Status:** COMPLETED

---

## Changes Made

### 1. SQL Query Updates

#### **q1_merge_schedule_recommendations.sql**
- **Changed:** Rewritten to use JSON envelope model
- **Storage:** One row per `(page_name, schedule_id)` with messages in `recommendation_data.messages` JSON array
- **Parameters:** Binds `@page_name` and `@schedule_id` in source CTE
- **Syntax:** Uses `MERGE ... USING` (not `MERGE INTO`)
- **Target Table:** `schedule_recommendations` (existing structure preserved)

#### **q2_merge_caption_assignments.sql**
- **Changed:** Updated to target `active_caption_assignments` (not `caption_assignments`)
- **Key Fields:** Uses `assignment_key` + `page_name` as composite key
- **New Field:** Now writes `schedule_id` column
- **Parameters:** Binds `@page_name` and `@schedule_id`

#### **q3_verify_latest_recommendations.sql**
- **Status:** No changes needed
- **Verified:** All references point to canonical dataset `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`

---

### 2. Schema Changes

#### **active_caption_assignments Table**
- **Action:** Added `schedule_id STRING` column
- **Reason:** Links caption assignments to specific schedule versions
- **Command:**
  ```sql
  ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  ADD COLUMN IF NOT EXISTS schedule_id STRING;
  ```

**Final Schema:**
```
page_name           STRING
caption_id          INT64
caption_text        STRING
assigned_date       DATE
scheduled_send_date DATE
scheduled_send_hour INT64
price_tier          STRING
is_active           BOOL
assigned_at         TIMESTAMP
assignment_key      STRING
schedule_id         STRING  ← NEW
```

---

### 3. Bridge View Created

#### **schedule_recommendations_messages**
- **Type:** VIEW
- **Purpose:** Flattens JSON envelope into row-per-message structure for compatibility
- **Location:** `sql/create_view_schedule_recommendations_messages.sql`
- **Schema:**
  ```
  page_name          STRING
  schedule_id        STRING
  send_at            TIMESTAMP
  message_type       STRING
  schedule_type      STRING
  caption            STRING
  recommended_price  FLOAT64
  caption_id         STRING
  row_number         INT64
  generated_at       TIMESTAMP
  updated_at         TIMESTAMP
  ```

**Query Example:**
```sql
SELECT page_name, schedule_id, COUNT(*) AS message_count
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
WHERE page_name = @page_name
GROUP BY 1,2;
```

---

## Validation Results

### Barrier A Checks (Passed)
- [x] q1/q2 updated to JSON model and active table
- [x] Bridge view created
- [x] active_caption_assignments has schedule_id column
- [x] CI gate passes (page_name-only gate clean)
- [x] No `MERGE INTO` syntax found
- [x] All canonical dataset references verified
- [x] @page_name and @schedule_id binding confirmed
- [x] run_bq.sh executable with correct parameters

### Barrier B Checks (Passed)
- [x] schedule_recommendations has `recommendation_data` JSON column
- [x] active_caption_assignments exists with schedule_id column
- [x] Bridge view created and queryable
- [x] Smoke tests execute without errors

---

## How to Use

### Writing Schedules (q1)
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system
export PAGE_NAME="jadebri"
export SCHEDULE_ID="schedule_2025-10-29_v1"
./scripts/run_bq.sh sql/q1_merge_schedule_recommendations.sql
```

### Writing Caption Assignments (q2)
```bash
export PAGE_NAME="jadebri"
export SCHEDULE_ID="schedule_2025-10-29_v1"
./scripts/run_bq.sh sql/q2_merge_caption_assignments.sql
```

### Reading Flattened Messages
```bash
bq query --nouse_legacy_sql \
  --parameter=page_name:STRING:"jadebri" \
  "SELECT * FROM \`of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages\`
   WHERE page_name = @page_name
   ORDER BY send_at;"
```

---

## Notes

1. **Storage Model:** JSON envelope in `schedule_recommendations.recommendation_data`
2. **Assignment Table:** `active_caption_assignments` (NOT `caption_assignments`)
3. **Parameter Binding:** All queries use `@page_name` + `@schedule_id` for scoping
4. **Dataset:** All references use fully-qualified `of-scheduler-proj.eros_scheduling_brain`

---

## Migration Sign-Off

**Executed By:** Claude Code
**Verification Status:** ALL CHECKS PASSED
**Production Ready:** YES

---
