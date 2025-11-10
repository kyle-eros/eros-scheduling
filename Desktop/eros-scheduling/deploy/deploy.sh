#!/bin/bash

# EROS Max AI System - Deployment Script
# Deploys infrastructure and validates system components

set -e  # Exit on error

echo "========================================"
echo "EROS Max AI System - Deployment"
echo "Version: 2.0"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="of-scheduler-proj"
DATASET_ID="eros_scheduling_brain"
PYTHON_VERSION="3.11"

# Step 1: Check Prerequisites
echo "Step 1: Checking prerequisites..."

# Check Python version
if ! python3 --version | grep -q "$PYTHON_VERSION"; then
    echo -e "${RED}✗ Python $PYTHON_VERSION required${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python version OK${NC}"

# Check gcloud CLI
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}✗ gcloud CLI not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ gcloud CLI found${NC}"

# Check bq CLI
if ! command -v bq &> /dev/null; then
    echo -e "${RED}✗ bq CLI not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ bq CLI found${NC}"

echo ""

# Step 2: Set GCP Project
echo "Step 2: Setting GCP project..."
gcloud config set project $PROJECT_ID
echo -e "${GREEN}✓ Project set to $PROJECT_ID${NC}"
echo ""

# Step 3: Create Python Virtual Environment
echo "Step 3: Setting up Python environment..."

if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

source venv/bin/activate
echo -e "${GREEN}✓ Virtual environment activated${NC}"

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt
echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# Step 4: Deploy BigQuery Infrastructure
echo "Step 4: Deploying BigQuery infrastructure..."

bq query --use_legacy_sql=false < sql/infrastructure/tables.sql

echo -e "${GREEN}✓ BigQuery tables created${NC}"
echo ""

# Step 5: Validate Existing Core Tables
echo "Step 5: Validating core tables..."

CORE_TABLES=("mass_messages" "caption_bank" "vault_matrix" "active_creators")

for table in "${CORE_TABLES[@]}"; do
    if bq show "$PROJECT_ID:$DATASET_ID.$table" &> /dev/null; then
        echo -e "${GREEN}✓ $table exists${NC}"
    else
        echo -e "${YELLOW}⚠  $table not found - this is a critical table${NC}"
    fi
done

echo ""

# Step 6: Create Output Directory
echo "Step 6: Creating output directories..."

mkdir -p output
mkdir -p logs

echo -e "${GREEN}✓ Output directories created${NC}"
echo ""

# Step 7: Test Python Modules
echo "Step 7: Testing Python modules..."

python3 -c "from python.analytics.performance_engine import PerformanceEngine; print('✓ Performance Engine')"
python3 -c "from python.caption.contextual_selector import ContextualCaptionSelector; print('✓ Caption Selector')"
python3 -c "from python.analytics.eros_scoring import EROSScoring; print('✓ EROS Scoring')"
python3 -c "from python.orchestration.batch_processor import BatchProcessor; print('✓ Batch Processor')"
python3 -c "from python.export.csv_formatter import ScheduleCSVFormatter; print('✓ CSV Formatter')"
python3 -c "from python.export.analysis_report import AnalysisReportGenerator; print('✓ Report Generator')"

echo -e "${GREEN}✓ All Python modules OK${NC}"
echo ""

# Step 8: Test BigQuery Connection
echo "Step 8: Testing BigQuery connection..."

python3 << EOF
from google.cloud import bigquery

client = bigquery.Client(project="$PROJECT_ID")
query = "SELECT COUNT(*) as count FROM \`$PROJECT_ID.$DATASET_ID.mass_messages\` LIMIT 1"

try:
    result = client.query(query).result()
    print("✓ BigQuery connection successful")
except Exception as e:
    print(f"✗ BigQuery connection failed: {e}")
    exit(1)
EOF

echo ""

# Step 9: Deployment Summary
echo "========================================"
echo "Deployment Summary"
echo "========================================"
echo ""
echo -e "${GREEN}✓ Infrastructure deployed${NC}"
echo -e "${GREEN}✓ Python environment configured${NC}"
echo -e "${GREEN}✓ BigQuery tables created${NC}"
echo -e "${GREEN}✓ All modules validated${NC}"
echo ""
echo "Next Steps:"
echo "1. Review agent specifications in agents/"
echo "2. Test with single creator: python3 python/orchestration/agent_coordinator.py --page_name <creator>"
echo "3. Run batch processing: python3 python/orchestration/batch_processor.py"
echo ""
echo -e "${GREEN}✓ EROS Max AI System ready for production!${NC}"
echo ""
