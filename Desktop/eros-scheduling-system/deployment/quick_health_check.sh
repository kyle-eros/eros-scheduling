#!/bin/bash

################################################################################
# EROS Scheduling System - Quick Health Check
#
# Description: Fast health check for daily operations
#   - System status validation
#   - Quick error detection
#   - Performance check
#   - Cost overview
#
# Usage: ./quick_health_check.sh [OPTIONS]
#
# Options:
#   --project-id ID      GCP project ID
#   --dataset NAME       BigQuery dataset
#   --verbose            Show detailed output
#   --json               Output in JSON format
#
# Exit Codes:
#   0 - Healthy
#   1 - Warnings detected
#   2 - Critical issues detected
#
# Author: DevOps Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Configuration
PROJECT_ID="${EROS_PROJECT_ID:-of-scheduler-proj}"
DATASET="${EROS_DATASET:-eros_scheduling_brain}"
VERBOSE=false
JSON_OUTPUT=false

# Thresholds
HEALTH_SCORE_WARNING=85
HEALTH_SCORE_CRITICAL=70
ERROR_RATE_WARNING=0.02
ERROR_RATE_CRITICAL=0.05
COST_WARNING=5.0
COST_CRITICAL=10.0

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Results tracking
WARNINGS=0
CRITICAL=0
CHECKS_PASSED=0
CHECKS_TOTAL=0

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

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
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_check() {
    local name=$1
    local status=$2
    local message=$3

    ((CHECKS_TOTAL++))

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        return
    fi

    case ${status} in
        PASS)
            echo -e "${GREEN}✓${NC} ${name}: ${message}"
            ((CHECKS_PASSED++))
            ;;
        WARN)
            echo -e "${YELLOW}⚠${NC} ${name}: ${message}"
            ((WARNINGS++))
            ;;
        FAIL)
            echo -e "${RED}✗${NC} ${name}: ${message}"
            ((CRITICAL++))
            ;;
    esac
}

log_info() {
    if [[ "${JSON_OUTPUT}" != "true" && "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

# ============================================================================
# HEALTH CHECK FUNCTIONS
# ============================================================================

check_system_connectivity() {
    log_info "Checking system connectivity..."

    # Check gcloud authentication
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        log_check "Authentication" "PASS" "gcloud authenticated"
    else
        log_check "Authentication" "FAIL" "Not authenticated with gcloud"
        return 1
    fi

    # Check project access
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null 2>&1; then
        log_check "Project Access" "PASS" "Can access project ${PROJECT_ID}"
    else
        log_check "Project Access" "FAIL" "Cannot access project ${PROJECT_ID}"
        return 1
    fi

    # Check BigQuery access
    if bq ls --project_id="${PROJECT_ID}" &>/dev/null; then
        log_check "BigQuery Access" "PASS" "Can access BigQuery"
    else
        log_check "BigQuery Access" "FAIL" "Cannot access BigQuery"
        return 1
    fi

    # Check dataset exists
    if bq show "${PROJECT_ID}:${DATASET}" &>/dev/null; then
        log_check "Dataset" "PASS" "Dataset ${DATASET} exists"
    else
        log_check "Dataset" "FAIL" "Dataset ${DATASET} not found"
        return 1
    fi

    return 0
}

check_table_health() {
    log_info "Checking table health..."

    local tables=(
        "caption_bank"
        "caption_bandit_stats"
        "active_caption_assignments"
        "caption_locks"
        "schedule_recommendations"
    )

    local missing_tables=()

    for table in "${tables[@]}"; do
        if bq show "${PROJECT_ID}:${DATASET}.${table}" &>/dev/null; then
            if [[ "${VERBOSE}" == "true" ]]; then
                log_check "Table: ${table}" "PASS" "Exists"
            fi
        else
            missing_tables+=("${table}")
        fi
    done

    if [[ ${#missing_tables[@]} -eq 0 ]]; then
        log_check "Tables" "PASS" "All ${#tables[@]} tables exist"
        return 0
    else
        log_check "Tables" "FAIL" "Missing tables: ${missing_tables[*]}"
        return 1
    fi
}

check_query_performance() {
    log_info "Checking query performance..."

    local query="
    SELECT
        COUNT(*) as total_queries,
        COUNTIF(total_slot_ms > 60000) as slow_queries,
        COUNTIF(error_result IS NOT NULL) as failed_queries,
        ROUND(AVG(total_slot_ms) / 1000, 2) as avg_execution_seconds
    FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    "

    local result=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "${query}" 2>/dev/null | tail -1)

    if [[ -z "${result}" ]]; then
        log_check "Query Performance" "WARN" "No query data available"
        return 0
    fi

    IFS=',' read -r total_queries slow_queries failed_queries avg_execution_seconds <<< "${result}"

    # Calculate error rate
    local error_rate=0
    if [[ ${total_queries} -gt 0 ]]; then
        error_rate=$(echo "scale=4; ${failed_queries} / ${total_queries}" | bc)
    fi

    # Check slow queries
    if [[ ${slow_queries} -gt 10 ]]; then
        log_check "Query Performance" "FAIL" "${slow_queries} slow queries (>60s) in last hour"
        return 1
    elif [[ ${slow_queries} -gt 5 ]]; then
        log_check "Query Performance" "WARN" "${slow_queries} slow queries detected"
    else
        log_check "Query Performance" "PASS" "Performance normal (${slow_queries} slow queries)"
    fi

    # Check error rate
    local error_rate_pct=$(echo "scale=2; ${error_rate} * 100" | bc)
    if (( $(echo "${error_rate} > ${ERROR_RATE_CRITICAL}" | bc -l) )); then
        log_check "Error Rate" "FAIL" "${error_rate_pct}% (threshold: 5%)"
        return 1
    elif (( $(echo "${error_rate} > ${ERROR_RATE_WARNING}" | bc -l) )); then
        log_check "Error Rate" "WARN" "${error_rate_pct}% (threshold: 2%)"
    else
        log_check "Error Rate" "PASS" "${error_rate_pct}%"
    fi

    return 0
}

check_cost() {
    log_info "Checking query costs..."

    local query="
    SELECT
        ROUND(SUM(total_bytes_billed) / POW(10, 12) * 5, 2) as cost_usd
    FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE DATE(creation_time) = CURRENT_DATE()
    "

    local cost=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "${query}" 2>/dev/null | tail -1)

    if [[ -z "${cost}" || "${cost}" == "cost_usd" ]]; then
        cost="0.00"
    fi

    if (( $(echo "${cost} > ${COST_CRITICAL}" | bc -l) )); then
        log_check "Daily Cost" "FAIL" "\$${cost} (threshold: \$${COST_CRITICAL})"
        return 1
    elif (( $(echo "${cost} > ${COST_WARNING}" | bc -l) )); then
        log_check "Daily Cost" "WARN" "\$${cost} (threshold: \$${COST_WARNING})"
    else
        log_check "Daily Cost" "PASS" "\$${cost}"
    fi

    return 0
}

check_caption_pool() {
    log_info "Checking caption pool..."

    local query="
    SELECT
        COUNT(DISTINCT cb.caption_id) as available_captions
    FROM \`${PROJECT_ID}.${DATASET}.caption_bank\` cb
    LEFT JOIN \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` aca
      ON cb.caption_id = aca.caption_id
      AND aca.expires_at > CURRENT_TIMESTAMP()
    WHERE aca.caption_id IS NULL
    "

    local available=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "${query}" 2>/dev/null | tail -1)

    if [[ -z "${available}" || "${available}" == "available_captions" ]]; then
        log_check "Caption Pool" "WARN" "Cannot determine caption pool size"
        return 0
    fi

    if [[ ${available} -lt 200 ]]; then
        log_check "Caption Pool" "FAIL" "${available} captions available (threshold: 200)"
        return 1
    elif [[ ${available} -lt 500 ]]; then
        log_check "Caption Pool" "WARN" "${available} captions available (threshold: 500)"
    else
        log_check "Caption Pool" "PASS" "${available} captions available"
    fi

    return 0
}

check_locks() {
    log_info "Checking caption locks..."

    local query="
    SELECT
        COUNT(*) as expired_locks
    FROM \`${PROJECT_ID}.${DATASET}.caption_locks\`
    WHERE expires_at < CURRENT_TIMESTAMP()
    "

    local expired=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "${query}" 2>/dev/null | tail -1)

    if [[ -z "${expired}" || "${expired}" == "expired_locks" ]]; then
        expired="0"
    fi

    if [[ ${expired} -gt 100 ]]; then
        log_check "Caption Locks" "FAIL" "${expired} expired locks (threshold: 100)"
        return 1
    elif [[ ${expired} -gt 10 ]]; then
        log_check "Caption Locks" "WARN" "${expired} expired locks (threshold: 10)"
    else
        log_check "Caption Locks" "PASS" "${expired} expired locks"
    fi

    return 0
}

check_recent_activity() {
    log_info "Checking recent activity..."

    local query="
    SELECT
        COUNT(*) as recent_assignments
    FROM \`${PROJECT_ID}.${DATASET}.active_caption_assignments\`
    WHERE assigned_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    "

    local assignments=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 "${query}" 2>/dev/null | tail -1)

    if [[ -z "${assignments}" || "${assignments}" == "recent_assignments" ]]; then
        log_check "Recent Activity" "WARN" "Cannot determine recent activity"
        return 0
    fi

    if [[ ${assignments} -eq 0 ]]; then
        log_check "Recent Activity" "WARN" "No caption assignments in last 24 hours"
    else
        log_check "Recent Activity" "PASS" "${assignments} assignments in last 24 hours"
    fi

    return 0
}

# ============================================================================
# MAIN HEALTH CHECK
# ============================================================================

run_health_checks() {
    if [[ "${JSON_OUTPUT}" != "true" ]]; then
        echo "========================================================================"
        echo "  EROS Scheduling System - Quick Health Check"
        echo "========================================================================"
        echo ""
        echo "Project: ${PROJECT_ID}"
        echo "Dataset: ${DATASET}"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    fi

    # Run all checks
    check_system_connectivity || true
    check_table_health || true
    check_query_performance || true
    check_cost || true
    check_caption_pool || true
    check_locks || true
    check_recent_activity || true

    # Calculate health score
    local health_score=100
    health_score=$((health_score - (WARNINGS * 5)))
    health_score=$((health_score - (CRITICAL * 20)))
    health_score=$((health_score < 0 ? 0 : health_score))

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        # Output JSON
        cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "project_id": "${PROJECT_ID}",
  "dataset": "${DATASET}",
  "health_score": ${health_score},
  "checks_passed": ${CHECKS_PASSED},
  "checks_total": ${CHECKS_TOTAL},
  "warnings": ${WARNINGS},
  "critical": ${CRITICAL},
  "status": "$(
    if [[ ${CRITICAL} -gt 0 ]]; then
        echo "CRITICAL"
    elif [[ ${WARNINGS} -gt 0 ]]; then
        echo "WARNING"
    else
        echo "HEALTHY"
    fi
  )"
}
EOF
    else
        # Output summary
        echo ""
        echo "========================================================================"
        echo "  Health Check Summary"
        echo "========================================================================"
        echo ""
        echo "Health Score: ${health_score}/100"
        echo "Checks Passed: ${CHECKS_PASSED}/${CHECKS_TOTAL}"
        echo "Warnings: ${WARNINGS}"
        echo "Critical Issues: ${CRITICAL}"
        echo ""

        if [[ ${CRITICAL} -gt 0 ]]; then
            echo -e "${RED}Status: CRITICAL - Immediate attention required${NC}"
            echo ""
            echo "Next Steps:"
            echo "  1. Review critical issues above"
            echo "  2. Check detailed logs: cat /var/log/eros/application/*.log"
            echo "  3. Consider rollback if deployment-related"
            echo "  4. Escalate if needed"
        elif [[ ${WARNINGS} -gt 0 ]]; then
            echo -e "${YELLOW}Status: WARNING - Monitoring recommended${NC}"
            echo ""
            echo "Next Steps:"
            echo "  1. Review warnings above"
            echo "  2. Monitor system for changes"
            echo "  3. Schedule maintenance if needed"
        else
            echo -e "${GREEN}Status: HEALTHY - All systems operational${NC}"
        fi
        echo ""
    fi

    # Return appropriate exit code
    if [[ ${CRITICAL} -gt 0 ]]; then
        return 2
    elif [[ ${WARNINGS} -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# ============================================================================
# EXECUTION
# ============================================================================

run_health_checks
exit $?
