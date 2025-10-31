#!/bin/bash

################################################################################
# EROS Scheduling System - Phase 1 Deployment Script
#
# Description: Deploys critical bug fixes
#   - Wilson Score calculation fix
#   - Thompson Sampling fix
#   - Caption locking mechanism
#   - SQL injection protection
#
# Usage: ./deploy_phase1.sh [PROJECT_ID] [DATASET]
#
# Requirements:
#   - bq CLI installed and authenticated
#   - Backup completed before deployment
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration
DEPLOYMENT_TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
LOG_DIR="/tmp/eros_deployment_phase1_${DEPLOYMENT_TIMESTAMP}"
mkdir -p "${LOG_DIR}"

# Parse arguments
PROJECT_ID="${1:-}"
DATASET="${2:-}"

# Get project ID
get_project_id() {
    if [[ -n "${PROJECT_ID}" ]]; then
        echo "${PROJECT_ID}"
    elif [[ -n "${EROS_PROJECT_ID:-}" ]]; then
        echo "${EROS_PROJECT_ID}"
    else
        local gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "${gcloud_project}" ]]; then
            echo "${gcloud_project}"
        else
            log_error "Project ID not provided"
            exit 1
        fi
    fi
}

# Get dataset
get_dataset() {
    if [[ -n "${DATASET}" ]]; then
        echo "${DATASET}"
    elif [[ -n "${EROS_DATASET:-}" ]]; then
        echo "${EROS_DATASET}"
    else
        echo "eros_platform"
    fi
}

PROJECT_ID=$(get_project_id)
DATASET=$(get_dataset)

# Validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
declare -a TEST_RESULTS

# Execute SQL query
execute_query() {
    local description=$1
    local query=$2
    local log_file="${LOG_DIR}/$(echo "${description}" | tr ' ' '_' | tr '[:upper:]' '[:lower:]').log"

    log_info "${description}"

    if echo "${query}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --format=pretty \
        --max_rows=10 > "${log_file}" 2>&1; then
        log_success "  Completed"
        return 0
    else
        log_error "  Failed - see ${log_file}"
        cat "${log_file}"
        return 1
    fi
}

# Run validation test
run_test() {
    local test_name=$1
    local query=$2
    local expected_result=$3

    ((TOTAL_TESTS++))
    log_info "Test ${TOTAL_TESTS}: ${test_name}"

    local result=$(echo "${query}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --format=csv \
        --max_rows=1 2>/dev/null | tail -n 1 || echo "ERROR")

    if [[ "${result}" == "${expected_result}" ]] || [[ "${result}" == *"${expected_result}"* ]]; then
        log_success "  PASSED"
        ((PASSED_TESTS++))
        TEST_RESULTS+=("PASS: ${test_name}")
        return 0
    else
        log_error "  FAILED - Expected: ${expected_result}, Got: ${result}"
        ((FAILED_TESTS++))
        TEST_RESULTS+=("FAIL: ${test_name} - Expected: ${expected_result}, Got: ${result}")
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found"
        exit 1
    fi

    if ! bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_error "Dataset ${PROJECT_ID}:${DATASET} not found"
        exit 1
    fi

    # Check for recent backup
    if ! gsutil ls "gs://eros-platform-backups/" | tail -n 5 | grep -q "$(date '+%Y-%m-%d')"; then
        log_warning "No backup found from today. It is strongly recommended to run ./backup_tables.sh first"
        read -p "Continue without backup? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi

    log_success "Prerequisites check passed"
}

################################################################################
# Fix 1: Wilson Score Lower Bound Calculation
################################################################################
deploy_wilson_score_fix() {
    log_step "Deploying Wilson Score Lower Bound Fix"

    local query="
-- Create or replace the corrected Wilson Score calculation
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET}.caption_scores_corrected\` AS
WITH wilson_scores AS (
  SELECT
    caption_id,
    total_views,
    engagement_count,
    -- Correct Wilson Score Lower Bound calculation
    CASE
      WHEN total_views = 0 THEN 0.0
      WHEN total_views < 10 THEN 0.0  -- Require minimum views
      ELSE
        (engagement_count + 1.9208) / (total_views + 3.8416)
        - 1.96 * SQRT((engagement_count * (total_views - engagement_count)) / total_views + 0.9604) / (total_views + 3.8416)
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

    if execute_query "Creating Wilson Score corrected view" "${query}"; then
        log_success "Wilson Score fix deployed"

        # Update caption_bandit_stats table
        local update_query="
UPDATE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` AS stats
SET wilson_score_lower_bound = (
  SELECT wilson_score_lower_bound
  FROM \`${PROJECT_ID}.${DATASET}.caption_scores_corrected\` AS corrected
  WHERE corrected.caption_id = stats.caption_id
)
WHERE TRUE;
"
        execute_query "Updating wilson_score_lower_bound in caption_bandit_stats" "${update_query}"
        return 0
    else
        return 1
    fi
}

# Validate Wilson Score fix
validate_wilson_score() {
    log_step "Validating Wilson Score Fix"

    # Test 1: All Wilson scores should be between 0 and 1
    run_test "Wilson scores are within valid range [0,1]" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` WHERE wilson_score_lower_bound < 0 OR wilson_score_lower_bound > 1" \
        "0"

    # Test 2: Captions with 0 views should have 0 Wilson score
    run_test "Captions with 0 views have 0 Wilson score" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` WHERE total_views = 0 AND wilson_score_lower_bound != 0" \
        "0"

    # Test 3: Captions with views should have non-negative Wilson scores
    run_test "Captions with views have valid Wilson scores" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` WHERE total_views > 0 AND wilson_score_lower_bound >= 0" \
        ">0"
}

################################################################################
# Fix 2: Thompson Sampling
################################################################################
deploy_thompson_sampling_fix() {
    log_step "Deploying Thompson Sampling Fix"

    local query="
-- Create Thompson Sampling stored procedure
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.select_caption_thompson_sampling\`(
  IN account_id STRING,
  IN account_size STRING,
  OUT selected_caption_id INT64
)
BEGIN
  DECLARE alpha FLOAT64;
  DECLARE beta FLOAT64;

  -- Sample from beta distribution for each caption
  CREATE TEMP TABLE thompson_samples AS
  SELECT
    caption_id,
    -- Alpha = successes + 1, Beta = failures + 1 (Bayesian prior)
    engagement_count + 1 AS alpha,
    (total_views - engagement_count) + 1 AS beta,
    -- Approximate beta distribution sampling using normal approximation
    -- For production, use a proper random number generator
    CASE
      WHEN total_views > 30 THEN
        -- Use normal approximation for beta distribution
        (engagement_count + 1.0) / (total_views + 2.0) +
        RAND() * SQRT(
          ((engagement_count + 1.0) * (total_views - engagement_count + 1.0)) /
          (POW(total_views + 2.0, 2) * (total_views + 3.0))
        )
      ELSE
        -- For small sample sizes, add more exploration
        (engagement_count + 1.0) / (total_views + 2.0) + (RAND() - 0.5) * 0.3
    END AS sampled_value
  FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
  WHERE total_views >= 0;  -- Include all captions

  -- Select caption with highest sampled value
  SET selected_caption_id = (
    SELECT caption_id
    FROM thompson_samples
    ORDER BY sampled_value DESC
    LIMIT 1
  );

  -- Clean up
  DROP TABLE thompson_samples;
END;
"

    execute_query "Creating Thompson Sampling procedure" "${query}"
}

# Validate Thompson Sampling
validate_thompson_sampling() {
    log_step "Validating Thompson Sampling Fix"

    # Test that procedure exists
    run_test "Thompson Sampling procedure exists" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name = 'select_caption_thompson_sampling'" \
        "1"
}

################################################################################
# Fix 3: Caption Locking Mechanism
################################################################################
deploy_caption_locking_fix() {
    log_step "Deploying Caption Locking Mechanism"

    # Create caption_locks table if it doesn't exist
    local create_locks_table="
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.caption_locks\` (
  caption_id INT64 NOT NULL,
  account_id STRING NOT NULL,
  locked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  expires_at TIMESTAMP NOT NULL,
  lock_id STRING NOT NULL
)
PARTITION BY DATE(locked_at)
CLUSTER BY caption_id, account_id;
"

    execute_query "Creating caption_locks table" "${create_locks_table}"

    # Create locking procedure
    local lock_procedure="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.acquire_caption_lock\`(
  IN caption_id INT64,
  IN account_id STRING,
  IN lock_duration_seconds INT64,
  OUT lock_acquired BOOL,
  OUT lock_id STRING
)
BEGIN
  DECLARE existing_locks INT64;

  -- Generate unique lock ID
  SET lock_id = GENERATE_UUID();

  -- Check for existing active locks
  SET existing_locks = (
    SELECT COUNT(*)
    FROM \`${PROJECT_ID}.${DATASET}.caption_locks\`
    WHERE caption_id = caption_id
      AND account_id = account_id
      AND expires_at > CURRENT_TIMESTAMP()
  );

  IF existing_locks = 0 THEN
    -- No active locks, acquire new lock
    INSERT INTO \`${PROJECT_ID}.${DATASET}.caption_locks\`
      (caption_id, account_id, locked_at, expires_at, lock_id)
    VALUES
      (caption_id, account_id, CURRENT_TIMESTAMP(),
       TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL lock_duration_seconds SECOND),
       lock_id);

    SET lock_acquired = TRUE;
  ELSE
    SET lock_acquired = FALSE;
    SET lock_id = NULL;
  END IF;
END;
"

    execute_query "Creating caption lock acquisition procedure" "${lock_procedure}"

    # Create lock release procedure
    local unlock_procedure="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.release_caption_lock\`(
  IN lock_id STRING
)
BEGIN
  DELETE FROM \`${PROJECT_ID}.${DATASET}.caption_locks\`
  WHERE lock_id = lock_id;
END;
"

    execute_query "Creating caption lock release procedure" "${unlock_procedure}"

    # Create expired locks cleanup procedure
    local cleanup_procedure="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.cleanup_expired_locks\`()
BEGIN
  DELETE FROM \`${PROJECT_ID}.${DATASET}.caption_locks\`
  WHERE expires_at < CURRENT_TIMESTAMP();
END;
"

    execute_query "Creating expired locks cleanup procedure" "${cleanup_procedure}"
}

# Validate caption locking
validate_caption_locking() {
    log_step "Validating Caption Locking Mechanism"

    run_test "Caption locks table exists" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.TABLES\` WHERE table_name = 'caption_locks'" \
        "1"

    run_test "Caption lock procedures exist" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name IN ('acquire_caption_lock', 'release_caption_lock', 'cleanup_expired_locks')" \
        "3"
}

################################################################################
# Fix 4: SQL Injection Protection
################################################################################
deploy_sql_injection_protection() {
    log_step "Deploying SQL Injection Protection"

    # Create parameterized query examples and validation function
    local validation_function="
CREATE OR REPLACE FUNCTION \`${PROJECT_ID}.${DATASET}.validate_input\`(input STRING, max_length INT64)
RETURNS BOOL
AS (
  -- Validate input string for safe use in queries
  input IS NOT NULL
  AND LENGTH(input) <= max_length
  AND input NOT LIKE '%\\\\%'  -- No backslashes
  AND input NOT LIKE '%;%'     -- No semicolons
  AND input NOT LIKE '%---%'   -- No SQL comments
  AND input NOT LIKE '%/*%'    -- No block comments
  AND REGEXP_CONTAINS(input, r'^[a-zA-Z0-9_-]+$')  -- Alphanumeric, underscore, hyphen only
);
"

    execute_query "Creating input validation function" "${validation_function}"

    # Create safe caption selection procedure
    local safe_selection="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.select_caption_safe\`(
  IN account_id_param STRING,
  OUT selected_caption_id INT64,
  OUT error_message STRING
)
BEGIN
  -- Validate input
  IF NOT \`${PROJECT_ID}.${DATASET}.validate_input\`(account_id_param, 255) THEN
    SET error_message = 'Invalid account_id format';
    SET selected_caption_id = NULL;
    RETURN;
  END IF;

  -- Use parameterized query
  SET selected_caption_id = (
    SELECT c.caption_id
    FROM \`${PROJECT_ID}.${DATASET}.caption_bank\` c
    LEFT JOIN \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` a
      ON c.caption_id = a.caption_id AND a.account_id = account_id_param
    WHERE a.caption_id IS NULL  -- Not already assigned
    ORDER BY RAND()
    LIMIT 1
  );

  SET error_message = NULL;
END;
"

    execute_query "Creating safe caption selection procedure" "${safe_selection}"
}

# Validate SQL injection protection
validate_sql_injection_protection() {
    log_step "Validating SQL Injection Protection"

    run_test "Input validation function exists" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name = 'validate_input'" \
        "1"

    run_test "Safe caption selection procedure exists" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\` WHERE routine_name = 'select_caption_safe'" \
        "1"

    # Test validation function with malicious input
    run_test "Validation rejects SQL injection attempt" \
        "SELECT \`${PROJECT_ID}.${DATASET}.validate_input\`('account123; DROP TABLE users--', 255)" \
        "false"

    run_test "Validation accepts valid input" \
        "SELECT \`${PROJECT_ID}.${DATASET}.validate_input\`('account_123', 255)" \
        "true"
}

################################################################################
# Main Deployment Flow
################################################################################
main() {
    echo ""
    echo "=========================================================="
    echo "  EROS Scheduling System - Phase 1 Deployment"
    echo "  Critical Bug Fixes"
    echo "=========================================================="
    echo ""

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Deployment Time: ${DEPLOYMENT_TIMESTAMP}"
    log_info "  Log Directory: ${LOG_DIR}"
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Deploy fixes
    local deployment_failed=false

    # Fix 1: Wilson Score
    if deploy_wilson_score_fix; then
        validate_wilson_score
    else
        deployment_failed=true
    fi
    echo ""

    # Fix 2: Thompson Sampling
    if deploy_thompson_sampling_fix; then
        validate_thompson_sampling
    else
        deployment_failed=true
    fi
    echo ""

    # Fix 3: Caption Locking
    if deploy_caption_locking_fix; then
        validate_caption_locking
    else
        deployment_failed=true
    fi
    echo ""

    # Fix 4: SQL Injection Protection
    if deploy_sql_injection_protection; then
        validate_sql_injection_protection
    else
        deployment_failed=true
    fi
    echo ""

    # Print summary
    echo "=========================================================="
    echo "  Phase 1 Deployment Summary"
    echo "=========================================================="
    echo ""
    log_info "Total validation tests: ${TOTAL_TESTS}"
    log_success "Passed: ${PASSED_TESTS}"
    if [[ ${FAILED_TESTS} -gt 0 ]]; then
        log_error "Failed: ${FAILED_TESTS}"
    fi
    echo ""

    if [[ ${FAILED_TESTS} -eq 0 ]] && [[ "${deployment_failed}" == "false" ]]; then
        log_success "Phase 1 deployment completed successfully!"
        echo ""
        log_info "Next steps:"
        log_info "  1. Monitor system for 30 minutes"
        log_info "  2. Review logs in: ${LOG_DIR}"
        log_info "  3. Run Phase 2 deployment: ./deploy_phase2.sh"
        echo ""
        exit 0
    else
        log_error "Phase 1 deployment completed with errors"
        echo ""
        log_error "Failed tests:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "${result}" == FAIL:* ]]; then
                log_error "  ${result}"
            fi
        done
        echo ""
        log_warning "Review logs in: ${LOG_DIR}"
        log_warning "Consider running rollback: ./rollback.sh"
        echo ""
        exit 1
    fi
}

# Handle interruption
trap 'log_error "Deployment interrupted"; exit 130' INT TERM

# Run main
main "$@"
