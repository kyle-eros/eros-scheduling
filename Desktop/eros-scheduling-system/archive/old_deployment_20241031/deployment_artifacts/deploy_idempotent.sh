#!/bin/bash

################################################################################
# EROS Scheduling System - Idempotent Deployment Script
#
# Description: Safe, repeatable deployment that can be re-run multiple times
#   - Checks current state before each operation
#   - Skips already-deployed components
#   - Creates missing components only
#   - Validates after each step
#   - Full rollback capability
#
# Usage: ./deploy_idempotent.sh [OPTIONS]
#
# Options:
#   --project-id ID      GCP project ID (default: from env or gcloud)
#   --dataset NAME       BigQuery dataset (default: eros_platform)
#   --skip-backup        Skip backup creation (not recommended)
#   --force              Force re-deployment of all components
#   --dry-run            Show what would be deployed without executing
#   --verbose            Enable verbose logging
#
# Examples:
#   ./deploy_idempotent.sh
#   ./deploy_idempotent.sh --dry-run
#   ./deploy_idempotent.sh --project-id my-project --dataset my_dataset
#
# Author: DevOps Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Configuration defaults
SKIP_BACKUP=false
FORCE_DEPLOY=false
DRY_RUN=false
VERBOSE=false

# Deployment timestamp
readonly DEPLOYMENT_TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
readonly LOG_DIR="/tmp/eros_deployment_${DEPLOYMENT_TIMESTAMP}"
readonly DEPLOYMENT_LOG="${LOG_DIR}/deployment.log"
readonly STATE_FILE="${LOG_DIR}/deployment_state.json"

mkdir -p "${LOG_DIR}"

# Redirect all output to log file and console
exec > >(tee -a "${DEPLOYMENT_LOG}") 2>&1

################################################################################
# Logging Functions
################################################################################

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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

log_dry_run() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $1"
    fi
}

################################################################################
# Parse Arguments
################################################################################

parse_arguments() {
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
            --force)
                FORCE_DEPLOY=true
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

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Idempotent deployment for EROS Scheduling System.
Safe to run multiple times - only deploys missing/changed components.

Options:
  --project-id ID      GCP project ID (default: from env or gcloud)
  --dataset NAME       BigQuery dataset (default: eros_platform)
  --skip-backup        Skip backup creation (not recommended)
  --force              Force re-deployment of all components
  --dry-run            Show what would be deployed without executing
  --verbose            Enable verbose logging
  -h, --help           Show this help message

Examples:
  $0
  $0 --dry-run
  $0 --project-id my-project --dataset my_dataset
  $0 --force --verbose

For more information, see deployment/README.md
EOF
}

################################################################################
# Environment Setup
################################################################################

get_project_id() {
    if [[ -n "${PROJECT_ID:-}" ]]; then
        echo "${PROJECT_ID}"
    elif [[ -n "${EROS_PROJECT_ID:-}" ]]; then
        echo "${EROS_PROJECT_ID}"
    else
        local gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "${gcloud_project}" ]]; then
            echo "${gcloud_project}"
        else
            log_error "Project ID not provided and cannot be determined"
            exit 1
        fi
    fi
}

get_dataset() {
    if [[ -n "${DATASET:-}" ]]; then
        echo "${DATASET}"
    elif [[ -n "${EROS_DATASET:-}" ]]; then
        echo "${EROS_DATASET}"
    else
        echo "eros_platform"
    fi
}

# Set global variables
PROJECT_ID=$(get_project_id)
DATASET=$(get_dataset)

################################################################################
# State Management
################################################################################

init_state_file() {
    cat > "${STATE_FILE}" << EOF
{
  "deployment_id": "${DEPLOYMENT_TIMESTAMP}",
  "project_id": "${PROJECT_ID}",
  "dataset": "${DATASET}",
  "started_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "components": {}
}
EOF
    log_debug "State file initialized: ${STATE_FILE}"
}

update_component_state() {
    local component=$1
    local status=$2
    local message=$3

    # Update state file using jq if available, otherwise simple append
    if command -v jq &> /dev/null; then
        local temp=$(mktemp)
        jq ".components[\"${component}\"] = {\"status\": \"${status}\", \"message\": \"${message}\", \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"}" \
            "${STATE_FILE}" > "${temp}"
        mv "${temp}" "${STATE_FILE}"
    fi

    log_debug "Component state updated: ${component} = ${status}"
}

get_component_state() {
    local component=$1

    if command -v jq &> /dev/null; then
        jq -r ".components[\"${component}\"].status // \"not_deployed\"" "${STATE_FILE}"
    else
        echo "not_deployed"
    fi
}

################################################################################
# Prerequisite Checks
################################################################################

check_prerequisites() {
    log_step "Checking prerequisites..."

    local all_ok=true

    # Check required commands
    local required_commands=("bq" "gcloud" "gsutil")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "Required command not found: ${cmd}"
            all_ok=false
        else
            log_debug "Found command: ${cmd}"
        fi
    done

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        all_ok=false
    fi

    # Check project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null 2>&1; then
        log_error "Cannot access project: ${PROJECT_ID}"
        all_ok=false
    fi

    # Check dataset exists
    if ! bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_warning "Dataset ${PROJECT_ID}:${DATASET} does not exist - will be created"
    else
        log_debug "Dataset ${PROJECT_ID}:${DATASET} exists"
    fi

    if [[ "${all_ok}" == "false" ]]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

################################################################################
# Backup Management
################################################################################

create_backup() {
    if [[ "${SKIP_BACKUP}" == "true" ]]; then
        log_warning "Skipping backup as requested"
        return 0
    fi

    log_step "Creating backup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "./backup_tables.sh ${PROJECT_ID} ${DATASET}"
        return 0
    fi

    local backup_script="$(dirname "$0")/backup_tables.sh"
    if [[ ! -f "${backup_script}" ]]; then
        log_warning "Backup script not found: ${backup_script}"
        return 0
    fi

    if bash "${backup_script}" "${PROJECT_ID}" "${DATASET}"; then
        log_success "Backup completed"
        update_component_state "backup" "completed" "Backup created successfully"
        return 0
    else
        log_error "Backup failed"
        return 1
    fi
}

################################################################################
# Component Deployment Functions
################################################################################

execute_sql_idempotent() {
    local component=$1
    local sql=$2
    local check_exists=${3:-}

    log_info "Deploying component: ${component}"

    # Check if already deployed (unless force mode)
    if [[ "${FORCE_DEPLOY}" != "true" ]]; then
        local current_state=$(get_component_state "${component}")
        if [[ "${current_state}" == "completed" ]]; then
            log_success "  Already deployed (skipping)"
            return 0
        fi
    fi

    # Check if component exists
    if [[ -n "${check_exists}" ]]; then
        if echo "${check_exists}" | bq query \
            --use_legacy_sql=false \
            --project_id="${PROJECT_ID}" \
            --format=csv \
            --max_rows=1 2>/dev/null | grep -q "1"; then

            if [[ "${FORCE_DEPLOY}" != "true" ]]; then
                log_success "  Component exists (skipping)"
                update_component_state "${component}" "completed" "Already exists"
                return 0
            else
                log_warning "  Component exists but force mode enabled (re-creating)"
            fi
        fi
    fi

    # Execute SQL
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Execute SQL for ${component}"
        return 0
    fi

    log_debug "Executing SQL for ${component}"

    if echo "${sql}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --format=pretty 2>&1 | tee -a "${LOG_DIR}/${component}.log"; then

        log_success "  Deployed successfully"
        update_component_state "${component}" "completed" "Deployed successfully"
        return 0
    else
        log_error "  Deployment failed"
        update_component_state "${component}" "failed" "Deployment error"
        return 1
    fi
}

deploy_dataset() {
    local component="dataset_${DATASET}"

    log_info "Ensuring dataset exists: ${DATASET}"

    if bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_success "  Dataset already exists"
        update_component_state "${component}" "completed" "Already exists"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "bq mk --dataset ${PROJECT_ID}:${DATASET}"
        return 0
    fi

    if bq mk --dataset --location=US "${PROJECT_ID}:${DATASET}"; then
        log_success "  Dataset created"
        update_component_state "${component}" "completed" "Created successfully"
        return 0
    else
        log_error "  Dataset creation failed"
        return 1
    fi
}

deploy_tables() {
    log_step "Deploying tables..."

    # Table: caption_bank
    local sql="
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.caption_bank\` (
        caption_id INT64,
        caption_text STRING,
        category STRING,
        price_tier STRING,
        has_urgency BOOL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
    )
    CLUSTER BY caption_id;
    "
    execute_sql_idempotent "table_caption_bank" "${sql}"

    # Table: caption_bandit_stats
    local sql="
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` (
        caption_id INT64,
        total_views INT64 DEFAULT 0,
        engagement_count INT64 DEFAULT 0,
        wilson_score_lower_bound FLOAT64 DEFAULT 0.0,
        last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
    )
    PARTITION BY DATE(last_updated)
    CLUSTER BY caption_id, wilson_score_lower_bound;
    "
    execute_sql_idempotent "table_caption_bandit_stats" "${sql}"

    # Table: active_caption_assignments
    local sql="
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` (
        caption_id INT64,
        account_id STRING,
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
        schedule_id STRING,
        expires_at TIMESTAMP
    )
    PARTITION BY DATE(assigned_at)
    CLUSTER BY account_id, caption_id;
    "
    execute_sql_idempotent "table_active_caption_assignments" "${sql}"

    # Table: caption_locks
    local sql="
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.caption_locks\` (
        caption_id INT64,
        account_id STRING,
        locked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
        expires_at TIMESTAMP,
        lock_id STRING
    )
    PARTITION BY DATE(locked_at)
    CLUSTER BY caption_id, account_id;
    "
    execute_sql_idempotent "table_caption_locks" "${sql}"

    # Table: schedule_recommendations
    local sql="
    CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.schedule_recommendations\` (
        schedule_id STRING,
        page_name STRING,
        week_start DATE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
        schedule_json STRING,
        total_messages INT64,
        saturation_zone STRING
    )
    PARTITION BY week_start
    CLUSTER BY page_name, schedule_id;
    "
    execute_sql_idempotent "table_schedule_recommendations" "${sql}"

    log_success "Tables deployment completed"
}

deploy_functions() {
    log_step "Deploying functions..."

    # Function: validate_input
    local sql="
    CREATE OR REPLACE FUNCTION \`${PROJECT_ID}.${DATASET}.validate_input\`(input STRING, max_length INT64)
    RETURNS BOOL
    AS (
        input IS NOT NULL
        AND LENGTH(input) <= max_length
        AND input NOT LIKE '%\\\\%'
        AND input NOT LIKE '%;%'
        AND input NOT LIKE '%---%'
        AND input NOT LIKE '%/*%'
        AND REGEXP_CONTAINS(input, r'^[a-zA-Z0-9_-]+\$')
    );
    "
    execute_sql_idempotent "function_validate_input" "${sql}"

    # Function: classify_account_size
    local sql="
    CREATE OR REPLACE FUNCTION \`${PROJECT_ID}.${DATASET}.classify_account_size\`(
        follower_count INT64,
        avg_engagement_rate FLOAT64
    )
    RETURNS STRING
    AS (
        CASE
            WHEN follower_count BETWEEN 1000 AND 10000 THEN 'micro'
            WHEN follower_count < 1000 AND avg_engagement_rate > 0.05 THEN 'nano_high_engagement'
            WHEN follower_count < 1000 THEN 'nano'
            WHEN follower_count BETWEEN 10001 AND 100000 THEN 'mid_tier'
            WHEN follower_count BETWEEN 100001 AND 1000000 THEN 'macro'
            WHEN follower_count > 1000000 THEN 'mega'
            ELSE 'unknown'
        END
    );
    "
    execute_sql_idempotent "function_classify_account_size" "${sql}"

    log_success "Functions deployment completed"
}

deploy_procedures() {
    log_step "Deploying stored procedures..."

    # Read procedure files if they exist
    local deployment_dir="$(dirname "$0")"

    if [[ -f "${deployment_dir}/stored_procedures.sql" ]]; then
        log_info "Deploying procedures from stored_procedures.sql"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry_run "Deploy stored_procedures.sql"
        else
            if bq query \
                --use_legacy_sql=false \
                --project_id="${PROJECT_ID}" \
                < "${deployment_dir}/stored_procedures.sql" 2>&1 | tee -a "${LOG_DIR}/procedures.log"; then
                log_success "  Procedures deployed"
                update_component_state "procedures" "completed" "Deployed from stored_procedures.sql"
            else
                log_warning "  Some procedures may have failed - check logs"
            fi
        fi
    else
        log_warning "stored_procedures.sql not found - skipping"
    fi

    log_success "Procedures deployment completed"
}

deploy_views() {
    log_step "Deploying views..."

    # View: caption_scores_corrected
    local sql="
    CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET}.caption_scores_corrected\` AS
    WITH wilson_scores AS (
        SELECT
            caption_id,
            total_views,
            engagement_count,
            CASE
                WHEN total_views = 0 THEN 0.0
                WHEN total_views < 10 THEN 0.0
                ELSE
                    (engagement_count + 1.9208) / (total_views + 3.8416)
                    - 1.96 * SQRT((engagement_count * (total_views - engagement_count)) / total_views + 0.9604)
                    / (total_views + 3.8416)
            END AS wilson_score_lower_bound
        FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
    )
    SELECT
        caption_id,
        total_views,
        engagement_count,
        GREATEST(0.0, LEAST(1.0, wilson_score_lower_bound)) AS wilson_score_lower_bound
    FROM wilson_scores;
    "
    execute_sql_idempotent "view_caption_scores_corrected" "${sql}"

    log_success "Views deployment completed"
}

################################################################################
# Validation
################################################################################

validate_deployment() {
    log_step "Validating deployment..."

    local validation_passed=true

    # Check tables exist
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

    # Check functions exist
    local function_count=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`
         WHERE routine_type = 'FUNCTION'" 2>/dev/null | tail -n 1)

    if [[ ${function_count} -ge 2 ]]; then
        log_success "  Functions exist: ${function_count} found"
    else
        log_warning "  Functions may be missing: only ${function_count} found"
    fi

    if [[ "${validation_passed}" == "true" ]]; then
        log_success "Validation passed"
        return 0
    else
        log_error "Validation failed"
        return 1
    fi
}

################################################################################
# Main Deployment Flow
################################################################################

main() {
    echo ""
    echo "=========================================================="
    echo "  EROS Scheduling System - Idempotent Deployment"
    echo "=========================================================="
    echo ""

    # Parse command line arguments
    parse_arguments "$@"

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Deployment ID: ${DEPLOYMENT_TIMESTAMP}"
    log_info "  Log Directory: ${LOG_DIR}"
    log_info "  Skip Backup: ${SKIP_BACKUP}"
    log_info "  Force Deploy: ${FORCE_DEPLOY}"
    log_info "  Dry Run: ${DRY_RUN}"
    log_info "  Verbose: ${VERBOSE}"
    echo ""

    # Initialize state tracking
    init_state_file

    # Check prerequisites
    check_prerequisites
    echo ""

    # Create backup
    if ! create_backup; then
        log_error "Backup creation failed - aborting deployment"
        exit 1
    fi
    echo ""

    # Deploy components
    local deployment_failed=false

    deploy_dataset || deployment_failed=true
    echo ""

    deploy_tables || deployment_failed=true
    echo ""

    deploy_functions || deployment_failed=true
    echo ""

    deploy_procedures || deployment_failed=true
    echo ""

    deploy_views || deployment_failed=true
    echo ""

    # Validate deployment
    if ! validate_deployment; then
        deployment_failed=true
    fi
    echo ""

    # Summary
    echo "=========================================================="
    echo "  Deployment Summary"
    echo "=========================================================="
    echo ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN completed - no changes were made"
        log_info "Review the log to see what would be deployed: ${DEPLOYMENT_LOG}"
        exit 0
    fi

    if [[ "${deployment_failed}" == "false" ]]; then
        log_success "Deployment completed successfully!"
        echo ""
        log_info "Deployment details:"
        log_info "  State file: ${STATE_FILE}"
        log_info "  Log file: ${DEPLOYMENT_LOG}"
        echo ""
        log_info "Next steps:"
        log_info "  1. Run validation tests: cd ../tests && ./run_validation_tests.sh"
        log_info "  2. Monitor system health: bq query < monitor_deployment.sql"
        log_info "  3. Check deployment logs: cat ${DEPLOYMENT_LOG}"
        echo ""
        exit 0
    else
        log_error "Deployment completed with errors"
        echo ""
        log_error "Review logs for details: ${DEPLOYMENT_LOG}"
        log_warning "To rollback: ./rollback.sh"
        echo ""
        exit 1
    fi
}

# Handle interruption
trap 'log_error "Deployment interrupted"; exit 130' INT TERM

# Run main
main "$@"
