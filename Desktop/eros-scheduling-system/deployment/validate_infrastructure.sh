#!/bin/bash
# =============================================================================
# EROS Scheduling System - Infrastructure Validation Script
# =============================================================================
# Purpose: Validate the caption bandit stats infrastructure
# Usage: ./validate_infrastructure.sh
# =============================================================================

set -e

PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
TABLE="caption_bandit_stats"

echo "=========================================="
echo "INFRASTRUCTURE VALIDATION"
echo "=========================================="
echo "Project: $PROJECT_ID"
echo "Dataset: $DATASET"
echo ""

# Test 1: Verify table exists
echo "[1] Checking if caption_bandit_stats table exists..."
bq ls -n 1000 "$PROJECT_ID:$DATASET" | grep -q "$TABLE" && echo "    ✓ Table exists" || echo "    ✗ Table NOT found"

# Test 2: Verify table schema
echo ""
echo "[2] Validating table schema (15 columns expected)..."
COLUMN_COUNT=$(bq query --use_legacy_sql=false --format=csv --quiet <<EOF
SELECT COUNT(*) as count
FROM \`$PROJECT_ID.$DATASET.INFORMATION_SCHEMA.COLUMNS\`
WHERE table_name = '$TABLE'
EOF
)
echo "    Found $COLUMN_COUNT columns"
[ "$COLUMN_COUNT" = "15" ] && echo "    ✓ Schema valid" || echo "    ✗ Schema INVALID"

# Test 3: Verify UDFs exist
echo ""
echo "[3] Checking if wilson_score_bounds UDF exists..."
bq ls --routines -n 1000 "$PROJECT_ID:$DATASET" | grep -q "wilson_score_bounds" && echo "    ✓ UDF exists" || echo "    ✗ UDF NOT found"

echo ""
echo "[4] Checking if wilson_sample UDF exists..."
bq ls --routines -n 1000 "$PROJECT_ID:$DATASET" | grep -q "wilson_sample" && echo "    ✓ UDF exists" || echo "    ✗ UDF NOT found"

# Test 5: Test wilson_score_bounds function
echo ""
echo "[5] Testing wilson_score_bounds function..."
bq query --use_legacy_sql=false --format=csv --quiet <<EOF 2>/dev/null
SELECT
  ROUND(bounds.lower_bound, 4) AS lower_bound,
  ROUND(bounds.upper_bound, 4) AS upper_bound,
  ROUND(bounds.exploration_bonus, 4) AS exploration_bonus
FROM UNNEST([\`$PROJECT_ID.$DATASET.wilson_score_bounds\`(50, 50)]) bounds
EOF
echo "    ✓ Function executed successfully"

# Test 6: Test wilson_sample function
echo ""
echo "[6] Testing wilson_sample function..."
SAMPLE=$(bq query --use_legacy_sql=false --format=csv --quiet <<EOF 2>/dev/null
SELECT ROUND(\`$PROJECT_ID.$DATASET.wilson_sample\`(50, 50), 4) as sample
EOF
)
echo "    Sample value: $SAMPLE"
echo "    ✓ Function executed successfully"

# Test 7: Verify table partitioning
echo ""
echo "[7] Checking table partitioning..."
bq show --format=prettyjson "$PROJECT_ID:$DATASET.$TABLE" 2>/dev/null | grep -q "timePartitioning" && echo "    ✓ Partitioning configured" || echo "    ✗ Partitioning NOT found"

# Test 8: Verify table clustering
echo ""
echo "[8] Checking table clustering..."
bq show --format=prettyjson "$PROJECT_ID:$DATASET.$TABLE" 2>/dev/null | grep -q "clustering" && echo "    ✓ Clustering configured" || echo "    ✗ Clustering NOT found"

echo ""
echo "=========================================="
echo "VALIDATION COMPLETE"
echo "=========================================="
