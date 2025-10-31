CREATE OR REPLACE VIEW `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages` AS
SELECT
  r.page_name,
  r.schedule_id,
  TIMESTAMP(JSON_VALUE(m, '$.send_at'))                                 AS send_at,
  JSON_VALUE(m, '$.message_type')                                       AS message_type,
  JSON_VALUE(m, '$.schedule_type')                                      AS schedule_type,
  JSON_VALUE(m, '$.caption')                                            AS caption,
  CAST(JSON_VALUE(m, '$.recommended_price') AS FLOAT64)                 AS recommended_price,
  JSON_VALUE(m, '$.caption_id')                                         AS caption_id,
  SAFE_CAST(JSON_VALUE(m, '$.row_number') AS INT64)                     AS row_number,
  r.generated_at,
  r.updated_at
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations` r,
UNNEST(JSON_EXTRACT_ARRAY(r.recommendation_data, '$.messages')) AS m;
