#!/bin/bash
# =============================================================================
# EROS SCHEDULING SYSTEM - SCHEDULED QUERIES DEPLOYMENT SCRIPT
# =============================================================================
# Project: of-scheduler-proj
# Dataset: eros_scheduling_brain
# Purpose: Deploy all BigQuery scheduled queries for EROS automation
# Usage: ./deploy_scheduled_queries.sh [--dry-run] [--force]
# =============================================================================

set -euo pipefail

# Configuration
PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
LOCATION="us"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
DRY_RUN=false
FORCE=false

# Parse command line arguments
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [--dry-run] [--force]"
      echo ""
      echo "Options:"
      echo "  --dry-run    Show what would be deployed without making changes"
      echo "  --force      Skip confirmation prompts"
      echo "  --help       Show this help message"
      exit 0
      ;;
  esac
done

# Logging functions
log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
  log "Checking prerequisites..."

  # Check if bq CLI is installed
  if ! command -v bq &> /dev/null; then
    log_error "bq CLI not found. Please install Google Cloud SDK."
    exit 1
  fi

  # Check if gcloud is authenticated
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    log_error "Not authenticated with gcloud. Run: gcloud auth login"
    exit 1
  fi

  # Check if project exists
  if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    log_error "Project $PROJECT_ID not found or not accessible."
    exit 1
  fi

  # Set active project
  gcloud config set project "$PROJECT_ID" &> /dev/null

  log "Prerequisites check passed."
}

# Validate stored procedures exist
validate_procedures() {
  log "Validating stored procedures..."

  local procedures=(
    "update_caption_performance"
    "run_daily_automation"
    "sweep_expired_caption_locks"
  )

  for proc in "${procedures[@]}"; do
    if bq ls --routine --project_id="$PROJECT_ID" "$DATASET" | grep -q "$proc"; then
      log_info "✓ Procedure $proc exists"
    else
      log_error "✗ Procedure $proc not found. Deploy it first using stored_procedures.sql"
      exit 1
    fi
  done

  log "All required procedures validated."
}

# Create or update scheduled query
deploy_scheduled_query() {
  local name=$1
  local display_name=$2
  local query=$3
  local schedule=$4
  local timezone=$5

  log_info "Deploying scheduled query: $display_name"

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would create/update scheduled query: $name"
    log_info "  Schedule: $schedule"
    log_info "  Query: ${query:0:100}..."
    return 0
  fi

  # Check if scheduled query already exists
  local existing_config
  existing_config=$(bq ls --transfer_config \
    --transfer_location="$LOCATION" \
    --project_id="$PROJECT_ID" \
    --format=json 2>/dev/null | \
    jq -r ".[] | select(.displayName == \"$display_name\") | .name" | head -1)

  if [ -n "$existing_config" ]; then
    log_warning "Scheduled query '$display_name' already exists (ID: $existing_config)"

    if [ "$FORCE" = false ]; then
      read -p "Update existing scheduled query? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping $display_name"
        return 0
      fi
    fi

    # Update existing scheduled query
    log_info "Updating scheduled query..."
    bq update --transfer_config "$existing_config" \
      --update_credentials=false \
      --schedule="$schedule" \
      --display_name="$display_name" 2>&1 | tee -a "$LOG_FILE"

    log "✓ Updated scheduled query: $display_name"
  else
    # Create new scheduled query
    log_info "Creating new scheduled query..."

    bq mk --transfer_config \
      --project_id="$PROJECT_ID" \
      --data_source=scheduled_query \
      --display_name="$display_name" \
      --schedule="$schedule" \
      --target_dataset="$DATASET" \
      --params="{\"query\":\"$query\",\"destination_table_name_template\":\"\",\"write_disposition\":\"WRITE_TRUNCATE\",\"partitioning_field\":\"\"}" 2>&1 | tee -a "$LOG_FILE"

    log "✓ Created scheduled query: $display_name"
  fi
}

# Deploy all scheduled queries
deploy_all_queries() {
  log "========================================"
  log "DEPLOYING EROS SCHEDULED QUERIES"
  log "========================================"
  log "Project: $PROJECT_ID"
  log "Dataset: $DATASET"
  log "Location: $LOCATION"
  log "Dry Run: $DRY_RUN"
  log "========================================"
  echo ""

  # Query 1: Performance Feedback Loop
  deploy_scheduled_query \
    "eros-performance-feedback-loop" \
    "EROS: Caption Performance Updates" \
    "CALL \\\`${PROJECT_ID}.${DATASET}.update_caption_performance\\\`()" \
    "every 6 hours" \
    "America/Los_Angeles"

  # Query 2: Daily Automation Orchestrator
  deploy_scheduled_query \
    "eros-daily-automation" \
    "EROS: Daily Schedule Generation" \
    "CALL \\\`${PROJECT_ID}.${DATASET}.run_daily_automation\\\`(CURRENT_DATE('America/Los_Angeles'))" \
    "every day 03:05" \
    "America/Los_Angeles"

  # Query 3: Caption Lock Cleanup
  deploy_scheduled_query \
    "eros-lock-cleanup" \
    "EROS: Caption Lock Cleanup" \
    "CALL \\\`${PROJECT_ID}.${DATASET}.sweep_expired_caption_locks\\\`()" \
    "every 1 hours" \
    "America/Los_Angeles"

  log ""
  log "========================================"
  log "DEPLOYMENT COMPLETE"
  log "========================================"
}

# List existing scheduled queries
list_scheduled_queries() {
  log "Listing existing scheduled queries..."
  echo ""

  bq ls --transfer_config \
    --transfer_location="$LOCATION" \
    --project_id="$PROJECT_ID" \
    --format=pretty 2>&1 | tee -a "$LOG_FILE"
}

# Verify deployment
verify_deployment() {
  log ""
  log "========================================"
  log "VERIFYING DEPLOYMENT"
  log "========================================"

  local expected_queries=(
    "EROS: Caption Performance Updates"
    "EROS: Daily Schedule Generation"
    "EROS: Caption Lock Cleanup"
  )

  local all_found=true

  for query_name in "${expected_queries[@]}"; do
    if bq ls --transfer_config \
      --transfer_location="$LOCATION" \
      --project_id="$PROJECT_ID" \
      --format=json 2>/dev/null | \
      jq -e ".[] | select(.displayName == \"$query_name\")" > /dev/null; then
      log "✓ Found: $query_name"
    else
      log_error "✗ Missing: $query_name"
      all_found=false
    fi
  done

  if [ "$all_found" = true ]; then
    log ""
    log "${GREEN}✓ All scheduled queries deployed successfully!${NC}"
    log ""
    log "Next steps:"
    log "  1. Review scheduled queries in BigQuery console"
    log "  2. Test manual execution: bq query 'CALL \`${PROJECT_ID}.${DATASET}.run_daily_automation\`(CURRENT_DATE(\"America/Los_Angeles\"))'"
    log "  3. Monitor first automated runs"
    log "  4. Set up alerting based on automation_alerts table"
    log ""
    log "Deployment log saved to: $LOG_FILE"
  else
    log_error "Deployment incomplete. Check errors above."
    exit 1
  fi
}

# Confirmation prompt
confirm_deployment() {
  if [ "$FORCE" = true ]; then
    return 0
  fi

  log_warning "This will create/update scheduled queries in project: $PROJECT_ID"
  log_warning "Dataset: $DATASET"
  echo ""
  read -p "Continue with deployment? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user."
    exit 0
  fi
}

# Main execution
main() {
  log "Starting EROS scheduled queries deployment..."
  log "Log file: $LOG_FILE"
  echo ""

  check_prerequisites
  validate_procedures

  if [ "$DRY_RUN" = false ]; then
    confirm_deployment
  fi

  deploy_all_queries

  if [ "$DRY_RUN" = false ]; then
    list_scheduled_queries
    verify_deployment
  else
    log ""
    log "${YELLOW}DRY RUN COMPLETE - No changes made${NC}"
    log "Remove --dry-run flag to deploy for real"
  fi
}

# Run main function
main "$@"
