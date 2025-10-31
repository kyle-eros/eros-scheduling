#!/bin/bash
# =============================================================================
# ROLLBACK SCRIPT FOR PRODUCTION INFRASTRUCTURE
# =============================================================================
# Project: of-scheduler-proj
# Dataset: eros_scheduling_brain
# Purpose: Rollback infrastructure deployment by dropping objects
# WARNING: This will DELETE all deployed objects. Use with caution!
# =============================================================================

set -euo pipefail

PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"

echo "======================================================================="
echo "ROLLBACK WARNING"
echo "======================================================================="
echo "This will DELETE the following objects from ${PROJECT_ID}:${DATASET}:"
echo "  - 4 UDFs"
echo "  - 4 Stored Procedures"
echo "  - 3 Tables (DATA WILL BE LOST)"
echo "  - 1 View"
echo ""
read -p "Are you sure you want to proceed? (type 'ROLLBACK' to confirm): " confirm

if [ "$confirm" != "ROLLBACK" ]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo "Starting rollback..."

# Drop procedures (in dependency order)
echo "Dropping procedures..."
bq rm -f --routine "${PROJECT_ID}:${DATASET}.select_captions_for_creator" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.sweep_expired_caption_locks" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.run_daily_automation" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.update_caption_performance" || true

# Drop view
echo "Dropping view..."
bq rm -f --table "${PROJECT_ID}:${DATASET}.schedule_recommendations_messages" || true

# Drop tables (WARNING: DATA LOSS)
echo "Dropping tables..."
bq rm -f --table "${PROJECT_ID}:${DATASET}.schedule_export_log" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.holiday_calendar" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.caption_bandit_stats" || true

# Drop supporting tables that may have been created by procedures
echo "Dropping procedure-created tables..."
bq rm -f --table "${PROJECT_ID}:${DATASET}.etl_job_runs" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.creator_processing_errors" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.schedule_generation_queue" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.automation_alerts" || true
bq rm -f --table "${PROJECT_ID}:${DATASET}.lock_sweep_log" || true

# Drop UDFs
echo "Dropping UDFs..."
bq rm -f --routine "${PROJECT_ID}:${DATASET}.wilson_sample" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.wilson_score_bounds" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.caption_key" || true
bq rm -f --routine "${PROJECT_ID}:${DATASET}.caption_key_v2" || true

echo ""
echo "======================================================================="
echo "ROLLBACK COMPLETE"
echo "======================================================================="
echo "All infrastructure objects have been removed from ${PROJECT_ID}:${DATASET}"
echo ""
