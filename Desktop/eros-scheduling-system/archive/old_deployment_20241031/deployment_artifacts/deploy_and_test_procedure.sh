#!/bin/bash

# =============================================================================
# FINAL PROCEDURE DEPLOYMENT & TESTING SCRIPT
# =============================================================================
# Project: of-scheduler-proj
# Purpose: Deploy analyze_creator_performance and test with real data
# =============================================================================

set -e

PROJECT_ID="of-scheduler-proj"
DATASET="eros_scheduling_brain"
REGION="US"

echo "=========================================================================="
echo "STEP 1: DEPLOYING MISSING TVFs AND MAIN PROCEDURE"
echo "=========================================================================="

# Deploy TVFs and procedure
bq query \
  --project_id=$PROJECT_ID \
  --dataset_id=$DATASET \
  --use_legacy_sql=false \
  --location=$REGION \
  < /Users/kylemerriman/Desktop/eros-scheduling-system/deployment/analyze_creator_performance_complete.sql

echo "✓ Deployment completed successfully"
echo ""

echo "=========================================================================="
echo "STEP 2: FINDING ACTIVE CREATORS"
echo "=========================================================================="

# Find creators with sufficient data
CREATORS=$(bq query \
  --project_id=$PROJECT_ID \
  --format=csv \
  --use_legacy_sql=false \
  --location=$REGION \
  --max_rows=5 \
  << 'EOF'
SELECT
  page_name,
  COUNT(*) AS message_count,
  ROUND(SUM(earnings), 2) AS total_earnings
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND viewed_count > 0
GROUP BY page_name
ORDER BY total_earnings DESC
LIMIT 5;
EOF
)

echo "Available creators:"
echo "$CREATORS"
echo ""

echo "=========================================================================="
echo "STEP 3: EXECUTING PROCEDURE FOR TEST CREATOR"
echo "=========================================================================="

# Get first creator from the list (skip header)
TEST_CREATOR=$(echo "$CREATORS" | tail -n +2 | head -n 1 | cut -d',' -f1 | tr -d ' ')

if [ -z "$TEST_CREATOR" ]; then
  echo "ERROR: No creators found with sufficient data"
  exit 1
fi

echo "Testing with creator: $TEST_CREATOR"
echo ""

# Call procedure and capture JSON result
RESULT=$(bq query \
  --project_id=$PROJECT_ID \
  --format=json \
  --use_legacy_sql=false \
  --location=$REGION \
  << EOF
CALL \`of-scheduler-proj.eros_scheduling_brain\`.analyze_creator_performance(
  '$TEST_CREATOR',
  @performance_report
);

SELECT @performance_report AS performance_report;
EOF
)

echo "Procedure execution completed"
echo ""

echo "=========================================================================="
echo "STEP 4: PARSING AND DISPLAYING RESULTS"
echo "=========================================================================="

# Save raw JSON to file
echo "$RESULT" > /tmp/performance_report.json

# Pretty print the JSON
echo "Full Performance Report:"
echo "========================"
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"

echo ""
echo "=========================================================================="
echo "STEP 5: PERFORMANCE METRICS SUMMARY"
echo "=========================================================================="

# Extract and display key metrics
python3 << 'PYEOF'
import json
import sys

try:
    with open('/tmp/performance_report.json', 'r') as f:
        data = json.load(f)

    # Handle array response from BQ
    if isinstance(data, list) and len(data) > 0:
        report = data[0]
    else:
        report = data

    if isinstance(report, dict) and 'performance_report' in report:
        perf = json.loads(report['performance_report'])
    else:
        perf = report

    print(f"Creator: {perf.get('creator_name', 'N/A')}")
    print(f"Analysis Time: {perf.get('analysis_timestamp', 'N/A')}")
    print(f"Data Freshness: {perf.get('data_freshness', 'N/A')}")
    print()

    # Account Classification
    if 'account_classification' in perf:
        acc = perf['account_classification']
        print("ACCOUNT CLASSIFICATION:")
        print(f"  Size Tier: {acc.get('size_tier', 'N/A')}")
        print(f"  Avg Audience: {acc.get('avg_audience', 'N/A'):,}")
        print(f"  Total Revenue (90d): ${acc.get('total_revenue_period', 0):,.2f}")
        print(f"  Daily PPV Target: {acc.get('daily_ppv_target_min', 'N/A')} - {acc.get('daily_ppv_target_max', 'N/A')}")
        print()

    # Behavioral Segment
    if 'behavioral_segment' in perf:
        seg = perf['behavioral_segment']
        print("BEHAVIORAL SEGMENT:")
        print(f"  Segment: {seg.get('segment_label', 'N/A')}")
        print(f"  Avg RPR: ${seg.get('avg_rpr', 0):.6f}")
        print(f"  Avg Conversion: {seg.get('avg_conv', 0):.4f}")
        print(f"  Sample Size: {seg.get('sample_size', 'N/A')}")
        print()

    # Saturation
    if 'saturation' in perf:
        sat = perf['saturation']
        print("SATURATION METRICS:")
        print(f"  Saturation Score: {sat.get('saturation_score', 'N/A'):.2f}")
        print(f"  Risk Level: {sat.get('risk_level', 'N/A')}")
        print(f"  Recommended Action: {sat.get('recommended_action', 'N/A')}")
        print()

    # Top Triggers
    if 'psychological_trigger_analysis' in perf and perf['psychological_trigger_analysis']:
        print("TOP PSYCHOLOGICAL TRIGGERS (Top 3):")
        triggers = perf['psychological_trigger_analysis'][:3]
        for i, trig in enumerate(triggers, 1):
            print(f"  {i}. {trig.get('psychological_trigger', 'N/A')}")
            print(f"     RPR Lift: {trig.get('rpr_lift_pct', 0):.2f}%")
            print(f"     Conversion Lift: {trig.get('conv_lift_pct', 0):.2f}%")
            print(f"     Statistically Significant (RPR): {trig.get('rpr_stat_sig', False)}")
        print()

    # Top Categories
    if 'content_category_performance' in perf and perf['content_category_performance']:
        print("TOP CONTENT CATEGORIES (Top 3):")
        categories = perf['content_category_performance'][:3]
        for i, cat in enumerate(categories, 1):
            print(f"  {i}. {cat.get('content_category', 'N/A')} ({cat.get('price_tier', 'N/A')})")
            print(f"     Avg RPR: ${cat.get('avg_rpr', 0):.6f}")
            print(f"     Trend: {cat.get('trend_direction', 'N/A')} ({cat.get('trend_pct', 0):.1f}%)")
            print(f"     Messages: {cat.get('msg_count', 'N/A')}")
        print()

    # Best Days
    if 'day_of_week_patterns' in perf and perf['day_of_week_patterns']:
        print("DAY OF WEEK PERFORMANCE:")
        day_names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
        for day in perf['day_of_week_patterns'][:3]:
            day_idx = day.get('day_of_week_la', 0)
            day_name = day_names[day_idx - 1] if 1 <= day_idx <= 7 else f"Day {day_idx}"
            print(f"  {day_name}: RPR ${day.get('avg_rpr', 0):.6f} | Conv {day.get('avg_conv', 0):.4f}")
        print()

    # Best Hours
    if 'time_window_optimization' in perf and perf['time_window_optimization']:
        print("BEST TIME WINDOWS (Top 3):")
        for i, window in enumerate(perf['time_window_optimization'][:3], 1):
            hour = window.get('hour_24', 0)
            day_type = window.get('day_type', 'Unknown')
            print(f"  {i}. {hour:02d}:00 ({day_type})")
            print(f"     RPR: ${window.get('avg_rpr', 0):.6f} | Conv: {window.get('avg_conv', 0):.4f}")
        print()

except Exception as e:
    print(f"Error parsing results: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo "=========================================================================="
echo "DEPLOYMENT AND TESTING COMPLETE"
echo "=========================================================================="
echo ""
echo "Files created/updated:"
echo "  - /Users/kylemerriman/Desktop/eros-scheduling-system/deployment/analyze_creator_performance_complete.sql"
echo "  - /tmp/performance_report.json"
echo ""
