-- q2_merge_caption_assignments.sql (BigQuery Standard SQL)
WITH assignment_input AS (
  -- TODO: agent populates rows:
  -- caption_id INT64, caption_text STRING, scheduled_send_date DATE, scheduled_send_hour INT64, price_tier STRING
  SELECT CAST(NULL AS INT64) AS caption_id, CAST(NULL AS STRING) AS caption_text, CAST(NULL AS DATE) AS scheduled_send_date, CAST(NULL AS INT64) AS scheduled_send_hour, CAST(NULL AS STRING) AS price_tier WHERE FALSE
),
source AS (
  SELECT
    @page_name AS page_name,
    caption_id,
    caption_text,
    scheduled_send_date,
    scheduled_send_hour,
    price_tier,
    TRUE AS is_active,
    CURRENT_TIMESTAMP() AS assigned_at,
    TO_HEX(SHA256(CONCAT(@page_name,'|',CAST(caption_id AS STRING),'|',CAST(scheduled_send_date AS STRING),'|',CAST(scheduled_send_hour AS STRING)))) AS assignment_key,
    @schedule_id AS schedule_id
  FROM assignment_input
)

MERGE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` AS T
USING source S
ON  T.assignment_key = S.assignment_key
AND T.page_name      = S.page_name

WHEN MATCHED THEN UPDATE SET
  caption_text        = S.caption_text,
  scheduled_send_date = S.scheduled_send_date,
  scheduled_send_hour = S.scheduled_send_hour,
  price_tier          = S.price_tier,
  is_active           = S.is_active,
  assigned_at         = S.assigned_at,
  assigned_date       = DATE(S.assigned_at),
  schedule_id         = S.schedule_id

WHEN NOT MATCHED THEN
  INSERT (page_name, caption_id, caption_text, scheduled_send_date, scheduled_send_hour, price_tier, is_active, assigned_at, assigned_date, assignment_key, schedule_id)
  VALUES (S.page_name, S.caption_id, S.caption_text, S.scheduled_send_date, S.scheduled_send_hour, S.price_tier, S.is_active, S.assigned_at, DATE(S.assigned_at), S.assignment_key, S.schedule_id);
