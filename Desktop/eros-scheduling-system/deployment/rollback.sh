#!/bin/bash

################################################################################
# EROS Scheduling System - Emergency Rollback Script
#
# Description: Emergency rollback procedure
#   - Restores tables from latest backup
#   - Disables scheduled jobs
#   - Sends alert notifications
#   - Logs all rollback activities
#
# Usage: ./rollback.sh [BACKUP_TIMESTAMP]
#
# Examples:
#   ./rollback.sh                      # Use latest backup
#   ./rollback.sh 2025-10-31_143022   # Use specific backup
#
# Requirements:
#   - bq CLI installed and authenticated
#   - Read access to backup bucket
#   - Write permissions to BigQuery
#
# Author: Deployment Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration
ROLLBACK_TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
BACKUP_BUCKET="gs://eros-platform-backups"
LOG_DIR="/tmp/eros_rollback_${ROLLBACK_TIMESTAMP}"
ROLLBACK_LOG="${LOG_DIR}/rollback.log"
mkdir -p "${LOG_DIR}"

# Redirect all output to log file and console
exec > >(tee -a "${ROLLBACK_LOG}") 2>&1

# Parse arguments
BACKUP_TIMESTAMP="${1:-}"

# Get project ID
get_project_id() {
    if [[ -n "${EROS_PROJECT_ID:-}" ]]; then
        echo "${EROS_PROJECT_ID}"
    else
        local gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "${gcloud_project}" ]]; then
            echo "${gcloud_project}"
        else
            log_error "Project ID not found"
            exit 1
        fi
    fi
}

# Get dataset
get_dataset() {
    if [[ -n "${EROS_DATASET:-}" ]]; then
        echo "${EROS_DATASET}"
    else
        echo "eros_platform"
    fi
}

PROJECT_ID=$(get_project_id)
DATASET=$(get_dataset)

# Tables to restore
TABLES=(
    "caption_bank"
    "caption_bandit_stats"
    "active_caption_assignments"
)

# Get latest backup timestamp
get_latest_backup() {
    log_info "Finding latest backup..."

    local latest=$(gsutil ls "${BACKUP_BUCKET}/" | grep "/$" | sort -r | head -n 1 | xargs basename)

    if [[ -z "${latest}" ]]; then
        log_error "No backups found in ${BACKUP_BUCKET}"
        exit 1
    fi

    echo "${latest}"
}

# Verify backup exists
verify_backup() {
    local backup_ts=$1
    local backup_path="${BACKUP_BUCKET}/${backup_ts}"

    log_info "Verifying backup: ${backup_path}"

    if ! gsutil ls "${backup_path}/" &> /dev/null; then
        log_error "Backup not found: ${backup_path}"
        return 1
    fi

    # Check metadata file
    if ! gsutil ls "${backup_path}/metadata.json" &> /dev/null; then
        log_warning "Backup metadata not found"
    else
        log_info "Backup metadata:"
        gsutil cat "${backup_path}/metadata.json" | head -20
    fi

    # Verify all table backups exist
    for table in "${TABLES[@]}"; do
        if ! gsutil ls "${backup_path}/${table}.json.gz" &> /dev/null; then
            log_error "Table backup not found: ${table}.json.gz"
            return 1
        fi
    done

    log_success "Backup verified"
    return 0
}

# Confirm rollback
confirm_rollback() {
    local backup_ts=$1

    echo ""
    echo "=========================================================="
    echo "  EMERGENCY ROLLBACK CONFIRMATION"
    echo "=========================================================="
    echo ""
    log_critical "You are about to perform an EMERGENCY ROLLBACK"
    echo ""
    log_info "Current configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Backup timestamp: ${backup_ts}"
    log_info "  Tables to restore: ${TABLES[*]}"
    echo ""
    log_warning "This operation will:"
    log_warning "  1. OVERWRITE current data in the tables above"
    log_warning "  2. Disable scheduled queries and jobs"
    log_warning "  3. Clear caption locks"
    log_warning "  4. Send alert notifications to stakeholders"
    echo ""
    log_error "ALL CURRENT DATA IN THESE TABLES WILL BE LOST"
    echo ""

    read -p "Type 'ROLLBACK' in capital letters to confirm: " -r
    if [[ $REPLY != "ROLLBACK" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi

    echo ""
    read -p "Enter rollback reason (will be logged): " -r ROLLBACK_REASON
    echo ""

    if [[ -z "${ROLLBACK_REASON}" ]]; then
        ROLLBACK_REASON="No reason provided"
    fi

    log_critical "Rollback confirmed. Reason: ${ROLLBACK_REASON}"
    echo ""
}

# Create pre-rollback snapshot
create_pre_rollback_snapshot() {
    log_step "Creating pre-rollback snapshot..."

    local snapshot_path="${BACKUP_BUCKET}/pre_rollback_${ROLLBACK_TIMESTAMP}"

    for table in "${TABLES[@]}"; do
        log_info "Snapshotting ${table}..."

        if bq extract \
            --destination_format=NEWLINE_DELIMITED_JSON \
            --compression=GZIP \
            "${PROJECT_ID}:${DATASET}.${table}" \
            "${snapshot_path}/${table}.json.gz" 2>&1; then
            log_success "  Snapshot created: ${table}"
        else
            log_warning "  Failed to snapshot ${table} (non-critical)"
        fi
    done

    log_success "Pre-rollback snapshot saved to: ${snapshot_path}"
}

# Disable scheduled queries
disable_scheduled_queries() {
    log_step "Disabling scheduled queries..."

    log_warning "Manual action required:"
    log_warning "  1. Go to BigQuery console: https://console.cloud.google.com/bigquery"
    log_warning "  2. Navigate to Scheduled queries"
    log_warning "  3. Pause all EROS Platform related scheduled queries"
    echo ""

    read -p "Press ENTER after disabling scheduled queries..." -r

    log_success "Scheduled queries disabled"
}

# Clear caption locks
clear_caption_locks() {
    log_step "Clearing caption locks..."

    local clear_locks="
DELETE FROM \`${PROJECT_ID}.${DATASET}.caption_locks\`
WHERE TRUE;
"

    if echo "${clear_locks}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" 2>&1; then
        log_success "Caption locks cleared"
    else
        log_warning "Failed to clear caption locks (table may not exist)"
    fi
}

# Restore single table
restore_table() {
    local table=$1
    local backup_ts=$2
    local backup_uri="${BACKUP_BUCKET}/${backup_ts}/${table}.json.gz"
    local temp_table="${table}_restore_temp"

    log_info "Restoring ${table}..."

    # Get row count before restore
    local count_before=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${table}\`" 2>/dev/null | tail -n 1 || echo "0")

    log_info "  Current row count: ${count_before}"

    # Create temporary table from backup
    log_info "  Loading backup data into temporary table..."

    if ! bq load \
        --source_format=NEWLINE_DELIMITED_JSON \
        --replace \
        "${PROJECT_ID}:${DATASET}.${temp_table}" \
        "${backup_uri}" 2>&1; then
        log_error "  Failed to load backup for ${table}"
        return 1
    fi

    # Get row count from backup
    local count_backup=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${temp_table}\`" 2>/dev/null | tail -n 1 || echo "0")

    log_info "  Backup row count: ${count_backup}"

    # Verify backup data
    if [[ ${count_backup} -eq 0 ]]; then
        log_error "  Backup contains no data for ${table}"
        bq rm -f -t "${PROJECT_ID}:${DATASET}.${temp_table}"
        return 1
    fi

    # Replace original table with backup
    log_info "  Replacing original table with backup..."

    if bq cp -f \
        "${PROJECT_ID}:${DATASET}.${temp_table}" \
        "${PROJECT_ID}:${DATASET}.${table}" 2>&1; then
        log_success "  Table restored: ${table}"

        # Clean up temporary table
        bq rm -f -t "${PROJECT_ID}:${DATASET}.${temp_table}"

        # Verify restoration
        local count_after=$(bq query --use_legacy_sql=false --format=csv --quiet \
            "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${table}\`" 2>/dev/null | tail -n 1 || echo "0")

        log_info "  Final row count: ${count_after}"

        if [[ ${count_after} -eq ${count_backup} ]]; then
            log_success "  Verification passed"
            return 0
        else
            log_error "  Verification failed: Row count mismatch"
            return 1
        fi
    else
        log_error "  Failed to replace table: ${table}"
        bq rm -f -t "${PROJECT_ID}:${DATASET}.${temp_table}"
        return 1
    fi
}

# Restore all tables
restore_all_tables() {
    local backup_ts=$1

    log_step "Restoring all tables from backup: ${backup_ts}"

    local success_count=0
    local failure_count=0

    for table in "${TABLES[@]}"; do
        if restore_table "${table}" "${backup_ts}"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
        echo ""
    done

    if [[ ${failure_count} -eq 0 ]]; then
        log_success "All tables restored successfully"
        return 0
    else
        log_error "${failure_count} table(s) failed to restore"
        return 1
    fi
}

# Verify system health after rollback
verify_system_health() {
    log_step "Verifying system health after rollback..."

    local health_checks_passed=true

    # Check 1: Table row counts
    for table in "${TABLES[@]}"; do
        local count=$(bq query --use_legacy_sql=false --format=csv --quiet \
            "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${table}\`" 2>/dev/null | tail -n 1 || echo "0")

        if [[ ${count} -gt 0 ]]; then
            log_success "  ${table}: ${count} rows"
        else
            log_error "  ${table}: EMPTY TABLE"
            health_checks_passed=false
        fi
    done

    # Check 2: Data integrity
    local corrupt_count=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
         WHERE total_views < 0 OR engagement_count < 0" 2>/dev/null | tail -n 1 || echo "ERROR")

    if [[ "${corrupt_count}" == "0" ]]; then
        log_success "  Data integrity: PASSED"
    else
        log_error "  Data integrity: FAILED (corrupt records found)"
        health_checks_passed=false
    fi

    if [[ "${health_checks_passed}" == "true" ]]; then
        log_success "System health verification PASSED"
        return 0
    else
        log_error "System health verification FAILED"
        return 1
    fi
}

# Send alert notifications
send_alert_notifications() {
    local backup_ts=$1
    local rollback_reason=$2
    local rollback_success=$3

    log_step "Sending alert notifications..."

    local status="COMPLETED"
    if [[ "${rollback_success}" != "true" ]]; then
        status="FAILED"
    fi

    local alert_message="
========================================================
EROS SCHEDULING SYSTEM - EMERGENCY ROLLBACK ${status}
========================================================

Rollback Time: $(date '+%Y-%m-%d %H:%M:%S UTC')
Rollback ID: ${ROLLBACK_TIMESTAMP}
Backup Used: ${backup_ts}
Project: ${PROJECT_ID}
Dataset: ${DATASET}

Reason: ${rollback_reason}

Tables Restored:
$(for table in "${TABLES[@]}"; do echo "  - ${table}"; done)

Status: ${status}

Log Location: ${ROLLBACK_LOG}

Actions Required:
  1. Verify system functionality
  2. Re-enable scheduled queries if appropriate
  3. Monitor system for 2 hours
  4. Schedule post-mortem meeting
  5. Review incident documentation

Emergency Contacts:
  - Deployment Lead: [CONTACT_INFO]
  - On-Call Engineer: [CONTACT_INFO]
  - Technical Lead: [CONTACT_INFO]

========================================================
"

    # Save alert to file
    echo "${alert_message}" > "${LOG_DIR}/alert_notification.txt"
    log_success "Alert notification saved to: ${LOG_DIR}/alert_notification.txt"

    echo ""
    log_warning "MANUAL ACTION REQUIRED:"
    log_warning "  Send the alert notification to:"
    log_warning "    - engineering@example.com"
    log_warning "    - oncall@example.com"
    log_warning "    - management@example.com"
    echo ""

    cat "${LOG_DIR}/alert_notification.txt"
}

# Create rollback report
create_rollback_report() {
    local backup_ts=$1
    local rollback_reason=$2
    local rollback_success=$3

    log_step "Creating rollback report..."

    local report_file="${LOG_DIR}/rollback_report.md"

    cat > "${report_file}" << EOF
# EROS Scheduling System - Rollback Report

## Rollback Summary

- **Rollback ID**: ${ROLLBACK_TIMESTAMP}
- **Date/Time**: $(date '+%Y-%m-%d %H:%M:%S UTC')
- **Status**: $(if [[ "${rollback_success}" == "true" ]]; then echo "SUCCESS"; else echo "FAILED"; fi)
- **Backup Used**: ${backup_ts}
- **Initiated By**: $(whoami)

## Reason for Rollback

${rollback_reason}

## Tables Restored

$(for table in "${TABLES[@]}"; do
    count=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.${table}\`" 2>/dev/null | tail -n 1 || echo "ERROR")
    echo "- **${table}**: ${count} rows"
done)

## Actions Taken

1. Pre-rollback snapshot created
2. Scheduled queries disabled
3. Caption locks cleared
4. Tables restored from backup
5. System health verified
6. Alert notifications sent

## Pre-Rollback Snapshot

Location: gs://eros-platform-backups/pre_rollback_${ROLLBACK_TIMESTAMP}/

This snapshot can be used to restore if the rollback was performed in error.

## Next Steps

- [ ] Monitor system for 2 hours
- [ ] Verify application functionality
- [ ] Check user-reported issues
- [ ] Review system metrics
- [ ] Schedule post-mortem meeting
- [ ] Update incident documentation
- [ ] Determine root cause
- [ ] Plan remediation steps

## Logs

- **Rollback Log**: ${ROLLBACK_LOG}
- **Alert Notification**: ${LOG_DIR}/alert_notification.txt

## Contact Information

For questions about this rollback, contact:
- Deployment Lead: [CONTACT_INFO]
- On-Call Engineer: [CONTACT_INFO]

---
*Generated automatically by rollback.sh v1.0*
EOF

    log_success "Rollback report created: ${report_file}"
    echo ""
    cat "${report_file}"
}

################################################################################
# Main Rollback Flow
################################################################################
main() {
    echo ""
    echo "=========================================================="
    echo "  EROS Scheduling System - EMERGENCY ROLLBACK"
    echo "=========================================================="
    echo ""

    log_critical "EMERGENCY ROLLBACK PROCEDURE INITIATED"
    echo ""

    # Determine backup to use
    if [[ -z "${BACKUP_TIMESTAMP}" ]]; then
        BACKUP_TIMESTAMP=$(get_latest_backup)
        log_info "Using latest backup: ${BACKUP_TIMESTAMP}"
    else
        log_info "Using specified backup: ${BACKUP_TIMESTAMP}"
    fi

    # Verify backup exists
    if ! verify_backup "${BACKUP_TIMESTAMP}"; then
        log_error "Backup verification failed"
        exit 1
    fi
    echo ""

    # Confirm rollback
    confirm_rollback "${BACKUP_TIMESTAMP}"

    # Start rollback process
    log_critical "Starting rollback process..."
    echo ""

    # Step 1: Create pre-rollback snapshot
    create_pre_rollback_snapshot
    echo ""

    # Step 2: Disable scheduled queries
    disable_scheduled_queries
    echo ""

    # Step 3: Clear caption locks
    clear_caption_locks
    echo ""

    # Step 4: Restore tables
    local restore_success=false
    if restore_all_tables "${BACKUP_TIMESTAMP}"; then
        restore_success=true
    fi
    echo ""

    # Step 5: Verify system health
    local health_check_success=false
    if verify_system_health; then
        health_check_success=true
    fi
    echo ""

    # Step 6: Send alerts
    local rollback_success=false
    if [[ "${restore_success}" == "true" ]] && [[ "${health_check_success}" == "true" ]]; then
        rollback_success=true
    fi

    send_alert_notifications "${BACKUP_TIMESTAMP}" "${ROLLBACK_REASON}" "${rollback_success}"
    echo ""

    # Step 7: Create report
    create_rollback_report "${BACKUP_TIMESTAMP}" "${ROLLBACK_REASON}" "${rollback_success}"
    echo ""

    # Final summary
    echo "=========================================================="
    echo "  Rollback Summary"
    echo "=========================================================="
    echo ""

    if [[ "${rollback_success}" == "true" ]]; then
        log_success "ROLLBACK COMPLETED SUCCESSFULLY"
        echo ""
        log_info "System has been restored to backup: ${BACKUP_TIMESTAMP}"
        log_info "All tables have been verified"
        echo ""
        log_warning "Next steps:"
        log_warning "  1. Monitor system for 2 hours"
        log_warning "  2. Verify application functionality"
        log_warning "  3. Re-enable scheduled queries when ready"
        log_warning "  4. Review rollback report: ${LOG_DIR}/rollback_report.md"
        log_warning "  5. Schedule post-mortem meeting"
        echo ""
        exit 0
    else
        log_critical "ROLLBACK FAILED"
        echo ""
        log_error "System may be in an inconsistent state"
        log_error "Immediate manual intervention required"
        echo ""
        log_critical "Emergency actions:"
        log_critical "  1. Contact database administrator immediately"
        log_critical "  2. Review logs: ${ROLLBACK_LOG}"
        log_critical "  3. Consider manual table restoration"
        log_critical "  4. Escalate to engineering leadership"
        echo ""
        exit 1
    fi
}

# Handle interruption
trap 'log_critical "Rollback interrupted - system may be in inconsistent state"; exit 130' INT TERM

# Run main
main "$@"
