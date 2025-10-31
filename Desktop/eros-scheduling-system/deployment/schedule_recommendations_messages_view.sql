-- =============================================================================
-- EROS SCHEDULING SYSTEM - SCHEDULE RECOMMENDATIONS MESSAGES VIEW
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Read-only view for exporting schedules to Google Sheets
--          Joins schedule recommendations with caption details
-- =============================================================================

CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages` AS
SELECT
  sr.schedule_id,
  sr.page_name,
  sr.day_of_week,
  sr.scheduled_send_time,
  sr.message_type,
  sr.caption_id,

  -- Caption details
  c.caption_text,
  c.price_tier,
  c.content_category,
  c.has_urgency,

  -- Performance metrics
  cbs.avg_conversion_rate AS performance_score,
  cbs.confidence_lower_bound,
  cbs.confidence_upper_bound,
  cbs.total_observations,
  cbs.last_updated AS caption_last_updated,

  -- Schedule metadata
  sr.created_at AS schedule_created_at,
  sr.is_active AS schedule_is_active,

  -- Ordering
  sr.time_slot_rank

FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations` sr

-- Left join to handle messages without captions (text-only/free messages)
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.captions` c
  ON sr.caption_id = c.caption_id

-- Left join to caption performance stats
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` cbs
  ON sr.caption_id = cbs.caption_id
  AND sr.page_name = cbs.page_name

WHERE sr.is_active = TRUE

ORDER BY
  sr.schedule_id,
  sr.day_of_week,
  sr.scheduled_send_time;

-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================

-- Query 1: Test view with a specific schedule_id
-- SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
-- WHERE schedule_id = 'SCH_XXXXXXXX'
-- LIMIT 100;

-- Query 2: Count messages per schedule
-- SELECT
--   schedule_id,
--   page_name,
--   COUNT(*) as message_count,
--   COUNT(DISTINCT day_of_week) as days_covered,
--   MIN(scheduled_send_time) as first_message,
--   MAX(scheduled_send_time) as last_message
-- FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
-- GROUP BY schedule_id, page_name
-- ORDER BY schedule_id DESC;

-- Query 3: Verify caption joins
-- SELECT
--   COUNT(*) as total_messages,
--   COUNT(caption_id) as messages_with_captions,
--   COUNT(caption_text) as messages_with_caption_text,
--   COUNT(performance_score) as messages_with_performance_data
-- FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`;
