#!/usr/bin/env bash
set -euo pipefail
: "${PAGE_NAME:?PAGE_NAME not set}"
: "${SCHEDULE_ID:?SCHEDULE_ID not set}"
PROJECT_ID="${PROJECT_ID:-of-scheduler-proj}"
DATASET="${DATASET:-eros_scheduling_brain}"
LOCATION="${LOCATION:-US}"
MIN_GAP_MINUTES="${MIN_GAP_MINUTES:-90}"
SQL_FILE="${1:?SQL file required}"
bq query --nouse_legacy_sql \
  --project_id="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --parameter=page_name:STRING:"${PAGE_NAME}" \
  --parameter=schedule_id:STRING:"${SCHEDULE_ID}" \
  --parameter=minimum_gap_minutes:INT64:"${MIN_GAP_MINUTES}" \
  < "${SQL_FILE}"
