#!/bin/bash

# ===============================================================================
# EROS Scheduling System - SQL Validation Test Suite Runner
# ===============================================================================
# Purpose: Execute SQL validation tests via BigQuery command-line
# Author: SQL Development Team
# Created: 2025-10-31
# Version: 1.0
#
# DESCRIPTION:
# This script runs the SQL validation suite against BigQuery production environment.
# It executes all 5 test procedures and reports pass/fail status.
#
# PREREQUISITES:
# 1. Google Cloud SDK installed (gcloud, bq commands available)
# 2. Authenticated to GCP project: of-scheduler-proj
# 3. Access to dataset: eros_scheduling_brain
# 4. Network connectivity to BigQuery API
#
# USAGE:
# ./run_validation_tests.sh                    # Run all tests
# ./run_validation_tests.sh --test wilson      # Run specific test
# ./run_validation_tests.sh --verbose          # Show detailed output
# ./run_validation_tests.sh --help             # Show help
# ===============================================================================

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration
PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
SQL_FILE="$(cd "$(dirname "$0")" && pwd)/sql_validation_suite.sql"
LOG_FILE="$(cd "$(dirname "$0")" && pwd)/test_results_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         EROS SCHEDULING SYSTEM - SQL VALIDATION TEST SUITE RUNNER               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Parse command-line arguments
VERBOSE=false
SPECIFIC_TEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test|-t)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v           Show detailed BigQuery output"
            echo "  --test, -t TEST_NAME    Run specific test only"
            echo "                          Options: wilson, locking, performance, stability, timeout"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Run all tests"
            echo "  $0 --verbose            # Run all tests with detailed output"
            echo "  $0 --test wilson        # Run only Wilson Score test"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check prerequisites
echo -e "${BLUE}[1/4]${NC} Checking prerequisites..."

# Check if bq command exists
if ! command -v bq &> /dev/null; then
    echo -e "${RED}ERROR: 'bq' command not found. Please install Google Cloud SDK.${NC}"
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "${GREEN}  ✓ BigQuery CLI found${NC}"

# Check if SQL file exists
if [[ ! -f "$SQL_FILE" ]]; then
    echo -e "${RED}ERROR: SQL file not found: $SQL_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ SQL validation suite found${NC}"

# Check authentication
if ! bq ls --project_id="$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Not authenticated or no access to project: $PROJECT_ID${NC}"
    echo "Run: gcloud auth login"
    exit 1
fi
echo -e "${GREEN}  ✓ Authenticated to project: $PROJECT_ID${NC}"

# Check dataset exists
if ! bq ls --project_id="$PROJECT_ID" "$DATASET" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Dataset not found: $DATASET${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Dataset accessible: $DATASET${NC}"

echo ""

# Function to run individual test
run_individual_test() {
    local test_name=$1
    local test_proc=$2

    echo -e "${BLUE}Running Test: $test_name...${NC}"

    local start_time=$(date +%s)
    local query="CALL \`$PROJECT_ID.$DATASET.$test_proc\`();"

    if [[ "$VERBOSE" == "true" ]]; then
        bq query --use_legacy_sql=false --project_id="$PROJECT_ID" "$query" 2>&1 | tee -a "$LOG_FILE"
        local result=${PIPESTATUS[0]}
    else
        bq query --use_legacy_sql=false --project_id="$PROJECT_ID" --quiet --format=none "$query" >> "$LOG_FILE" 2>&1
        local result=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}  ✓ PASSED${NC} (${duration}s)"
        return 0
    else
        echo -e "${RED}  ✗ FAILED${NC} (${duration}s)"
        if [[ "$VERBOSE" == "false" ]]; then
            echo -e "${YELLOW}  See log for details: $LOG_FILE${NC}"
        fi
        return 1
    fi
}

# Step 2: Deploy test procedures
echo -e "${BLUE}[2/4]${NC} Deploying test procedures to BigQuery..."

if [[ "$VERBOSE" == "true" ]]; then
    bq query --use_legacy_sql=false --project_id="$PROJECT_ID" < "$SQL_FILE" 2>&1 | tee -a "$LOG_FILE"
    deploy_result=${PIPESTATUS[0]}
else
    bq query --use_legacy_sql=false --project_id="$PROJECT_ID" --quiet < "$SQL_FILE" >> "$LOG_FILE" 2>&1
    deploy_result=$?
fi

if [[ $deploy_result -ne 0 ]]; then
    echo -e "${RED}ERROR: Failed to deploy test procedures${NC}"
    echo -e "${YELLOW}See log: $LOG_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Test procedures deployed successfully${NC}"
echo ""

# Step 3: Run tests
echo -e "${BLUE}[3/4]${NC} Executing validation tests..."
echo ""

test_count=0
passed_count=0

# Run specific test or all tests
if [[ -n "$SPECIFIC_TEST" ]]; then
    case "$SPECIFIC_TEST" in
        wilson)
            run_individual_test "Wilson Score Bounds Accuracy" "test_wilson_score" && ((passed_count++)) || true
            ((test_count++))
            ;;
        locking)
            run_individual_test "Caption Locking Race Condition" "test_caption_locking" && ((passed_count++)) || true
            ((test_count++))
            ;;
        performance)
            run_individual_test "Performance Feedback Loop Speed" "test_performance_feedback_speed" && ((passed_count++)) || true
            ((test_count++))
            ;;
        stability)
            run_individual_test "Account Size Classification Stability" "test_account_size_stability" && ((passed_count++)) || true
            ((test_count++))
            ;;
        timeout)
            run_individual_test "Query Timeout Enforcement" "test_query_timeouts" && ((passed_count++)) || true
            ((test_count++))
            ;;
        *)
            echo -e "${RED}Unknown test: $SPECIFIC_TEST${NC}"
            echo "Valid options: wilson, locking, performance, stability, timeout"
            exit 1
            ;;
    esac
else
    # Run all tests
    run_individual_test "Wilson Score Bounds Accuracy" "test_wilson_score" && ((passed_count++)) || true
    ((test_count++))
    echo ""

    run_individual_test "Caption Locking Race Condition" "test_caption_locking" && ((passed_count++)) || true
    ((test_count++))
    echo ""

    run_individual_test "Performance Feedback Loop Speed" "test_performance_feedback_speed" && ((passed_count++)) || true
    ((test_count++))
    echo ""

    run_individual_test "Account Size Classification Stability" "test_account_size_stability" && ((passed_count++)) || true
    ((test_count++))
    echo ""

    run_individual_test "Query Timeout Enforcement" "test_query_timeouts" && ((passed_count++)) || true
    ((test_count++))
    echo ""
fi

# Step 4: Report results
echo -e "${BLUE}[4/4]${NC} Test Results Summary"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

failed_count=$((test_count - passed_count))

if [[ $failed_count -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo -e "${GREEN}$passed_count of $test_count tests passed successfully${NC}"
    echo ""
    echo -e "${GREEN}DEPLOYMENT STATUS: ✓ Ready for Production${NC}"
    echo "All critical issues validated and functioning correctly."
    EXIT_CODE=0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo -e "${YELLOW}$passed_count of $test_count tests passed ($failed_count failed)${NC}"
    echo ""
    echo -e "${RED}DEPLOYMENT STATUS: ✗ NOT READY${NC}"
    echo "Fix failing tests before deploying to production."
    EXIT_CODE=1
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}Detailed log saved to: $LOG_FILE${NC}"
echo ""

# Additional information
echo -e "${BLUE}Test Coverage:${NC}"
echo "  • Issue 1: Wilson Score Calculation Error"
echo "  • Issue 3: Race Condition in Caption Locking"
echo "  • Issue 5: Performance Feedback Loop O(n²) Complexity"
echo "  • Issue 6: Account Size Classification Instability"
echo "  • Issue 7: Missing BigQuery Query Timeouts"
echo ""

if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Review test results log: $LOG_FILE"
    echo "  2. Proceed with deployment following the deployment guide"
    echo "  3. Monitor production metrics for 24-48 hours"
    echo "  4. Run validation tests daily for the first week"
else
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Review detailed error log: $LOG_FILE"
    echo "  2. Fix failing tests in sql_validation_suite.sql"
    echo "  3. Re-run tests: $0"
    echo "  4. Consult COMPREHENSIVE_FIX_IMPLEMENTATION_PROMPT.md for details"
fi

echo ""
exit $EXIT_CODE
