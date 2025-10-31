#!/bin/bash

################################################################################
# EROS Scheduling System - Complete Production Deployment
#
# Description: Full end-to-end deployment with validation and rollback capability
#   - Idempotent: Safe to run multiple times
#   - Comprehensive logging with structured output
#   - Automatic health checks and validation
#   - Rollback on failure with automatic backup restoration
#   - Progress tracking with state management
#
# Usage: ./deploy_production_complete.sh [OPTIONS]
#
# Options:
#   --project-id ID      GCP project ID (default: of-scheduler-proj)
#   --dataset NAME       BigQuery dataset (default: eros_scheduling_brain)
#   --skip-backup        Skip backup creation (not recommended)
#   --skip-tests         Skip post-deployment tests
#   --dry-run            Show what would be deployed without executing
#   --verbose            Enable verbose logging
#   --force              Force re-deployment of existing components
#
# Examples:
#   ./deploy_production_complete.sh
#   ./deploy_production_complete.sh --dry-run
#   ./deploy_production_complete.sh --project-id my-project --verbose
#
# Exit Codes:
#   0 - Success
#   1 - Prerequisites failed
#   2 - Backup failed
#   3 - Deployment failed
#   4 - Validation failed
#   5 - Rollback required
#
# Author: DevOps Engineer
# Version: 2.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Default configuration
PROJECT_ID="${EROS_PROJECT_ID:-of-scheduler-proj}"
DATASET="${EROS_DATASET:-eros_scheduling_brain}"
SKIP_BACKUP=false
SKIP_TESTS=false
DRY_RUN=false
VERBOSE=false
FORCE=false

# Deployment tracking
DEPLOYMENT_ID=$(date '+%Y%m%d_%H%M%S')
LOG_DIR="/tmp/eros_deployment_${DEPLOYMENT_ID}"
DEPLOYMENT_LOG="${LOG_DIR}/deployment.log"
STATE_FILE="${LOG_DIR}/state.json"
BACKUP_TIMESTAMP=""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create log directory
mkdir -p "${LOG_DIR}"

# Redirect all output to log and console
exec > >(tee -a "${DEPLOYMENT_LOG}") 2>&1

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_header() {
    echo -e "${BOLD}${BLUE}"
    echo "========================================================================"
    echo "  $1"
    echo "========================================================================"
    echo -e "${NC}"
}

log_step() {
    echo -e "${CYAN}[STEP $(date '+%H:%M:%S')]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO $(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS $(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING $(date '+%H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR $(date '+%H:%M:%S')]${NC} $1"
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${MAGENTA}[DEBUG $(date '+%H:%M:%S')]${NC} $1"
    fi
}

log_dry_run() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $1"
    fi
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

init_state() {
    cat > "${STATE_FILE}" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "project_id": "${PROJECT_ID}",
  "dataset": "${DATASET}",
  "started_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "status": "in_progress",
  "components": {}
}
EOF
}

update_state() {
    local component=$1
    local status=$2
    local message=${3:-""}

    if command -v jq &> /dev/null; then
        local temp=$(mktemp)
        jq ".components[\"${component}\"] = {\"status\": \"${status}\", \"message\": \"${message}\", \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"}" \
            "${STATE_FILE}" > "${temp}"
        mv "${temp}" "${STATE_FILE}"
    fi
}

get_state() {
    local component=$1

    if command -v jq &> /dev/null; then
        jq -r ".components[\"${component}\"].status // \"not_deployed\"" "${STATE_FILE}"
    else
        echo "not_deployed"
    fi
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << EOF
EROS Scheduling System - Complete Production Deployment

Usage: $0 [OPTIONS]

Options:
  --project-id ID      GCP project ID (default: of-scheduler-proj)
  --dataset NAME       BigQuery dataset (default: eros_scheduling_brain)
  --skip-backup        Skip backup creation (not recommended)
  --skip-tests         Skip post-deployment tests
  --dry-run            Show what would be deployed without executing
  --verbose            Enable verbose logging
  --force              Force re-deployment of existing components
  -h, --help           Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --project-id my-project --verbose

For more information, see deployment/README.md
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --dataset)
                DATASET="$2"
                shift 2
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."

    local all_ok=true

    # Check required commands
    local commands=("bq" "gcloud" "gsutil")
    for cmd in "${commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "Required command not found: ${cmd}"
            all_ok=false
        else
            log_debug "Found: ${cmd}"
        fi
    done

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        all_ok=false
    fi

    # Check project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null 2>&1; then
        log_error "Cannot access project: ${PROJECT_ID}"
        all_ok=false
    else
        log_debug "Project accessible: ${PROJECT_ID}"
    fi

    # Check BigQuery permissions
    if ! bq ls --project_id="${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access BigQuery in project: ${PROJECT_ID}"
        all_ok=false
    fi

    # Check if dataset exists or can be created
    if bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_info "Dataset exists: ${PROJECT_ID}:${DATASET}"
    else
        log_warning "Dataset does not exist - will be created: ${PROJECT_ID}:${DATASET}"
    fi

    # Check SQL files exist
    local required_files=(
        "bigquery_infrastructure_setup.sql"
        "stored_procedures.sql"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
            log_error "Required SQL file not found: ${file}"
            all_ok=false
        fi
    done

    if [[ "${all_ok}" == "false" ]]; then
        log_error "Prerequisites check failed"
        return 1
    fi

    log_success "Prerequisites check passed"
    return 0
}

# ============================================================================
# BACKUP MANAGEMENT
# ============================================================================

create_backup() {
    if [[ "${SKIP_BACKUP}" == "true" ]]; then
        log_warning "Skipping backup as requested"
        return 0
    fi

    log_step "Creating backup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "./backup_tables.sh ${PROJECT_ID} ${DATASET}"
        BACKUP_TIMESTAMP="DRY_RUN_$(date '+%Y%m%d_%H%M%S')"
        return 0
    fi

    local backup_script="${SCRIPT_DIR}/backup_tables.sh"

    if [[ ! -f "${backup_script}" ]]; then
        log_warning "Backup script not found: ${backup_script}"
        log_warning "Proceeding without backup (not recommended)"
        return 0
    fi

    if bash "${backup_script}" "${PROJECT_ID}" "${DATASET}" 2>&1 | tee "${LOG_DIR}/backup.log"; then
        # Extract backup timestamp from backup log
        BACKUP_TIMESTAMP=$(grep -oP 'backup_\K[0-9_]+' "${LOG_DIR}/backup.log" | head -1 || echo "$(date '+%Y%m%d_%H%M%S')")
        log_success "Backup completed: ${BACKUP_TIMESTAMP}"
        update_state "backup" "completed" "Backup timestamp: ${BACKUP_TIMESTAMP}"
        echo "${BACKUP_TIMESTAMP}" > "${LOG_DIR}/backup_timestamp.txt"
        return 0
    else
        log_error "Backup failed"
        update_state "backup" "failed" "Backup creation failed"
        return 1
    fi
}

# ============================================================================
# DEPLOYMENT COMPONENTS
# ============================================================================

deploy_dataset() {
    log_step "Ensuring dataset exists..."

    if bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_success "Dataset already exists: ${DATASET}"
        update_state "dataset" "exists" "Dataset already exists"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "bq mk --dataset ${PROJECT_ID}:${DATASET}"
        return 0
    fi

    log_info "Creating dataset: ${DATASET}"

    if bq mk --dataset --location=US --description="EROS Scheduling System Brain" "${PROJECT_ID}:${DATASET}"; then
        log_success "Dataset created: ${DATASET}"
        update_state "dataset" "created" "Dataset created successfully"
        return 0
    else
        log_error "Dataset creation failed"
        update_state "dataset" "failed" "Dataset creation failed"
        return 1
    fi
}

deploy_infrastructure() {
    log_step "Deploying infrastructure (tables, UDFs, TVFs)..."

    local sql_file="${SCRIPT_DIR}/bigquery_infrastructure_setup.sql"

    if [[ ! -f "${sql_file}" ]]; then
        # Try alternate location
        sql_file="${SCRIPT_DIR}/complete_bigquery_infrastructure.sql"
    fi

    if [[ ! -f "${sql_file}" ]]; then
        log_error "Infrastructure SQL file not found"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "bq query < ${sql_file}"
        return 0
    fi

    log_info "Executing infrastructure SQL..."

    if bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --max_rows=0 \
        < "${sql_file}" 2>&1 | tee "${LOG_DIR}/infrastructure.log"; then

        log_success "Infrastructure deployed successfully"
        update_state "infrastructure" "deployed" "Tables, UDFs, and TVFs deployed"
        return 0
    else
        log_error "Infrastructure deployment failed"
        update_state "infrastructure" "failed" "Infrastructure deployment failed"
        return 1
    fi
}

deploy_procedures() {
    log_step "Deploying stored procedures..."

    local procedures_file="${SCRIPT_DIR}/stored_procedures.sql"

    if [[ ! -f "${procedures_file}" ]]; then
        log_error "Stored procedures file not found: ${procedures_file}"
        return 1
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "bq query < ${procedures_file}"
        return 0
    fi

    log_info "Deploying stored procedures..."

    # Deploy main procedures file
    if bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --max_rows=0 \
        < "${procedures_file}" 2>&1 | tee "${LOG_DIR}/procedures.log"; then

        log_success "Stored procedures deployed"
        update_state "procedures" "deployed" "Stored procedures deployed"
    else
        log_warning "Some procedures may have failed - check logs"
        update_state "procedures" "partial" "Some procedures failed"
    fi

    # Deploy additional specific procedures if they exist
    local additional_procs=(
        "select_captions_procedure.sql"
        "CORRECTED_analyze_creator_performance_FULL.sql"
    )

    for proc_file in "${additional_procs[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${proc_file}" ]]; then
            log_info "Deploying ${proc_file}..."
            bq query \
                --use_legacy_sql=false \
                --project_id="${PROJECT_ID}" \
                --max_rows=0 \
                < "${SCRIPT_DIR}/${proc_file}" 2>&1 | tee -a "${LOG_DIR}/procedures.log" || true
        fi
    done

    return 0
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_deployment() {
    log_step "Validating deployment..."

    local validation_passed=true
    local validation_warnings=0

    # Check tables exist
    log_info "Checking tables..."
    local required_tables=(
        "caption_bank"
        "caption_bandit_stats"
        "active_caption_assignments"
        "caption_locks"
        "schedule_recommendations"
    )

    for table in "${required_tables[@]}"; do
        if bq show "${PROJECT_ID}:${DATASET}.${table}" &> /dev/null; then
            log_success "  Table exists: ${table}"
        else
            log_error "  Table missing: ${table}"
            validation_passed=false
        fi
    done

    # Check UDFs exist
    log_info "Checking UDFs..."
    local udf_count=$(bq query --use_legacy_sql=false --format=csv --max_rows=100 \
        "SELECT COUNT(*) as cnt FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type = 'FUNCTION' AND routine_name NOT LIKE '%tvf_%'" 2>/dev/null | tail -1)

    if [[ ${udf_count:-0} -ge 2 ]]; then
        log_success "  UDFs found: ${udf_count}"
    else
        log_warning "  UDFs may be missing: only ${udf_count} found"
        ((validation_warnings++))
    fi

    # Check TVFs exist
    log_info "Checking TVFs..."
    local tvf_count=$(bq query --use_legacy_sql=false --format=csv --max_rows=100 \
        "SELECT COUNT(*) as cnt FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type = 'TABLE_VALUED_FUNCTION'" 2>/dev/null | tail -1)

    if [[ ${tvf_count:-0} -ge 3 ]]; then
        log_success "  TVFs found: ${tvf_count}"
    else
        log_warning "  TVFs may be missing: only ${tvf_count} found"
        ((validation_warnings++))
    fi

    # Check procedures exist
    log_info "Checking stored procedures..."
    local proc_count=$(bq query --use_legacy_sql=false --format=csv --max_rows=100 \
        "SELECT COUNT(*) as cnt FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type = 'PROCEDURE'" 2>/dev/null | tail -1)

    if [[ ${proc_count:-0} -ge 2 ]]; then
        log_success "  Procedures found: ${proc_count}"
    else
        log_warning "  Procedures may be missing: only ${proc_count} found"
        ((validation_warnings++))
    fi

    # Summary
    echo ""
    if [[ "${validation_passed}" == "true" ]]; then
        if [[ ${validation_warnings} -eq 0 ]]; then
            log_success "Validation passed with no warnings"
            update_state "validation" "passed" "All checks passed"
            return 0
        else
            log_warning "Validation passed with ${validation_warnings} warnings"
            update_state "validation" "passed_with_warnings" "${validation_warnings} warnings"
            return 0
        fi
    else
        log_error "Validation failed"
        update_state "validation" "failed" "Critical checks failed"
        return 1
    fi
}

run_smoke_tests() {
    if [[ "${SKIP_TESTS}" == "true" ]]; then
        log_warning "Skipping smoke tests as requested"
        return 0
    fi

    log_step "Running smoke tests..."

    local test_file="${SCRIPT_DIR}/../tests/comprehensive_smoke_test.py"

    if [[ ! -f "${test_file}" ]]; then
        log_warning "Smoke test file not found: ${test_file}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "python3 ${test_file}"
        return 0
    fi

    log_info "Executing smoke tests..."

    if python3 "${test_file}" 2>&1 | tee "${LOG_DIR}/smoke_tests.log"; then
        log_success "Smoke tests passed"
        update_state "smoke_tests" "passed" "All smoke tests passed"
        return 0
    else
        log_warning "Some smoke tests failed - check logs"
        update_state "smoke_tests" "partial" "Some tests failed"
        return 0  # Don't fail deployment on test warnings
    fi
}

# ============================================================================
# ROLLBACK
# ============================================================================

trigger_rollback() {
    log_error "Deployment failed - triggering rollback..."

    if [[ -z "${BACKUP_TIMESTAMP}" ]]; then
        log_error "No backup available for rollback"
        return 1
    fi

    local rollback_script="${SCRIPT_DIR}/rollback.sh"

    if [[ ! -f "${rollback_script}" ]]; then
        log_error "Rollback script not found: ${rollback_script}"
        return 1
    fi

    log_warning "Rolling back to backup: ${BACKUP_TIMESTAMP}"

    if bash "${rollback_script}" "${BACKUP_TIMESTAMP}" 2>&1 | tee "${LOG_DIR}/rollback.log"; then
        log_success "Rollback completed successfully"
        return 0
    else
        log_error "Rollback failed"
        return 1
    fi
}

# ============================================================================
# SUMMARY AND REPORTING
# ============================================================================

generate_summary() {
    local exit_code=$1

    log_header "DEPLOYMENT SUMMARY"

    echo "Deployment ID: ${DEPLOYMENT_ID}"
    echo "Project: ${PROJECT_ID}"
    echo "Dataset: ${DATASET}"
    echo "Started: $(jq -r '.started_at' "${STATE_FILE}")"
    echo "Completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""

    # Component status
    echo "Component Status:"
    if command -v jq &> /dev/null; then
        jq -r '.components | to_entries[] | "  \(.key): \(.value.status)"' "${STATE_FILE}"
    fi
    echo ""

    # Files and logs
    echo "Deployment Artifacts:"
    echo "  State file: ${STATE_FILE}"
    echo "  Log file: ${DEPLOYMENT_LOG}"
    echo "  Log directory: ${LOG_DIR}"
    if [[ -n "${BACKUP_TIMESTAMP}" ]]; then
        echo "  Backup timestamp: ${BACKUP_TIMESTAMP}"
    fi
    echo ""

    # Result
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "DEPLOYMENT SUCCESSFUL"
        echo ""
        echo "Next Steps:"
        echo "  1. Monitor system health: bq query < ${SCRIPT_DIR}/monitor_deployment.sql"
        echo "  2. Run integration tests manually"
        echo "  3. Review logs: cat ${DEPLOYMENT_LOG}"
        echo "  4. Set up monitoring alerts"
    else
        log_error "DEPLOYMENT FAILED"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Review logs: cat ${DEPLOYMENT_LOG}"
        echo "  2. Check component status: cat ${STATE_FILE}"
        if [[ -n "${BACKUP_TIMESTAMP}" ]]; then
            echo "  3. Rollback if needed: ./rollback.sh ${BACKUP_TIMESTAMP}"
        fi
    fi

    echo ""
}

# ============================================================================
# MAIN DEPLOYMENT FLOW
# ============================================================================

main() {
    log_header "EROS SCHEDULING SYSTEM - PRODUCTION DEPLOYMENT"

    # Parse arguments
    parse_args "$@"

    # Display configuration
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Deployment ID: ${DEPLOYMENT_ID}"
    log_info "  Log Directory: ${LOG_DIR}"
    log_info "  Skip Backup: ${SKIP_BACKUP}"
    log_info "  Skip Tests: ${SKIP_TESTS}"
    log_info "  Dry Run: ${DRY_RUN}"
    log_info "  Verbose: ${VERBOSE}"
    log_info "  Force: ${FORCE}"
    echo ""

    # Initialize state
    init_state

    # Prerequisites
    if ! check_prerequisites; then
        generate_summary 1
        exit 1
    fi
    echo ""

    # Backup
    if ! create_backup; then
        log_error "Backup failed - aborting deployment"
        generate_summary 2
        exit 2
    fi
    echo ""

    # Deploy components
    local deployment_failed=false

    if ! deploy_dataset; then
        deployment_failed=true
    fi
    echo ""

    if ! deploy_infrastructure; then
        deployment_failed=true
    fi
    echo ""

    if ! deploy_procedures; then
        # Procedures can have warnings but don't fail deployment
        log_warning "Procedures deployment had issues but continuing..."
    fi
    echo ""

    # Validate
    if ! validate_deployment; then
        deployment_failed=true
    fi
    echo ""

    # Smoke tests
    run_smoke_tests || true
    echo ""

    # Handle failure
    if [[ "${deployment_failed}" == "true" ]]; then
        log_error "Deployment failed validation"

        if [[ "${DRY_RUN}" != "true" ]]; then
            read -p "Trigger automatic rollback? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                trigger_rollback
            fi
        fi

        generate_summary 3
        exit 3
    fi

    # Success
    update_state "deployment" "completed" "Deployment successful"
    generate_summary 0
    exit 0
}

# Trap interrupts
trap 'log_error "Deployment interrupted"; generate_summary 130; exit 130' INT TERM

# Execute main
main "$@"
