-- q3_verify_latest_recommendations.sql
-- Purpose: Verify schedule was written correctly to BigQuery
-- Usage: Execute after MERGE operations to validate data integrity

-- Main Verification Query
SELECT
  page_name,
  schedule_id,
  COUNT(*) AS row_count,
  COUNT(DISTINCT message_type) AS message_types_count,

  -- Schedule Type Validation (CRITICAL)
  SUM(CASE WHEN schedule_type = 'Mass Message' THEN 1 ELSE 0 END) AS mass_message_count,
  SUM(CASE WHEN schedule_type != 'Mass Message' OR schedule_type IS NULL THEN 1 ELSE 0 END) AS invalid_schedule_type_rows,

  -- Message Type Breakdown
  SUM(CASE WHEN message_type = 'Unlock' THEN 1 ELSE 0 END) AS unlock_count,
  SUM(CASE WHEN message_type = 'Follow up' THEN 1 ELSE 0 END) AS followup_count,
  SUM(CASE WHEN message_type = 'Photo bump' THEN 1 ELSE 0 END) AS photobump_count,

  -- Price Validation
  SUM(CASE
    WHEN message_type = 'Unlock' AND recommended_price LIKE '$%' THEN 1
    ELSE 0
  END) AS valid_unlock_prices,
  SUM(CASE
    WHEN message_type = 'Photo bump' AND recommended_price = '.' THEN 1
    ELSE 0
  END) AS valid_bump_prices,
  SUM(CASE
    WHEN message_type = 'Follow up' AND (recommended_price = '' OR recommended_price IS NULL) THEN 1
    ELSE 0
  END) AS valid_followup_prices,

  -- Caption ID Validation
  SUM(CASE WHEN caption_id IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_caption_id,
  SUM(CASE WHEN caption_id IS NULL THEN 1 ELSE 0 END) AS rows_without_caption_id,

  -- Date Range
  MIN(schedule_date) AS first_date,
  MAX(schedule_date) AS last_date,
  COUNT(DISTINCT schedule_date) AS unique_dates,

  -- Metadata
  MIN(created_at) AS first_created_at,
  MAX(updated_at) AS last_updated_at

FROM `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`
WHERE page_name = @page_name
  AND schedule_id = @schedule_id
GROUP BY page_name, schedule_id;

-- Expected Parameters:
-- @page_name: STRING (normalized creator name)
-- @schedule_id: STRING (unique schedule identifier)

-- Success Criteria (all must pass):
-- 1. row_count = expected_row_count (from schedule builder)
-- 2. invalid_schedule_type_rows = 0 (all rows have schedule_type='Mass Message')
-- 3. message_types_count >= 2 (at least Unlock + Photo bump present)
-- 4. unlock_count >= 1 (at least one PPV)
-- 5. photobump_count >= 2 (minimum bump requirement)
-- 6. valid_unlock_prices = unlock_count (all Unlocks have proper price format)
-- 7. valid_bump_prices = photobump_count (all bumps have price='.')
-- 8. valid_followup_prices = followup_count (all follow-ups have empty price)
-- 9. unique_dates = 7 (full week coverage)

-- Additional Validation Queries:

-- Check for PPV Gap Violations (tier-specific)
-- Small accounts (≤8K fans): 120 min gap
-- Medium accounts (9-18K fans): 90 min gap
-- Large accounts (≥19K fans): 65 min gap
WITH ppv_times AS (
  SELECT
    schedule_date,
    time_pst,
    PARSE_TIME('%I:%M %p', time_pst) AS time_parsed,
    ROW_NUMBER() OVER (PARTITION BY schedule_date ORDER BY PARSE_TIME('%I:%M %p', time_pst)) AS seq
  FROM `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`
  WHERE page_name = @page_name
    AND schedule_id = @schedule_id
    AND message_type = 'Unlock'
),
gap_check AS (
  SELECT
    a.schedule_date,
    a.time_pst AS time1,
    b.time_pst AS time2,
    TIME_DIFF(b.time_parsed, a.time_parsed, MINUTE) AS gap_minutes
  FROM ppv_times a
  JOIN ppv_times b
    ON a.schedule_date = b.schedule_date
    AND b.seq = a.seq + 1
)
SELECT
  schedule_date,
  time1,
  time2,
  gap_minutes,
  CASE
    WHEN gap_minutes < @minimum_gap_minutes THEN 'VIOLATION'
    ELSE 'OK'
  END AS gap_status
FROM gap_check
WHERE gap_minutes < @minimum_gap_minutes
ORDER BY schedule_date, time1;

-- @minimum_gap_minutes: 120 for small, 90 for medium, 75 for large

-- Check for Message Type Alternation Violations
WITH message_sequence AS (
  SELECT
    schedule_date,
    time_pst,
    message_type,
    LAG(message_type, 1) OVER (PARTITION BY schedule_date ORDER BY PARSE_TIME('%I:%M %p', time_pst)) AS prev_type,
    LAG(message_type, 2) OVER (PARTITION BY schedule_date ORDER BY PARSE_TIME('%I:%M %p', time_pst)) AS prev_prev_type
  FROM `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`
  WHERE page_name = @page_name
    AND schedule_id = @schedule_id
)
SELECT
  schedule_date,
  time_pst,
  message_type,
  prev_type,
  prev_prev_type
FROM message_sequence
WHERE message_type = prev_type
  AND message_type = prev_prev_type  -- 3 consecutive of same type
  AND message_type != 'Follow up'    -- Follow-ups can appear consecutively in funnels
ORDER BY schedule_date, time_pst;

-- Check for Missing schedule_type (CRITICAL ERROR)
SELECT
  row_number,
  schedule_date,
  time_pst,
  message_type,
  schedule_type,
  'ERROR: Missing or invalid schedule_type' AS error
FROM `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`
WHERE page_name = @page_name
  AND schedule_id = @schedule_id
  AND (schedule_type != 'Mass Message' OR schedule_type IS NULL)
ORDER BY row_number;

-- Expected Result: 0 rows (all schedule_type fields must be 'Mass Message')

-- Summary Statistics for Metadata Logging
SELECT
  'VERIFICATION_SUMMARY' AS check_type,
  COUNT(*) AS total_rows,
  SUM(CASE WHEN schedule_type = 'Mass Message' THEN 1 ELSE 0 END) AS valid_rows,
  SUM(CASE WHEN schedule_type != 'Mass Message' OR schedule_type IS NULL THEN 1 ELSE 0 END) AS invalid_rows,
  ROUND(SUM(CASE WHEN schedule_type = 'Mass Message' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS validation_percentage
FROM `of-scheduler-proj.eros_scheduling_brain.latest_recommendations`
WHERE page_name = @page_name
  AND schedule_id = @schedule_id;

-- Expected: validation_percentage = 100.00
