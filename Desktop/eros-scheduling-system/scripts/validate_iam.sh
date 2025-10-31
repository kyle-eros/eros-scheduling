#!/bin/bash
################################################################################
# IAM Validation Script for Caption Restrictions Feature
################################################################################
#
# PURPOSE:
# Validate IAM permissions for Apps Script service account to ensure proper
# access to BigQuery tables and views required for caption restrictions.
#
# USAGE:
#   export APPS_SCRIPT_SA="your-sa@appspot.gserviceaccount.com"
#   ./scripts/validate_iam.sh
#
# EXIT CODES:
#   0 - All checks passed
#   1 - One or more checks failed
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${PROJECT_ID:-of-scheduler-proj}"
DATASET_ID="${DATASET_ID:-eros_scheduling_brain}"
SERVICE_ACCOUNT="${APPS_SCRIPT_SA:-}"

################################################################################
# Helper Functions
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

check_prerequisites() {
  # Check service account email provided
  if [[ -z "${SERVICE_ACCOUNT}" ]]; then
    log_error "APPS_SCRIPT_SA environment variable not set"
    echo ""
    echo "Usage:"
    echo "  export APPS_SCRIPT_SA='your-sa@appspot.gserviceaccount.com'"
    echo "  ./scripts/validate_iam.sh"
    echo ""
    exit 1
  fi

  # Check gcloud CLI
  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not found. Install Google Cloud SDK."
    exit 1
  fi

  # Check bq CLI
  if ! command -v bq &> /dev/null; then
    log_error "bq CLI not found. Install Google Cloud SDK."
    exit 1
  fi

  # Check authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    log_error "Not authenticated with gcloud"
    log_info "Run: gcloud auth application-default login"
    exit 1
  fi
}

################################################################################
# Validation Tests
################################################################################

test_bigquery_job_user() {
  log_info "Test 1: Checking bigquery.jobUser role (project-level)..."

  if gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${SERVICE_ACCOUNT}" \
    --format="value(bindings.role)" 2>/dev/null | grep -q "roles/bigquery.jobUser"; then
    log_success "bigquery.jobUser role granted"
    return 0
  else
    log_error "bigquery.jobUser role MISSING"
    log_info "Grant with: gcloud projects add-iam-policy-binding ${PROJECT_ID} --member=\"serviceAccount:${SERVICE_ACCOUNT}\" --role=\"roles/bigquery.jobUser\""
    return 1
  fi
}

test_bigquery_data_editor() {
  log_info "Test 2: Checking bigquery.dataEditor role (dataset-level)..."

  # Note: bq show --iam_policy requires bigquery.datasets.get permission
  if bq show --format=prettyjson "${PROJECT_ID}:${DATASET_ID}" 2>/dev/null | \
    grep -q "${SERVICE_ACCOUNT}"; then
    log_success "Service account has dataset access"
    return 0
  else
    log_warning "Cannot verify bigquery.dataEditor role (may lack admin permissions)"
    log_info "If errors occur, grant with: bq add-iam-policy-binding --member=\"serviceAccount:${SERVICE_ACCOUNT}\" --role=\"roles/bigquery.dataEditor\" ${PROJECT_ID}:${DATASET_ID}"
    return 0  # Don't fail on warning
  fi
}

test_select_views() {
  log_info "Test 3: Testing SELECT permission on views..."

  local views=(
    "active_creator_caption_restrictions_v"
    "creator_allowed_profile_v"
    "feature_flags"
  )

  local failed=0

  for view in "${views[@]}"; do
    if bq query --use_legacy_sql=false --format=none --max_rows=1 \
      "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_ID}.${view}\` LIMIT 1" &>/dev/null; then
      log_success "SELECT permission on ${view}"
    else
      log_error "SELECT permission MISSING on ${view}"
      ((failed++))
    fi
  done

  return ${failed}
}

test_merge_permission() {
  log_info "Test 4: Testing MERGE permission (dry run)..."

  # Test MERGE on creator_caption_restrictions (dry run only)
  if bq query --use_legacy_sql=false --dry_run \
    "MERGE \`${PROJECT_ID}.${DATASET_ID}.creator_caption_restrictions\` AS T
     USING (SELECT 'test_iam_validation' AS page_name) AS S
     ON T.page_name = S.page_name
     WHEN NOT MATCHED THEN
       INSERT (page_name, is_active, version)
       VALUES (S.page_name, FALSE, 1)" &>/dev/null; then
    log_success "MERGE permission on creator_caption_restrictions (dry run)"
  else
    log_error "MERGE permission MISSING on creator_caption_restrictions"
    return 1
  fi

  # Test MERGE on creator_allowed_profile (dry run only)
  if bq query --use_legacy_sql=false --dry_run \
    "MERGE \`${PROJECT_ID}.${DATASET_ID}.creator_allowed_profile\` AS T
     USING (SELECT 'test_iam_validation' AS page_name) AS S
     ON T.page_name = S.page_name
     WHEN NOT MATCHED THEN
       INSERT (page_name, is_active)
       VALUES (S.page_name, FALSE)" &>/dev/null; then
    log_success "MERGE permission on creator_allowed_profile (dry run)"
  else
    log_error "MERGE permission MISSING on creator_allowed_profile"
    return 1
  fi

  return 0
}

test_table_existence() {
  log_info "Test 5: Verifying required tables and views exist..."

  local tables=(
    "creator_caption_restrictions"
    "creator_allowed_profile"
    "feature_flags"
  )

  local views=(
    "active_creator_caption_restrictions_v"
    "creator_allowed_profile_v"
  )

  local failed=0

  for table in "${tables[@]}"; do
    if bq show "${PROJECT_ID}:${DATASET_ID}.${table}" &>/dev/null; then
      log_success "Table ${table} exists"
    else
      log_error "Table ${table} NOT FOUND"
      ((failed++))
    fi
  done

  for view in "${views[@]}"; do
    if bq show "${PROJECT_ID}:${DATASET_ID}.${view}" &>/dev/null; then
      log_success "View ${view} exists"
    else
      log_error "View ${view} NOT FOUND"
      ((failed++))
    fi
  done

  if [[ ${failed} -gt 0 ]]; then
    log_info "Run deployment script: ./scripts/bq_deploy.sh"
  fi

  return ${failed}
}

################################################################################
# Main Execution
################################################################################

main() {
  echo "========================================================================"
  echo "IAM Validation for Caption Restrictions Feature"
  echo "========================================================================"
  echo "Project:         ${PROJECT_ID}"
  echo "Dataset:         ${DATASET_ID}"
  echo "Service Account: ${SERVICE_ACCOUNT}"
  echo "========================================================================"
  echo ""

  # Check prerequisites
  check_prerequisites

  # Run validation tests
  local total_tests=5
  local passed_tests=0
  local failed_tests=0

  # Test 1: bigquery.jobUser
  if test_bigquery_job_user; then
    ((passed_tests++))
  else
    ((failed_tests++))
  fi
  echo ""

  # Test 2: bigquery.dataEditor
  if test_bigquery_data_editor; then
    ((passed_tests++))
  else
    ((failed_tests++))
  fi
  echo ""

  # Test 3: SELECT on views
  if test_select_views; then
    ((passed_tests++))
  else
    ((failed_tests++))
  fi
  echo ""

  # Test 4: MERGE permission
  if test_merge_permission; then
    ((passed_tests++))
  else
    ((failed_tests++))
  fi
  echo ""

  # Test 5: Table/view existence
  if test_table_existence; then
    ((passed_tests++))
  else
    ((failed_tests++))
  fi
  echo ""

  # Summary
  echo "========================================================================"
  if [[ ${failed_tests} -eq 0 ]]; then
    log_success "All ${total_tests} validation tests PASSED!"
    echo "========================================================================"
    echo ""
    echo "Next steps:"
    echo "  1. Configure Apps Script (see docs/APPS_SCRIPT_PREREQUISITES.md)"
    echo "  2. Set up monitoring (see docs/MONITORING_SETUP.md)"
    echo ""
    return 0
  else
    log_error "${failed_tests} out of ${total_tests} tests FAILED"
    echo "========================================================================"
    echo ""
    echo "Fix the issues above and re-run this script."
    echo ""
    return 1
  fi
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
