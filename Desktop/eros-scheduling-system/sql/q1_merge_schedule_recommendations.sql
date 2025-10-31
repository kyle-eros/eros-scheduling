-- q1_merge_schedule_recommendations.sql (BigQuery Standard SQL)
DECLARE run_generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

WITH msg AS (
  -- TODO: agent populates rows:
  -- send_at TIMESTAMP, message_type STRING, schedule_type STRING,
  -- caption STRING, recommended_price FLOAT64, caption_id STRING, row_number INT64
  SELECT CAST(NULL AS TIMESTAMP) AS send_at, CAST(NULL AS STRING) AS message_type, CAST(NULL AS STRING) AS schedule_type, CAST(NULL AS STRING) AS caption, CAST(NULL AS FLOAT64) AS recommended_price, CAST(NULL AS STRING) AS caption_id, CAST(NULL AS INT64) AS row_number WHERE FALSE
),
json_messages AS (
  SELECT ARRAY_AGG(STRUCT(
    FORMAT_TIMESTAMP('%FT%T%Ez', send_at)      AS send_at,
    message_type,
    schedule_type,
    caption,
    CAST(recommended_price AS FLOAT64)         AS recommended_price,
    caption_id,
    row_number
  ) ORDER BY send_at) AS messages
  FROM msg
),
source AS (
  SELECT
    @page_name                          AS page_name,
    @schedule_id                        AS schedule_id,
    run_generated_at                    AS generated_at,
    run_generated_at                    AS updated_at,
    TO_JSON(STRUCT(messages))           AS recommendation_data,
    0.80                                AS confidence_score,
    'pending'                           AS status,
    CURRENT_DATE()                      AS created_date
  FROM json_messages
)

MERGE `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations` AS T
USING source S
ON  T.page_name   = S.page_name
AND T.schedule_id = S.schedule_id

WHEN MATCHED THEN UPDATE SET
  updated_at          = S.updated_at,
  recommendation_data = S.recommendation_data,
  confidence_score    = S.confidence_score,
  status              = S.status

WHEN NOT MATCHED THEN
  INSERT (page_name, schedule_id, generated_at, updated_at, recommendation_data, confidence_score, status, created_date)
  VALUES (S.page_name, S.schedule_id, S.generated_at, S.updated_at, S.recommendation_data, S.confidence_score, S.status, S.created_date);
