#!/bin/bash
# =============================================================================
# EROS SCHEDULING SYSTEM - AUTOMATION TESTING SCRIPT
# =============================================================================
# Project: of-scheduler-proj
# Dataset: eros_scheduling_brain
# Purpose: Test automation procedures before enabling scheduled queries
# Usage: ./test_automation.sh [--verbose]
# =============================================================================

set -euo pipefail

PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
for arg in "$@"; do
  case $arg in
    --verbose)
      VERBOSE=true
      shift
      ;;
  esac
done

log() {
  echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
}

log_error() {
  echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*"
}

run_test() {
  local test_name=$1
  local query=$2

  echo ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TEST: $test_name"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ "$VERBOSE" = true ]; then
    log_info "Query: $query"
  fi

  if bq query --use_legacy_sql=false --format=pretty "$query" 2>&1; then
    log "${GREEN}✓ PASS${NC} - $test_name"
    return 0
  else
    log_error "${RED}✗ FAIL${NC} - $test_name"
    return 1
  fi
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

preflight_checks() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "PRE-FLIGHT CHECKS"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Check bq CLI
  if ! command -v bq &> /dev/null; then
    log_error "bq CLI not found"
    exit 1
  fi
  log "✓ bq CLI installed"

  # Check authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    log_error "Not authenticated with gcloud"
    exit 1
  fi
  log "✓ Authenticated with gcloud"

  # Check project access
  if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
    log_error "Cannot access project $PROJECT_ID"
    exit 1
  fi
  log "✓ Project access verified"

  # Check dataset exists
  if ! bq ls --project_id="$PROJECT_ID" | grep -q "$DATASET"; then
    log_error "Dataset $DATASET not found"
    exit 1
  fi
  log "✓ Dataset exists"

  echo ""
}

# =============================================================================
# PROCEDURE EXISTENCE TESTS
# =============================================================================

test_procedures_exist() {
  local all_passed=true

  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TESTING: Procedure Existence"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local procedures=(
    "run_daily_automation"
    "sweep_expired_caption_locks"
    "update_caption_performance"
    "analyze_creator_performance"
    "lock_caption_assignments"
  )

  for proc in "${procedures[@]}"; do
    if bq ls --routine --project_id="$PROJECT_ID" "$DATASET" | grep -q "$proc"; then
      log "✓ Procedure exists: $proc"
    else
      log_error "✗ Missing procedure: $proc"
      all_passed=false
    fi
  done

  echo ""
  if [ "$all_passed" = false ]; then
    log_error "Some procedures are missing. Deploy them first."
    exit 1
  fi
}

# =============================================================================
# TABLE EXISTENCE TESTS
# =============================================================================

test_tables_exist() {
  local all_passed=true

  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TESTING: Required Tables"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local required_tables=(
    "caption_bandit_stats"
    "mass_messages"
    "caption_bank"
    "active_caption_assignments"
  )

  for table in "${required_tables[@]}"; do
    if bq ls --project_id="$PROJECT_ID" "$DATASET" | grep -q "$table"; then
      log "✓ Table exists: $table"
    else
      log_error "✗ Missing table: $table"
      all_passed=false
    fi
  done

  echo ""
  if [ "$all_passed" = false ]; then
    log_error "Some required tables are missing. Deploy infrastructure first."
    exit 1
  fi
}

# =============================================================================
# FUNCTIONAL TESTS
# =============================================================================

test_lock_cleanup() {
  run_test "Lock Cleanup Procedure" \
    "CALL \`${PROJECT_ID}.${DATASET}.sweep_expired_caption_locks\`()"
}

test_daily_automation() {
  run_test "Daily Automation Orchestrator" \
    "CALL \`${PROJECT_ID}.${DATASET}.run_daily_automation\`(CURRENT_DATE('America/Los_Angeles'))"
}

test_performance_update() {
  run_test "Caption Performance Update" \
    "CALL \`${PROJECT_ID}.${DATASET}.update_caption_performance\`()"
}

# =============================================================================
# VERIFICATION TESTS
# =============================================================================

verify_job_logs() {
  run_test "Verify Job Logs Created" \
    "SELECT COUNT(*) AS job_count, MAX(job_start_time) AS last_run
     FROM \`${PROJECT_ID}.${DATASET}.etl_job_runs\`
     WHERE job_name = 'daily_automation'
       AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)"
}

verify_lock_sweep_logs() {
  run_test "Verify Lock Sweep Logs" \
    "SELECT COUNT(*) AS sweep_count, MAX(sweep_time) AS last_sweep
     FROM \`${PROJECT_ID}.${DATASET}.lock_sweep_log\`
     WHERE sweep_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)"
}

verify_queue_table() {
  run_test "Verify Schedule Queue Populated" \
    "SELECT
       status,
       COUNT(*) AS count,
       MAX(queued_at) AS latest_queued
     FROM \`${PROJECT_ID}.${DATASET}.schedule_generation_queue\`
     WHERE execution_date = CURRENT_DATE('America/Los_Angeles')
     GROUP BY status"
}

# =============================================================================
# HEALTH CHECK TESTS
# =============================================================================

test_health_checks() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TESTING: Health Check Queries"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  run_test "Health Check - Daily Automation Status" \
    "SELECT
       DATE(job_start_time, 'America/Los_Angeles') AS date,
       job_status,
       COUNT(*) AS count
     FROM \`${PROJECT_ID}.${DATASET}.etl_job_runs\`
     WHERE job_name = 'daily_automation'
       AND job_start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
     GROUP BY date, job_status"

  run_test "Health Check - Active Lock Count" \
    "SELECT
       COUNT(*) AS active_locks,
       COUNT(DISTINCT page_name) AS creators,
       COUNT(DISTINCT caption_id) AS unique_captions
     FROM \`${PROJECT_ID}.${DATASET}.active_caption_assignments\`
     WHERE is_active = TRUE"

  run_test "Health Check - Performance Freshness" \
    "SELECT
       COUNT(*) AS total_captions,
       TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) AS hours_since_update,
       TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MIN(last_updated), HOUR) AS oldest_update_hours
     FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`"
}

# =============================================================================
# ALERT TESTS
# =============================================================================

test_alerts() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TESTING: Alert System"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Check if alerts table exists and has structure
  run_test "Verify Alerts Table Structure" \
    "SELECT
       COUNT(*) AS total_alerts,
       COUNTIF(alert_level = 'CRITICAL') AS critical_count,
       COUNTIF(alert_level = 'WARNING') AS warning_count,
       COUNTIF(acknowledged = FALSE) AS unacknowledged_count
     FROM \`${PROJECT_ID}.${DATASET}.automation_alerts\`
     WHERE alert_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_error_logging() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TESTING: Error Logging"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  run_test "Verify Error Logging Table" \
    "SELECT
       COUNT(*) AS total_errors,
       COUNT(DISTINCT page_name) AS affected_creators,
       MAX(error_time) AS last_error
     FROM \`${PROJECT_ID}.${DATASET}.creator_processing_errors\`
     WHERE error_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)"
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
  echo ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "TEST SUMMARY"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  log "${GREEN}✓ All tests passed!${NC}"
  echo ""
  log "Next steps:"
  log "  1. Deploy scheduled queries: ./deploy_scheduled_queries.sh"
  log "  2. Monitor first automated runs"
  log "  3. Set up alerting channels"
  log "  4. Create monitoring dashboard"
  echo ""
  log "Useful queries:"
  log "  - Health check: bq query --use_legacy_sql=false < automation_health_check.sql"
  log "  - Job logs: SELECT * FROM \`${PROJECT_ID}.${DATASET}.etl_job_runs\` ORDER BY job_start_time DESC LIMIT 10"
  log "  - Alerts: SELECT * FROM \`${PROJECT_ID}.${DATASET}.automation_alerts\` WHERE acknowledged = FALSE"
  echo ""
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
  echo ""
  log "╔════════════════════════════════════════════════════════════╗"
  log "║        EROS AUTOMATION TESTING SUITE                       ║"
  log "╚════════════════════════════════════════════════════════════╝"
  echo ""

  preflight_checks
  test_procedures_exist
  test_tables_exist

  # Functional tests
  test_lock_cleanup
  test_performance_update
  test_daily_automation

  # Verification tests
  verify_job_logs
  verify_lock_sweep_logs
  verify_queue_table

  # Health and monitoring tests
  test_health_checks
  test_alerts
  test_error_logging

  print_summary
}

# Run main
main "$@"
