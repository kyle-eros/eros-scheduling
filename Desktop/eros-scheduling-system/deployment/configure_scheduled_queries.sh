#!/bin/bash
# =============================================================================
# SCHEDULED QUERY CONFIGURATION SCRIPT
# =============================================================================
# Project: of-scheduler-proj
# Dataset: eros_scheduling_brain
# Purpose: Configure scheduled queries via bq CLI
# Version: 1.0.0
# =============================================================================

set -euo pipefail

PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
LOCATION="US"

echo "======================================================================="
echo "CONFIGURING SCHEDULED QUERIES"
echo "======================================================================="
echo ""

# =============================================================================
# SCHEDULED QUERY 1: update_caption_performance (Every 6 hours)
# =============================================================================
echo "Configuring: update_caption_performance (every 6 hours)"
bq mk \
  --transfer_config \
  --project_id="$PROJECT_ID" \
  --data_source=scheduled_query \
  --display_name="EROS - Update Caption Performance" \
  --target_dataset="$DATASET" \
  --schedule="every 6 hours" \
  --params='{
    "query":"CALL `'"$PROJECT_ID"'.'"$DATASET"'.update_caption_performance`();",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND",
    "partitioning_field":"",
    "time_partitioning_type":"DAY"
  }' \
  --location="$LOCATION"

echo "✓ update_caption_performance scheduled"
echo ""

# =============================================================================
# SCHEDULED QUERY 2: run_daily_automation (Daily at 03:05 LA time)
# =============================================================================
echo "Configuring: run_daily_automation (daily at 03:05 America/Los_Angeles)"
bq mk \
  --transfer_config \
  --project_id="$PROJECT_ID" \
  --data_source=scheduled_query \
  --display_name="EROS - Daily Automation" \
  --target_dataset="$DATASET" \
  --schedule="every day 03:05" \
  --schedule_timezone="America/Los_Angeles" \
  --params='{
    "query":"CALL `'"$PROJECT_ID"'.'"$DATASET"'.run_daily_automation`(CURRENT_DATE(\"America/Los_Angeles\"));",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND",
    "partitioning_field":"",
    "time_partitioning_type":"DAY"
  }' \
  --location="$LOCATION"

echo "✓ run_daily_automation scheduled"
echo ""

# =============================================================================
# SCHEDULED QUERY 3: sweep_expired_caption_locks (Hourly)
# =============================================================================
echo "Configuring: sweep_expired_caption_locks (every 1 hour)"
bq mk \
  --transfer_config \
  --project_id="$PROJECT_ID" \
  --data_source=scheduled_query \
  --display_name="EROS - Sweep Expired Caption Locks" \
  --target_dataset="$DATASET" \
  --schedule="every 1 hours" \
  --params='{
    "query":"CALL `'"$PROJECT_ID"'.'"$DATASET"'.sweep_expired_caption_locks`();",
    "destination_table_name_template":"",
    "write_disposition":"WRITE_APPEND",
    "partitioning_field":"",
    "time_partitioning_type":"DAY"
  }' \
  --location="$LOCATION"

echo "✓ sweep_expired_caption_locks scheduled"
echo ""

# =============================================================================
# VERIFICATION
# =============================================================================
echo "======================================================================="
echo "Listing all scheduled queries for project..."
echo "======================================================================="
bq ls --transfer_config --project_id="$PROJECT_ID" --data_source=scheduled_query

echo ""
echo "======================================================================="
echo "SCHEDULED QUERIES CONFIGURED SUCCESSFULLY"
echo "======================================================================="
echo ""
echo "To manage scheduled queries:"
echo "  List:    bq ls --transfer_config --project_id=$PROJECT_ID --data_source=scheduled_query"
echo "  Update:  bq update --transfer_config [CONFIG_ID] --schedule='new schedule'"
echo "  Delete:  bq rm --transfer_config [CONFIG_ID]"
echo "  Console: https://console.cloud.google.com/bigquery/scheduled-queries?project=$PROJECT_ID"
echo ""
