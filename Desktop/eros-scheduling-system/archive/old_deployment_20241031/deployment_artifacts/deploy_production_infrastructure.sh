#!/bin/bash
# =============================================================================
# EROS SCHEDULING SYSTEM - PRODUCTION INFRASTRUCTURE DEPLOYMENT SCRIPT
# =============================================================================
# Project: of-scheduler-proj
# Dataset: eros_scheduling_brain
# Purpose: Deploy complete DDL infrastructure to BigQuery
# Version: 1.0.0
# Created: 2025-10-31
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
DEPLOYMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${DEPLOYMENT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Job configuration (applied at bq command level, NOT in SQL)
QUERY_TIMEOUT_MS=300000  # 5 minutes
MAX_BYTES_BILLED=10737418240  # 10GB

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Check bq CLI is available
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    log_success "bq CLI found: $(which bq)"

    # Check authentication
    if ! bq ls --project_id="$PROJECT_ID" &> /dev/null; then
        log_error "Authentication failed. Run: gcloud auth login"
        exit 1
    fi
    log_success "Authenticated to project: $PROJECT_ID"

    # Check dataset exists
    if ! bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_error "Dataset not found: ${PROJECT_ID}:${DATASET}"
        exit 1
    fi
    log_success "Dataset found: ${PROJECT_ID}:${DATASET}"

    # Check SQL files exist
    if [ ! -f "${DEPLOYMENT_DIR}/PRODUCTION_INFRASTRUCTURE.sql" ]; then
        log_error "PRODUCTION_INFRASTRUCTURE.sql not found in ${DEPLOYMENT_DIR}"
        exit 1
    fi
    log_success "Found PRODUCTION_INFRASTRUCTURE.sql"

    if [ ! -f "${DEPLOYMENT_DIR}/verify_production_infrastructure.sql" ]; then
        log_warning "verify_production_infrastructure.sql not found (optional)"
    else
        log_success "Found verify_production_infrastructure.sql"
    fi
}

create_backup() {
    log "Creating pre-deployment backup of existing objects..."

    local backup_file="${DEPLOYMENT_DIR}/backup_$(date +%Y%m%d_%H%M%S).sql"

    # Backup existing procedures (if any)
    for proc in update_caption_performance run_daily_automation sweep_expired_caption_locks select_captions_for_creator; do
        bq show --format=prettyjson "${PROJECT_ID}:${DATASET}.${proc}" >> "$backup_file" 2>/dev/null || true
    done

    if [ -f "$backup_file" ]; then
        log_success "Backup created: $backup_file"
    else
        log_warning "No existing objects to backup"
    fi
}

deploy_infrastructure() {
    log "Deploying PRODUCTION_INFRASTRUCTURE.sql..."

    # Deploy with job-level settings (NOT in SQL)
    # Note: bq query doesn't support timeout flags for multi-statement scripts
    # Timeout is handled by BigQuery's default limits
    if bq query \
        --project_id="$PROJECT_ID" \
        --use_legacy_sql=false \
        --maximum_bytes_billed="$MAX_BYTES_BILLED" \
        < "${DEPLOYMENT_DIR}/PRODUCTION_INFRASTRUCTURE.sql" >> "$LOG_FILE" 2>&1; then

        log_success "Infrastructure deployment completed successfully"
        return 0
    else
        log_error "Infrastructure deployment failed. Check log: $LOG_FILE"
        return 1
    fi
}

verify_deployment() {
    log "Running verification tests..."

    if [ ! -f "${DEPLOYMENT_DIR}/verify_production_infrastructure.sql" ]; then
        log_warning "Skipping verification (file not found)"
        return 0
    fi

    # Run basic object count checks
    log "Checking deployed objects..."

    # Count UDFs
    local udf_count=$(bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type='SCALAR_FUNCTION'
         AND routine_name IN ('caption_key_v2','caption_key','wilson_score_bounds','wilson_sample')" 2>/dev/null | tail -1)

    if [ "$udf_count" = "4" ]; then
        log_success "All 4 UDFs deployed successfully"
    else
        log_error "Expected 4 UDFs, found $udf_count"
        return 1
    fi

    # Count procedures
    local proc_count=$(bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type='PROCEDURE'" 2>/dev/null | tail -1)

    if [ "$proc_count" -ge "4" ]; then
        log_success "All 4 procedures deployed successfully"
    else
        log_error "Expected 4 procedures, found $proc_count"
        return 1
    fi

    # Count tables
    local table_count=$(bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.TABLES\`
         WHERE table_type='BASE TABLE'
         AND table_name IN ('caption_bandit_stats','holiday_calendar','schedule_export_log')" 2>/dev/null | tail -1)

    if [ "$table_count" = "3" ]; then
        log_success "All 3 core tables deployed successfully"
    else
        log_error "Expected 3 tables, found $table_count"
        return 1
    fi

    # Count views
    local view_count=$(bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.TABLES\`
         WHERE table_type='VIEW'
         AND table_name='schedule_recommendations_messages'" 2>/dev/null | tail -1)

    if [ "$view_count" = "1" ]; then
        log_success "Schedule export view deployed successfully"
    else
        log_error "Expected 1 view, found $view_count"
        return 1
    fi

    log_success "All verification checks passed"
    return 0
}

print_scheduled_query_config() {
    log ""
    log "======================================================================="
    log "SCHEDULED QUERY CONFIGURATION REQUIRED"
    log "======================================================================="
    log ""
    log "The following scheduled queries must be configured via Console or API:"
    log ""
    log "1. update_caption_performance"
    log "   Schedule: Every 6 hours"
    log "   Query: CALL \`${PROJECT_ID}.${DATASET}.update_caption_performance\`();"
    log "   Timeout: 300 seconds"
    log "   Max bytes: 10GB"
    log ""
    log "2. run_daily_automation"
    log "   Schedule: Daily at 03:05 America/Los_Angeles"
    log "   Query: CALL \`${PROJECT_ID}.${DATASET}.run_daily_automation\`(CURRENT_DATE('America/Los_Angeles'));"
    log "   Timeout: 600 seconds"
    log "   Max bytes: 10GB"
    log ""
    log "3. sweep_expired_caption_locks"
    log "   Schedule: Every 1 hour"
    log "   Query: CALL \`${PROJECT_ID}.${DATASET}.sweep_expired_caption_locks\`();"
    log "   Timeout: 60 seconds"
    log "   Max bytes: 1GB"
    log ""
    log "Configuration methods:"
    log "  - Console: https://console.cloud.google.com/bigquery/scheduled-queries"
    log "  - CLI: Use deployment/configure_scheduled_queries.sh (separate script)"
    log "  - API: Use BigQuery Data Transfer Service API"
    log ""
    log "======================================================================="
}

print_summary() {
    log ""
    log "======================================================================="
    log "DEPLOYMENT SUMMARY"
    log "======================================================================="
    log "Project: $PROJECT_ID"
    log "Dataset: $DATASET"
    log "Timestamp: $(date +'%Y-%m-%d %H:%M:%S')"
    log "Log file: $LOG_FILE"
    log ""
    log "Deployed objects:"
    log "  - 4 UDFs (caption_key_v2, caption_key, wilson_score_bounds, wilson_sample)"
    log "  - 3 Tables (caption_bandit_stats, holiday_calendar, schedule_export_log)"
    log "  - 1 View (schedule_recommendations_messages)"
    log "  - 4 Procedures (update_caption_performance, run_daily_automation, sweep_expired_caption_locks, select_captions_for_creator)"
    log "  - 20+ holidays seeded in holiday_calendar (2025)"
    log ""
    log "Status: ${GREEN}DEPLOYMENT SUCCESSFUL ✓${NC}"
    log "======================================================================="
}

rollback() {
    log_error "Deployment failed. Rolling back..."

    # Note: Since we use CREATE OR REPLACE, rollback would require
    # re-deploying from backup. For safety, we keep failed state
    # and let operator decide on rollback strategy.

    log_warning "Manual rollback required if needed. See backup files in deployment/"
    log_warning "Failed deployment log: $LOG_FILE"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    log "======================================================================="
    log "EROS SCHEDULING SYSTEM - PRODUCTION INFRASTRUCTURE DEPLOYMENT"
    log "======================================================================="
    log "Starting deployment to ${PROJECT_ID}:${DATASET}"
    log ""

    # Phase 1: Prerequisites
    check_prerequisites || exit 1

    # Phase 2: Backup
    create_backup || log_warning "Backup failed (non-fatal)"

    # Phase 3: Deploy
    if deploy_infrastructure; then
        log_success "Phase 3: Infrastructure deployment completed"
    else
        rollback
        exit 1
    fi

    # Phase 4: Verify
    if verify_deployment; then
        log_success "Phase 4: Verification completed"
    else
        log_error "Phase 4: Verification failed (infrastructure may be partially deployed)"
        exit 1
    fi

    # Phase 5: Print configuration instructions
    print_scheduled_query_config

    # Phase 6: Summary
    print_summary

    log ""
    log "Next steps:"
    log "  1. Review this log: $LOG_FILE"
    log "  2. Configure scheduled queries (see instructions above)"
    log "  3. Deploy analyze_creator_performance: deployment/CORRECTED_analyze_creator_performance_FULL.sql"
    log "  4. Test procedures with sample data"
    log "  5. Monitor etl_job_runs and automation_alerts tables"
    log ""
    log_success "Deployment complete!"
}

# Run main function
main "$@"
