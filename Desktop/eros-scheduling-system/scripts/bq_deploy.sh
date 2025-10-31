#!/bin/bash
################################################################################
# BigQuery Deployment Script for Caption Restrictions Feature
################################################################################
#
# PURPOSE:
# Deploy all required BigQuery tables, views, and seed data for the Caption
# Restrictions feature in the correct order with proper error handling.
#
# USAGE:
#   ./scripts/bq_deploy.sh [--dataset DATASET] [--project PROJECT]
#
# OPTIONS:
#   --dataset   BigQuery dataset (default: of-scheduler-proj.eros_scheduling_brain)
#   --project   GCP project ID (default: of-scheduler-proj)
#   --dry-run   Show what would be executed without running
#
# FEATURES:
#   - Idempotent (safe to re-run)
#   - Fail-fast error handling
#   - Deployment verification
#   - Rollback on failure (optional)
#
# REQUIREMENTS:
#   - bq CLI installed and authenticated
#   - SQL files in ../sql/ directory
#
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
BQ_PROJECT="${BQ_PROJECT:-of-scheduler-proj}"
BQ_DATASET="${BQ_DATASET:-eros_scheduling_brain}"
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$(cd "${SCRIPT_DIR}/../sql" && pwd)"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dataset)
      BQ_DATASET="$2"
      shift 2
      ;;
    --project)
      BQ_PROJECT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      head -n 30 "$0" | tail -n +3 | sed 's/^# //; s/^#//'
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Full dataset path
FULL_DATASET="${BQ_PROJECT}.${BQ_DATASET}"

################################################################################
# Helper Functions
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check bq CLI
  if ! command -v bq &> /dev/null; then
    log_error "bq CLI not found. Install Google Cloud SDK: https://cloud.google.com/sdk/install"
    exit 1
  fi

  # Check authentication
  if ! bq ls --project_id="${BQ_PROJECT}" &> /dev/null; then
    log_error "Not authenticated or no access to project ${BQ_PROJECT}"
    log_info "Run: gcloud auth application-default login"
    exit 1
  fi

  # Check dataset exists
  if ! bq ls --project_id="${BQ_PROJECT}" | grep -q "${BQ_DATASET}"; then
    log_error "Dataset ${FULL_DATASET} does not exist"
    log_info "Create it first: bq mk --dataset ${FULL_DATASET}"
    exit 1
  fi

  # Check SQL files exist
  local required_files=(
    "create_table_feature_flags.sql"
    "create_table_creator_caption_restrictions.sql"
    "create_table_creator_allowed_profile.sql"
    "create_table_caption_filter_audit_log.sql"
    "create_view_active_creator_caption_restrictions_v.sql"
    "create_view_creator_allowed_profile_v.sql"
    "create_view_recent_caption_usage_v_if_missing.sql"
    "seed_feature_flag_caption_restrictions.sql"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "${SQL_DIR}/${file}" ]]; then
      log_error "Required SQL file not found: ${SQL_DIR}/${file}"
      exit 1
    fi
  done

  log_success "Prerequisites check passed"
}

execute_sql() {
  local sql_file="$1"
  local description="$2"
  local file_path="${SQL_DIR}/${sql_file}"

  log_info "Executing: ${description}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Would execute: ${sql_file}"
    return 0
  fi

  # Execute with error handling
  if bq query \
    --use_legacy_sql=false \
    --project_id="${BQ_PROJECT}" \
    --dataset_id="${BQ_DATASET}" \
    --format=none \
    < "${file_path}"; then
    log_success "${description} completed"
    return 0
  else
    log_error "${description} failed"
    return 1
  fi
}

verify_deployment() {
  log_info "Verifying deployment..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "[DRY RUN] Skipping verification"
    return 0
  fi

  local tables=("feature_flags" "creator_caption_restrictions" "creator_allowed_profile" "caption_filter_audit_log")
  local views=("active_creator_caption_restrictions_v" "creator_allowed_profile_v")

  # Check tables exist
  for table in "${tables[@]}"; do
    if bq show --project_id="${BQ_PROJECT}" "${BQ_DATASET}.${table}" &> /dev/null; then
      log_success "Table ${table} exists"
    else
      log_error "Table ${table} not found"
      return 1
    fi
  done

  # Check views exist
  for view in "${views[@]}"; do
    if bq show --project_id="${BQ_PROJECT}" "${BQ_DATASET}.${view}" &> /dev/null; then
      log_success "View ${view} exists"
    else
      log_error "View ${view} not found"
      return 1
    fi
  done

  # Check feature flag seed data
  local flag_count
  flag_count=$(bq query --use_legacy_sql=false --format=csv \
    "SELECT COUNT(*) FROM \`${FULL_DATASET}.feature_flags\` WHERE flag = 'caption_restrictions_enabled'" \
    | tail -n 1)

  if [[ "$flag_count" -ge 1 ]]; then
    log_success "Feature flag seed data present"
  else
    log_warning "Feature flag seed data missing (count: ${flag_count})"
  fi

  log_success "Deployment verification passed"
}

################################################################################
# Main Deployment Flow
################################################################################

main() {
  echo "========================================================================"
  echo "BigQuery Caption Restrictions Deployment"
  echo "========================================================================"
  echo "Project:  ${BQ_PROJECT}"
  echo "Dataset:  ${BQ_DATASET}"
  echo "Dry Run:  ${DRY_RUN}"
  echo "========================================================================"
  echo ""

  # Step 0: Prerequisites
  check_prerequisites

  # Deployment order (dependencies matter!)
  local deployment_steps=(
    "create_table_feature_flags.sql|Create feature_flags table"
    "create_table_creator_caption_restrictions.sql|Create creator_caption_restrictions table"
    "create_table_creator_allowed_profile.sql|Create creator_allowed_profile table"
    "create_table_caption_filter_audit_log.sql|Create caption_filter_audit_log table"
    "create_view_active_creator_caption_restrictions_v.sql|Create active_creator_caption_restrictions_v view"
    "create_view_creator_allowed_profile_v.sql|Create creator_allowed_profile_v view"
    "create_view_recent_caption_usage_v_if_missing.sql|Create recent_caption_usage_v fallback (if missing)"
    "seed_feature_flag_caption_restrictions.sql|Seed caption_restrictions feature flag"
  )

  # Execute deployment steps
  local step_num=1
  for step in "${deployment_steps[@]}"; do
    local sql_file="${step%%|*}"
    local description="${step##*|}"

    echo ""
    log_info "Step ${step_num}/${#deployment_steps[@]}: ${description}"

    if ! execute_sql "${sql_file}" "${description}"; then
      log_error "Deployment failed at step ${step_num}"
      exit 1
    fi

    ((step_num++))
  done

  # Verification
  echo ""
  verify_deployment

  # Success summary
  echo ""
  echo "========================================================================"
  log_success "Deployment completed successfully!"
  echo "========================================================================"
  echo ""
  echo "Next steps:"
  echo "  1. Verify feature flag: SELECT * FROM \`${FULL_DATASET}.feature_flags\` WHERE flag = 'caption_restrictions_enabled'"
  echo "  2. Add restrictions via Google Sheets sync: syncRestrictionsToBigQuery()"
  echo "  3. (Optional) Add allowed profiles via Google Sheets sync: syncCreatorAllowedProfileToBigQuery()"
  echo "  4. Test restriction filtering: Run caption-selector with test data"
  echo "  5. Monitor pool health: bq query < monitoring/queries/pool_health.sql"
  echo ""
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
