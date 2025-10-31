#!/bin/bash

################################################################################
# EROS Scheduling System - Deployment Package Verification Script
#
# Description: Verifies all deployment files are present and valid
#
# Usage: ./verify_deployment_package.sh
#
# Author: Deployment Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "=========================================================="
echo "  EROS Scheduling System - Deployment Package Verification"
echo "=========================================================="
echo ""

PASS=0
FAIL=0

# Function to check file
check_file() {
    local file=$1
    local type=$2

    if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
        echo -e "${GREEN}✓${NC} ${file} - ${type}"
        ((PASS++))

        # Check if executable files have execute permission
        if [[ "${file}" == *.sh ]]; then
            if [[ -x "${SCRIPT_DIR}/${file}" ]]; then
                echo -e "  ${GREEN}✓${NC} Executable permissions set"
            else
                echo -e "  ${RED}✗${NC} Missing executable permissions"
                ((FAIL++))
            fi
        fi
    else
        echo -e "${RED}✗${NC} ${file} - MISSING"
        ((FAIL++))
    fi
}

# Check documentation files
echo "Checking Documentation Files:"
echo "----------------------------"
check_file "PRE_DEPLOYMENT_CHECKLIST.md" "Deployment checklist and procedures"
check_file "README.md" "Complete documentation"
check_file "QUICKSTART.md" "Quick start guide"
echo ""

# Check deployment scripts
echo "Checking Deployment Scripts:"
echo "----------------------------"
check_file "backup_tables.sh" "Backup automation script"
check_file "deploy_phase1.sh" "Phase 1 deployment (critical fixes)"
check_file "deploy_phase2.sh" "Phase 2 deployment (optimizations)"
check_file "rollback.sh" "Emergency rollback script"
echo ""

# Check monitoring files
echo "Checking Monitoring Files:"
echo "----------------------------"
check_file "monitor_deployment.sql" "Health check and monitoring queries"
echo ""

# Verify script syntax
echo "Verifying Script Syntax:"
echo "----------------------------"

for script in backup_tables.sh deploy_phase1.sh deploy_phase2.sh rollback.sh; do
    if bash -n "${SCRIPT_DIR}/${script}" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ${script} - Syntax valid"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} ${script} - Syntax errors"
        ((FAIL++))
    fi
done
echo ""

# Check file sizes (basic sanity check)
echo "Checking File Sizes:"
echo "----------------------------"

declare -A expected_sizes=(
    ["backup_tables.sh"]=10000
    ["deploy_phase1.sh"]=15000
    ["deploy_phase2.sh"]=20000
    ["rollback.sh"]=15000
    ["monitor_deployment.sql"]=20000
    ["PRE_DEPLOYMENT_CHECKLIST.md"]=10000
    ["README.md"]=8000
)

for file in "${!expected_sizes[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
        size=$(wc -c < "${SCRIPT_DIR}/${file}" | tr -d ' ')
        min_size=${expected_sizes[$file]}

        if [[ ${size} -ge ${min_size} ]]; then
            echo -e "${GREEN}✓${NC} ${file} - $(numfmt --to=iec-i --suffix=B ${size})"
            ((PASS++))
        else
            echo -e "${YELLOW}⚠${NC} ${file} - Only $(numfmt --to=iec-i --suffix=B ${size}) (expected >${min_size})"
        fi
    fi
done
echo ""

# Check for required tools
echo "Checking System Prerequisites:"
echo "----------------------------"

if command -v bq &> /dev/null; then
    echo -e "${GREEN}✓${NC} bq (BigQuery CLI) - $(bq version | head -1)"
    ((PASS++))
else
    echo -e "${RED}✗${NC} bq (BigQuery CLI) - NOT FOUND"
    echo -e "  Install: https://cloud.google.com/sdk/docs/install"
    ((FAIL++))
fi

if command -v gsutil &> /dev/null; then
    echo -e "${GREEN}✓${NC} gsutil (Cloud Storage) - $(gsutil version | head -1)"
    ((PASS++))
else
    echo -e "${RED}✗${NC} gsutil (Cloud Storage) - NOT FOUND"
    ((FAIL++))
fi

if command -v gcloud &> /dev/null; then
    echo -e "${GREEN}✓${NC} gcloud - $(gcloud version | grep 'Google Cloud SDK' | head -1)"
    ((PASS++))
else
    echo -e "${RED}✗${NC} gcloud - NOT FOUND"
    ((FAIL++))
fi
echo ""

# Summary
echo "=========================================================="
echo "  Verification Summary"
echo "=========================================================="
echo ""
echo -e "Total Checks: $((PASS + FAIL))"
echo -e "${GREEN}Passed: ${PASS}${NC}"
echo -e "${RED}Failed: ${FAIL}${NC}"
echo ""

if [[ ${FAIL} -eq 0 ]]; then
    echo -e "${GREEN}✓ Deployment package verification PASSED${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review PRE_DEPLOYMENT_CHECKLIST.md"
    echo "  2. Set environment variables:"
    echo "     export EROS_PROJECT_ID=\"your-project-id\""
    echo "     export EROS_DATASET=\"eros_platform\""
    echo "  3. Start deployment: ./backup_tables.sh"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Deployment package verification FAILED${NC}"
    echo ""
    echo "Please resolve the issues above before proceeding."
    echo ""
    exit 1
fi
