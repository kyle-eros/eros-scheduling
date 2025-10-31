#!/bin/bash
# =============================================================================
# STEP-BY-STEP DEPLOYMENT (works around bq query multi-statement limitations)
# =============================================================================

set -euo pipefail

PROJECT="of-scheduler-proj"
DATASET="eros_scheduling_brain"

echo "Deploying infrastructure step-by-step..."
echo ""

# Phase 1: UDFs
echo "Phase 1: Deploying UDFs..."
bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(
  message STRING
)
RETURNS STRING
AS (
  TO_HEX(SHA256(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          LOWER(TRIM(message)),
          r'[\p{So}\p{Sk}\p{Sm}\p{Sc}]', ''
        ),
        r'[^\w\s]', ''
      ),
      r'\s+', ' '
    )
  ))
);
EOF

bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.caption_key`(
  message STRING
)
RETURNS STRING
AS (
  `of-scheduler-proj.eros_scheduling_brain.caption_key_v2`(message)
);
EOF

bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
  successes INT64,
  failures INT64
)
RETURNS STRUCT<lower_bound FLOAT64, upper_bound FLOAT64, exploration_bonus FLOAT64>
AS ((
  WITH calc AS (
    SELECT
      CAST(successes + failures AS FLOAT64) AS n,
      SAFE_DIVIDE(
        CAST(successes AS FLOAT64),
        NULLIF(CAST(successes + failures AS FLOAT64), 0)
      ) AS p_hat,
      1.96 AS z
  )
  SELECT AS STRUCT
    CASE WHEN n = 0 THEN 0.0 ELSE
      SAFE_DIVIDE(
        p_hat + SAFE_DIVIDE(z*z, 2*n) - z*SQRT(
          SAFE_DIVIDE(p_hat*(1-p_hat), n) + SAFE_DIVIDE(z*z, 4*n*n)
        ),
        1 + SAFE_DIVIDE(z*z, n)
      )
    END AS lower_bound,
    CASE WHEN n = 0 THEN 1.0 ELSE
      SAFE_DIVIDE(
        p_hat + SAFE_DIVIDE(z*z, 2*n) + z*SQRT(
          SAFE_DIVIDE(p_hat*(1-p_hat), n) + SAFE_DIVIDE(z*z, 4*n*n)
        ),
        1 + SAFE_DIVIDE(z*z, n)
      )
    END AS upper_bound,
    SAFE_DIVIDE(1.0, SQRT(n + 1.0)) AS exploration_bonus
  FROM calc
));
EOF

bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
  successes INT64,
  failures INT64
)
RETURNS FLOAT64
AS ((
  WITH w AS (
    SELECT b.lower_bound lb, b.upper_bound ub
    FROM UNNEST([
      `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(successes, failures)
    ]) b
  )
  SELECT GREATEST(0.0, LEAST(1.0, lb + (ub - lb) * RAND()))
  FROM w
));
EOF

echo "✓ UDFs deployed"
echo ""

# Phase 2: Tables
echo "Phase 2: Deploying Tables..."

# Use bq mk for tables (safer than query for complex DDL)
echo "Creating caption_bandit_stats..."
bq mk --table \
  --project_id="$PROJECT" \
  --time_partitioning_field=last_updated \
  --time_partitioning_type=DAY \
  --clustering_fields=page_name,caption_id,last_used \
  --description="Caption performance statistics for Thompson sampling algorithm" \
  --label=system:eros \
  --label=component:caption_selection \
  --force \
  "${PROJECT}:${DATASET}.caption_bandit_stats" \
  caption_id:INTEGER,page_name:STRING,successes:INTEGER,failures:INTEGER,total_observations:INTEGER,total_revenue:FLOAT,avg_conversion_rate:FLOAT,avg_emv:FLOAT,last_emv_observed:FLOAT,confidence_lower_bound:FLOAT,confidence_upper_bound:FLOAT,exploration_score:FLOAT,last_used:TIMESTAMP,last_updated:TIMESTAMP,performance_percentile:INTEGER

echo "Creating holiday_calendar..."
bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
CREATE OR REPLACE TABLE `of-scheduler-proj.eros_scheduling_brain.holiday_calendar` (
  holiday_date DATE NOT NULL,
  holiday_name STRING NOT NULL,
  holiday_type STRING,
  is_major_holiday BOOL,
  saturation_impact_factor FLOAT64
)
PARTITION BY DATE_TRUNC(holiday_date, YEAR)
OPTIONS(
  description = 'US holiday calendar for scheduling and saturation analysis',
  labels = [("system", "eros"), ("component", "scheduling")]
);
EOF

echo "Creating schedule_export_log..."
bq mk --table \
  --project_id="$PROJECT" \
  --time_partitioning_field=export_timestamp \
  --time_partitioning_type=DAY \
  --clustering_fields=page_name,status \
  --description="Audit log for schedule generation and export operations" \
  --label=system:eros \
  --label=component:telemetry \
  --force \
  "${PROJECT}:${DATASET}.schedule_export_log" \
  schedule_id:STRING,page_name:STRING,export_timestamp:TIMESTAMP,message_count:INTEGER,execution_time_seconds:FLOAT,status:STRING,error_message:STRING,export_format:STRING,exported_by:STRING

echo "✓ Tables created"
echo ""

# Phase 3: Seed holiday data
echo "Phase 3: Seeding holiday calendar..."
bq query --project_id="$PROJECT" --use_legacy_sql=false <<'EOF'
MERGE `of-scheduler-proj.eros_scheduling_brain.holiday_calendar` AS target
USING (
  SELECT
    PARSE_DATE('%Y-%m-%d', holiday_date_str) AS holiday_date,
    holiday_name,
    holiday_type,
    is_major_holiday,
    saturation_impact_factor
  FROM UNNEST([
    STRUCT('2025-01-01' AS holiday_date_str, 'New Year Day' AS holiday_name, 'FEDERAL' AS holiday_type, TRUE AS is_major_holiday, 0.7 AS saturation_impact_factor),
    STRUCT('2025-01-20', 'Martin Luther King Jr Day', 'FEDERAL', FALSE, 1.0),
    STRUCT('2025-02-14', 'Valentine Day', 'COMMERCIAL', TRUE, 0.8),
    STRUCT('2025-02-17', 'Presidents Day', 'FEDERAL', FALSE, 1.0),
    STRUCT('2025-03-17', 'St Patrick Day', 'CULTURAL', FALSE, 1.0),
    STRUCT('2025-04-20', 'Easter Sunday', 'CULTURAL', TRUE, 0.8),
    STRUCT('2025-05-11', 'Mother Day', 'COMMERCIAL', TRUE, 0.8),
    STRUCT('2025-05-26', 'Memorial Day', 'FEDERAL', TRUE, 0.8),
    STRUCT('2025-06-15', 'Father Day', 'COMMERCIAL', FALSE, 0.9),
    STRUCT('2025-06-19', 'Juneteenth', 'FEDERAL', FALSE, 1.0),
    STRUCT('2025-07-04', 'Independence Day', 'FEDERAL', TRUE, 0.7),
    STRUCT('2025-09-01', 'Labor Day', 'FEDERAL', TRUE, 0.8),
    STRUCT('2025-10-13', 'Columbus Day', 'FEDERAL', FALSE, 1.0),
    STRUCT('2025-10-31', 'Halloween', 'CULTURAL', FALSE, 0.9),
    STRUCT('2025-11-11', 'Veterans Day', 'FEDERAL', FALSE, 1.0),
    STRUCT('2025-11-27', 'Thanksgiving', 'FEDERAL', TRUE, 0.7),
    STRUCT('2025-11-28', 'Black Friday', 'COMMERCIAL', FALSE, 0.9),
    STRUCT('2025-12-24', 'Christmas Eve', 'CULTURAL', TRUE, 0.7),
    STRUCT('2025-12-25', 'Christmas Day', 'FEDERAL', TRUE, 0.6),
    STRUCT('2025-12-31', 'New Year Eve', 'CULTURAL', TRUE, 0.7)
  ])
) AS source
ON target.holiday_date = source.holiday_date
WHEN NOT MATCHED THEN
  INSERT (holiday_date, holiday_name, holiday_type, is_major_holiday, saturation_impact_factor)
  VALUES (source.holiday_date, source.holiday_name, source.holiday_type, source.is_major_holiday, source.saturation_impact_factor);
EOF

echo "✓ Holiday calendar seeded with 20 holidays"
echo ""

echo "==================================================================="
echo "INFRASTRUCTURE DEPLOYMENT COMPLETE"
echo "==================================================================="
echo ""
echo "Deployed:"
echo "  ✓ 4 UDFs"
echo "  ✓ 3 Tables (partitioned and clustered)"
echo "  ✓ 20 holidays seeded"
echo ""
echo "Next: Deploy stored procedures using PRODUCTION_INFRASTRUCTURE.sql"
echo "      (procedures require separate deployment due to complexity)"
echo ""
