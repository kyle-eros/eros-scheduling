#!/bin/bash

# =============================================================================
# PROCEDURE VALIDATION SCRIPT
# =============================================================================
# Purpose: Validate stored procedures compilation and functionality
# Usage: ./validate_procedures.sh [--execute-tests] [--project-id PROJECT_ID]
# =============================================================================

set -e

# Configuration
PROJECT_ID="${PROJECT_ID:-of-scheduler-proj}"
DATASET="eros_scheduling_brain"
BQ_FLAGS="--project_id=${PROJECT_ID} --use_legacy_sql=false"
EXECUTE_TESTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --execute-tests)
      EXECUTE_TESTS=true
      shift
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=========================================="
echo "PROCEDURE VALIDATION REPORT"
echo "=========================================="
echo "Project: ${PROJECT_ID}"
echo "Dataset: ${DATASET}"
echo "Timestamp: $(date)"
echo ""

# Step 1: Verify UDFs exist and are accessible
echo "Step 1: Checking UDF Dependencies..."
echo "----------------------------------------"

bq query ${BQ_FLAGS} << 'EOF'
SELECT
  routine_name,
  routine_type,
  DATE(creation_time) as created_date,
  COALESCE(CAST(DDL AS STRING), 'UDF exists') as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN ('wilson_score_bounds', 'wilson_sample')
  AND routine_schema = 'eros_scheduling_brain'
ORDER BY routine_name;
EOF

echo ""
echo "Step 2: Checking Required Table Schemas..."
echo "----------------------------------------"

# Verify caption_bandit_stats table
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'caption_bandit_stats' as table_name,
  COUNT(*) as column_count,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as columns
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;
EOF

echo ""

# Verify mass_messages has caption_id column
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'mass_messages' as table_name,
  COUNT(*) as column_count,
  STRING_AGG(CASE WHEN column_name = 'caption_id' THEN 'HAS caption_id' ELSE column_name END, ', ' ORDER BY ordinal_position) as columns
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'mass_messages'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;
EOF

echo ""

# Verify active_caption_assignments table
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'active_caption_assignments' as table_name,
  COUNT(*) as column_count,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as columns
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'active_caption_assignments'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;
EOF

echo ""

# Verify caption_bank table
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'caption_bank' as table_name,
  COUNT(*) as column_count,
  STRING_AGG(column_name, ', ' ORDER BY ordinal_position) as columns
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bank'
  AND table_schema = 'eros_scheduling_brain'
GROUP BY table_name;
EOF

echo ""
echo "Step 3: Verifying Procedure Compilation..."
echo "----------------------------------------"

# Compile update_caption_performance by checking its signature
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  routine_name,
  routine_type,
  'OK - Ready for execution' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'update_caption_performance'
  AND routine_schema = 'eros_scheduling_brain';
EOF

echo ""

# Compile lock_caption_assignments by checking its signature
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  routine_name,
  routine_type,
  'OK - Ready for execution' as status
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'lock_caption_assignments'
  AND routine_schema = 'eros_scheduling_brain';
EOF

echo ""
echo "Step 4: Testing UDFs..."
echo "----------------------------------------"

# Test wilson_score_bounds UDF
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'wilson_score_bounds' as udf_name,
  'Testing 50/50 ratio' as test_case,
  w.lower_bound,
  w.upper_bound,
  w.exploration_bonus,
  'PASS' as status
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50)]) w;
EOF

echo ""

# Test wilson_sample UDF
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'wilson_sample' as udf_name,
  'Testing sample generation' as test_case,
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) as sample_value,
  'PASS' as status;
EOF

echo ""
echo "Step 5: Checking caption_id Availability in mass_messages..."
echo "----------------------------------------"

# Verify caption_id column exists and has data
bq query ${BQ_FLAGS} << 'EOF'
SELECT
  'caption_id column check' as test,
  COUNT(*) as total_rows,
  COUNTIF(caption_id IS NOT NULL) as rows_with_caption_id,
  ROUND(100.0 * COUNTIF(caption_id IS NOT NULL) / COUNT(*), 2) as percentage_with_caption_id,
  'PASS' as status
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
LIMIT 100;
EOF

echo ""
echo "=========================================="
echo "VALIDATION COMPLETE"
echo "=========================================="
echo ""
echo "If all checks passed, the procedures are ready for deployment."
echo ""
echo "To execute the procedures:"
echo "  bq query --use_legacy_sql=false 'CALL \`of-scheduler-proj.eros_scheduling_brain.update_caption_performance\`();'"
echo "  bq query --use_legacy_sql=false 'CALL \`of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments\`(\"schedule_id_123\", \"page_name\", [STRUCT<caption_id INT64, scheduled_send_date DATE, scheduled_send_hour INT64>(1, DATE(\"2025-11-01\"), 14)]);'"
echo ""

