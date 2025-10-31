#!/bin/bash

################################################################################
# EROS Scheduling System - Phase 2 Deployment Script
#
# Description: Deploys performance optimizations
#   - Performance feedback loop optimization
#   - Account size classification fix
#   - Query timeout configuration
#   - Performance benchmarking
#
# Usage: ./deploy_phase2.sh [PROJECT_ID] [DATASET]
#
# Requirements:
#   - Phase 1 deployment completed successfully
#   - bq CLI installed and authenticated
#   - Write permissions to BigQuery
#
# Author: Deployment Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_benchmark() {
    echo -e "${MAGENTA}[BENCHMARK]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration
DEPLOYMENT_TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
LOG_DIR="/tmp/eros_deployment_phase2_${DEPLOYMENT_TIMESTAMP}"
BENCHMARK_FILE="${LOG_DIR}/performance_benchmarks.json"
mkdir -p "${LOG_DIR}"

# Parse arguments
PROJECT_ID="${1:-}"
DATASET="${2:-}"

# Get project ID
get_project_id() {
    if [[ -n "${PROJECT_ID}" ]]; then
        echo "${PROJECT_ID}"
    elif [[ -n "${EROS_PROJECT_ID:-}" ]]; then
        echo "${EROS_PROJECT_ID}"
    else
        local gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "${gcloud_project}" ]]; then
            echo "${gcloud_project}"
        else
            log_error "Project ID not provided"
            exit 1
        fi
    fi
}

# Get dataset
get_dataset() {
    if [[ -n "${DATASET}" ]]; then
        echo "${DATASET}"
    elif [[ -n "${EROS_DATASET:-}" ]]; then
        echo "${EROS_DATASET}"
    else
        echo "eros_platform"
    fi
}

PROJECT_ID=$(get_project_id)
DATASET=$(get_dataset)

# Benchmark tracking
declare -A BENCHMARK_BEFORE
declare -A BENCHMARK_AFTER

# Execute query with timing
execute_query_timed() {
    local description=$1
    local query=$2
    local log_file="${LOG_DIR}/$(echo "${description}" | tr ' ' '_' | tr '[:upper:]' '[:lower:]').log"

    log_info "${description}"

    local start_time=$(date +%s%N)

    if echo "${query}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --format=pretty \
        --max_rows=10 > "${log_file}" 2>&1; then

        local end_time=$(date +%s%N)
        local duration_ms=$(( (end_time - start_time) / 1000000 ))

        log_success "  Completed in ${duration_ms}ms"
        echo "${duration_ms}"
        return 0
    else
        log_error "  Failed - see ${log_file}"
        cat "${log_file}"
        echo "0"
        return 1
    fi
}

# Execute query
execute_query() {
    local description=$1
    local query=$2

    execute_query_timed "${description}" "${query}" > /dev/null
    return $?
}

# Run benchmark query
benchmark_query() {
    local name=$1
    local query=$2
    local phase=$3  # "before" or "after"

    log_benchmark "Running benchmark: ${name} (${phase})"

    local start_time=$(date +%s%N)

    local result=$(echo "${query}" | bq query \
        --use_legacy_sql=false \
        --project_id="${PROJECT_ID}" \
        --format=csv \
        --max_rows=1 2>/dev/null | tail -n 1 || echo "ERROR")

    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    if [[ "${phase}" == "before" ]]; then
        BENCHMARK_BEFORE["${name}"]="${duration_ms}"
    else
        BENCHMARK_AFTER["${name}"]="${duration_ms}"
    fi

    log_benchmark "  ${name}: ${duration_ms}ms"

    return 0
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found"
        exit 1
    fi

    if ! bq show "${PROJECT_ID}:${DATASET}" &> /dev/null; then
        log_error "Dataset ${PROJECT_ID}:${DATASET} not found"
        exit 1
    fi

    # Verify Phase 1 deployment completed
    log_info "Verifying Phase 1 deployment..."

    local required_objects=(
        "caption_scores_corrected"
        "select_caption_thompson_sampling"
        "caption_locks"
        "validate_input"
    )

    for obj in "${required_objects[@]}"; do
        if ! bq ls "${PROJECT_ID}:${DATASET}" | grep -q "${obj}"; then
            log_error "Phase 1 object not found: ${obj}"
            log_error "Please complete Phase 1 deployment first"
            exit 1
        fi
    done

    log_success "Prerequisites check passed"
}

################################################################################
# Pre-Deployment Benchmarks
################################################################################
run_pre_deployment_benchmarks() {
    log_step "Running Pre-Deployment Benchmarks"

    # Benchmark 1: Caption selection query performance
    benchmark_query "caption_selection" \
        "SELECT caption_id FROM \`${PROJECT_ID}.${DATASET}.caption_bank\` ORDER BY RAND() LIMIT 1" \
        "before"

    # Benchmark 2: Wilson score calculation
    benchmark_query "wilson_score_calc" \
        "SELECT AVG(wilson_score_lower_bound) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`" \
        "before"

    # Benchmark 3: Account classification query
    benchmark_query "account_classification" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` GROUP BY account_id LIMIT 100" \
        "before"

    # Benchmark 4: Caption stats update
    benchmark_query "stats_update" \
        "SELECT caption_id, total_views, engagement_count FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` ORDER BY total_views DESC LIMIT 100" \
        "before"

    log_success "Pre-deployment benchmarks completed"
}

################################################################################
# Optimization 1: Performance Feedback Loop
################################################################################
deploy_feedback_loop_optimization() {
    log_step "Deploying Performance Feedback Loop Optimization"

    # Create optimized feedback loop with batching
    local feedback_procedure="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.update_caption_stats_batch\`(
  IN batch_size INT64
)
BEGIN
  -- Create temporary table for batch updates
  CREATE TEMP TABLE pending_updates AS
  SELECT
    caption_id,
    COUNT(*) as view_increment,
    SUM(CAST(engaged AS INT64)) as engagement_increment
  FROM \`${PROJECT_ID}.${DATASET}.caption_performance_log\`
  WHERE processed = FALSE
  GROUP BY caption_id
  LIMIT batch_size;

  -- Update caption_bandit_stats in batch
  UPDATE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` AS stats
  SET
    total_views = total_views + updates.view_increment,
    engagement_count = engagement_count + updates.engagement_increment,
    last_updated = CURRENT_TIMESTAMP()
  FROM pending_updates AS updates
  WHERE stats.caption_id = updates.caption_id;

  -- Recalculate Wilson scores for updated captions only
  UPDATE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` AS stats
  SET wilson_score_lower_bound = (
    SELECT wilson_score_lower_bound
    FROM \`${PROJECT_ID}.${DATASET}.caption_scores_corrected\` AS scores
    WHERE scores.caption_id = stats.caption_id
  )
  WHERE stats.caption_id IN (SELECT caption_id FROM pending_updates);

  -- Mark as processed
  UPDATE \`${PROJECT_ID}.${DATASET}.caption_performance_log\`
  SET processed = TRUE
  WHERE caption_id IN (SELECT caption_id FROM pending_updates);

  -- Clean up
  DROP TABLE pending_updates;
END;
"

    execute_query "Creating batch feedback loop procedure" "${feedback_procedure}"

    # Create materialized view for frequently accessed stats
    local materialized_view="
CREATE MATERIALIZED VIEW IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.caption_stats_summary\`
PARTITION BY DATE(last_updated)
CLUSTER BY caption_id
AS
SELECT
  caption_id,
  total_views,
  engagement_count,
  wilson_score_lower_bound,
  SAFE_DIVIDE(engagement_count, total_views) as engagement_rate,
  last_updated,
  -- Performance tier classification
  CASE
    WHEN wilson_score_lower_bound >= 0.7 THEN 'high'
    WHEN wilson_score_lower_bound >= 0.4 THEN 'medium'
    ELSE 'low'
  END as performance_tier
FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
WHERE total_views > 0;
"

    execute_query "Creating materialized view for caption stats" "${materialized_view}"

    # Create incremental update procedure
    local incremental_update="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.incremental_caption_update\`(
  IN caption_id INT64,
  IN view_increment INT64,
  IN engagement_increment INT64
)
BEGIN
  -- Atomic increment operation
  UPDATE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
  SET
    total_views = total_views + view_increment,
    engagement_count = engagement_count + engagement_increment,
    last_updated = CURRENT_TIMESTAMP()
  WHERE caption_id = caption_id;

  -- Recalculate Wilson score
  UPDATE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` AS stats
  SET wilson_score_lower_bound = GREATEST(0.0, LEAST(1.0,
    CASE
      WHEN stats.total_views = 0 THEN 0.0
      WHEN stats.total_views < 10 THEN 0.0
      ELSE
        (stats.engagement_count + 1.9208) / (stats.total_views + 3.8416)
        - 1.96 * SQRT((stats.engagement_count * (stats.total_views - stats.engagement_count)) / stats.total_views + 0.9604)
        / (stats.total_views + 3.8416)
    END
  ))
  WHERE stats.caption_id = caption_id;
END;
"

    execute_query "Creating incremental update procedure" "${incremental_update}"
}

################################################################################
# Optimization 2: Account Size Classification
################################################################################
deploy_account_classification_fix() {
    log_step "Deploying Account Size Classification Fix"

    # Create account metrics table
    local account_metrics="
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.account_metrics\` (
  account_id STRING NOT NULL,
  follower_count INT64,
  avg_engagement_rate FLOAT64,
  total_posts INT64,
  account_age_days INT64,
  account_size_category STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(last_updated)
CLUSTER BY account_id, account_size_category;
"

    execute_query "Creating account metrics table" "${account_metrics}"

    # Create improved classification function
    local classification_function="
CREATE OR REPLACE FUNCTION \`${PROJECT_ID}.${DATASET}.classify_account_size\`(
  follower_count INT64,
  avg_engagement_rate FLOAT64
)
RETURNS STRING
AS (
  CASE
    -- Micro influencers: 1K-10K followers
    WHEN follower_count BETWEEN 1000 AND 10000 THEN 'micro'

    -- Nano influencers: <1K followers but high engagement
    WHEN follower_count < 1000 AND avg_engagement_rate > 0.05 THEN 'nano_high_engagement'
    WHEN follower_count < 1000 THEN 'nano'

    -- Mid-tier: 10K-100K
    WHEN follower_count BETWEEN 10001 AND 100000 THEN 'mid_tier'

    -- Macro: 100K-1M
    WHEN follower_count BETWEEN 100001 AND 1000000 THEN 'macro'

    -- Mega: >1M
    WHEN follower_count > 1000000 THEN 'mega'

    ELSE 'unknown'
  END
);
"

    execute_query "Creating account classification function" "${classification_function}"

    # Create account-specific caption selection
    local account_selection="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.select_caption_for_account\`(
  IN account_id_param STRING,
  IN account_size STRING,
  OUT selected_caption_id INT64
)
BEGIN
  DECLARE exploration_rate FLOAT64;

  -- Set exploration rate based on account size
  SET exploration_rate = CASE account_size
    WHEN 'nano' THEN 0.3              -- High exploration for small accounts
    WHEN 'nano_high_engagement' THEN 0.25
    WHEN 'micro' THEN 0.2
    WHEN 'mid_tier' THEN 0.15
    WHEN 'macro' THEN 0.1
    WHEN 'mega' THEN 0.05             -- Low exploration for large accounts
    ELSE 0.2
  END;

  -- Select caption using exploration/exploitation balance
  SET selected_caption_id = (
    WITH candidate_captions AS (
      SELECT
        c.caption_id,
        s.wilson_score_lower_bound,
        s.total_views,
        RAND() as random_value
      FROM \`${PROJECT_ID}.${DATASET}.caption_bank\` c
      JOIN \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` s
        ON c.caption_id = s.caption_id
      LEFT JOIN \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` a
        ON c.caption_id = a.caption_id AND a.account_id = account_id_param
      WHERE a.caption_id IS NULL  -- Not already assigned
        AND c.is_active = TRUE
    )
    SELECT caption_id
    FROM candidate_captions
    ORDER BY
      -- Exploration: Random selection
      IF(random_value < exploration_rate, random_value, NULL) DESC,
      -- Exploitation: Best performing captions
      wilson_score_lower_bound DESC,
      total_views ASC  -- Prefer less-tested captions when scores are equal
    LIMIT 1
  );
END;
"

    execute_query "Creating account-specific caption selection" "${account_selection}"
}

################################################################################
# Optimization 3: Query Timeout Configuration
################################################################################
deploy_query_timeout_config() {
    log_step "Deploying Query Timeout Configuration"

    # Create timeout configuration table
    local timeout_config="
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.query_timeout_config\` (
  query_type STRING NOT NULL,
  timeout_seconds INT64 NOT NULL,
  max_retries INT64 DEFAULT 3,
  description STRING,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Insert default timeout configurations
INSERT INTO \`${PROJECT_ID}.${DATASET}.query_timeout_config\`
  (query_type, timeout_seconds, max_retries, description)
VALUES
  ('caption_selection', 30, 3, 'Caption selection queries'),
  ('stats_update', 60, 2, 'Statistics update operations'),
  ('wilson_score_calc', 45, 2, 'Wilson score calculations'),
  ('batch_processing', 300, 1, 'Large batch processing jobs'),
  ('reporting', 120, 1, 'Analytics and reporting queries'),
  ('backup', 600, 0, 'Backup operations')
ON CONFLICT (query_type) DO NOTHING;
"

    execute_query "Creating query timeout configuration" "${timeout_config}"

    # Create query execution wrapper with timeout
    local timeout_wrapper="
CREATE OR REPLACE PROCEDURE \`${PROJECT_ID}.${DATASET}.execute_with_timeout\`(
  IN query_type STRING,
  IN query_sql STRING,
  OUT success BOOL,
  OUT error_message STRING
)
BEGIN
  DECLARE timeout_seconds INT64;
  DECLARE max_retries INT64;
  DECLARE retry_count INT64 DEFAULT 0;

  -- Get timeout configuration
  SET (timeout_seconds, max_retries) = (
    SELECT AS STRUCT timeout_seconds, max_retries
    FROM \`${PROJECT_ID}.${DATASET}.query_timeout_config\`
    WHERE query_type = query_type
    LIMIT 1
  );

  -- Default timeout if not configured
  IF timeout_seconds IS NULL THEN
    SET timeout_seconds = 60;
    SET max_retries = 2;
  END IF;

  -- Note: Actual timeout enforcement would be done at application layer
  -- This procedure documents the timeout policy

  SET success = TRUE;
  SET error_message = NULL;
END;
"

    execute_query "Creating timeout wrapper procedure" "${timeout_wrapper}"

    # Create query performance monitoring
    local performance_monitoring="
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET}.query_performance_log\` (
  query_id STRING,
  query_type STRING,
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  duration_ms INT64,
  bytes_processed INT64,
  bytes_billed INT64,
  slot_ms INT64,
  success BOOL,
  error_message STRING
)
PARTITION BY DATE(start_time)
CLUSTER BY query_type, success;
"

    execute_query "Creating query performance log table" "${performance_monitoring}"
}

################################################################################
# Optimization 4: Additional Performance Enhancements
################################################################################
deploy_additional_optimizations() {
    log_step "Deploying Additional Performance Enhancements"

    # Create indexes for frequently queried columns (via clustering)
    local optimize_tables="
-- Optimize caption_bank table
CREATE OR REPLACE TABLE \`${PROJECT_ID}.${DATASET}.caption_bank_optimized\`
CLUSTER BY caption_id, is_active, category
AS SELECT * FROM \`${PROJECT_ID}.${DATASET}.caption_bank\`;

-- Optimize caption_bandit_stats
CREATE OR REPLACE TABLE \`${PROJECT_ID}.${DATASET}.caption_bandit_stats_optimized\`
PARTITION BY DATE(last_updated)
CLUSTER BY caption_id, wilson_score_lower_bound
AS SELECT * FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`;

-- Note: In production, you would rename these tables after verification
-- For safety, we create _optimized versions that can be validated first
"

    execute_query "Creating optimized table structures" "${optimize_tables}"

    # Create query cache helper
    local query_cache="
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET}.top_performing_captions\`
AS
SELECT
  caption_id,
  total_views,
  engagement_count,
  wilson_score_lower_bound,
  RANK() OVER (ORDER BY wilson_score_lower_bound DESC) as performance_rank
FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`
WHERE total_views >= 30  -- Sufficient data for reliable scores
ORDER BY wilson_score_lower_bound DESC
LIMIT 1000;
"

    execute_query "Creating top performing captions view" "${query_cache}"
}

################################################################################
# Post-Deployment Benchmarks
################################################################################
run_post_deployment_benchmarks() {
    log_step "Running Post-Deployment Benchmarks"

    # Run same benchmarks as pre-deployment
    benchmark_query "caption_selection" \
        "SELECT caption_id FROM \`${PROJECT_ID}.${DATASET}.caption_bank\` ORDER BY RAND() LIMIT 1" \
        "after"

    benchmark_query "wilson_score_calc" \
        "SELECT AVG(wilson_score_lower_bound) FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\`" \
        "after"

    benchmark_query "account_classification" \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.active_caption_assignments\` GROUP BY account_id LIMIT 100" \
        "after"

    benchmark_query "stats_update" \
        "SELECT caption_id, total_views, engagement_count FROM \`${PROJECT_ID}.${DATASET}.caption_bandit_stats\` ORDER BY total_views DESC LIMIT 100" \
        "after"

    log_success "Post-deployment benchmarks completed"
}

################################################################################
# Performance Analysis
################################################################################
analyze_performance_improvements() {
    log_step "Analyzing Performance Improvements"

    echo ""
    echo "=========================================================="
    echo "  Performance Benchmark Results"
    echo "=========================================================="
    echo ""

    local total_improvement=0
    local benchmark_count=0

    for benchmark in "${!BENCHMARK_BEFORE[@]}"; do
        local before=${BENCHMARK_BEFORE[$benchmark]}
        local after=${BENCHMARK_AFTER[$benchmark]:-0}

        if [[ ${after} -gt 0 ]]; then
            local improvement=$(( (before - after) * 100 / before ))
            total_improvement=$((total_improvement + improvement))
            ((benchmark_count++))

            printf "%-30s %10s ms → %10s ms " "${benchmark}:" "${before}" "${after}"

            if [[ ${improvement} -gt 0 ]]; then
                log_success "(${improvement}% faster)"
            elif [[ ${improvement} -lt 0 ]]; then
                local slowdown=$(( -improvement ))
                log_warning "(${slowdown}% slower)"
            else
                log_info "(no change)"
            fi
        fi
    done

    echo ""

    if [[ ${benchmark_count} -gt 0 ]]; then
        local avg_improvement=$((total_improvement / benchmark_count))
        log_benchmark "Average performance improvement: ${avg_improvement}%"
    fi

    # Save benchmark results to JSON
    cat > "${BENCHMARK_FILE}" << EOF
{
  "deployment_timestamp": "${DEPLOYMENT_TIMESTAMP}",
  "project_id": "${PROJECT_ID}",
  "dataset": "${DATASET}",
  "benchmarks": {
EOF

    local first=true
    for benchmark in "${!BENCHMARK_BEFORE[@]}"; do
        if [[ "${first}" == "false" ]]; then
            echo "," >> "${BENCHMARK_FILE}"
        fi
        first=false

        local before=${BENCHMARK_BEFORE[$benchmark]}
        local after=${BENCHMARK_AFTER[$benchmark]:-0}
        local improvement=$(( (before - after) * 100 / before ))

        cat >> "${BENCHMARK_FILE}" << EOF
    "${benchmark}": {
      "before_ms": ${before},
      "after_ms": ${after},
      "improvement_percent": ${improvement}
    }
EOF
    done

    cat >> "${BENCHMARK_FILE}" << EOF

  }
}
EOF

    log_success "Benchmark results saved to: ${BENCHMARK_FILE}"
}

################################################################################
# Main Deployment Flow
################################################################################
main() {
    echo ""
    echo "=========================================================="
    echo "  EROS Scheduling System - Phase 2 Deployment"
    echo "  Performance Optimizations"
    echo "=========================================================="
    echo ""

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Deployment Time: ${DEPLOYMENT_TIMESTAMP}"
    log_info "  Log Directory: ${LOG_DIR}"
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Pre-deployment benchmarks
    run_pre_deployment_benchmarks
    echo ""

    # Deploy optimizations
    local deployment_failed=false

    if ! deploy_feedback_loop_optimization; then
        deployment_failed=true
    fi
    echo ""

    if ! deploy_account_classification_fix; then
        deployment_failed=true
    fi
    echo ""

    if ! deploy_query_timeout_config; then
        deployment_failed=true
    fi
    echo ""

    if ! deploy_additional_optimizations; then
        deployment_failed=true
    fi
    echo ""

    # Post-deployment benchmarks
    run_post_deployment_benchmarks
    echo ""

    # Analyze results
    analyze_performance_improvements
    echo ""

    # Summary
    echo "=========================================================="
    echo "  Phase 2 Deployment Summary"
    echo "=========================================================="
    echo ""

    if [[ "${deployment_failed}" == "false" ]]; then
        log_success "Phase 2 deployment completed successfully!"
        echo ""
        log_info "Optimizations deployed:"
        log_info "  ✓ Performance feedback loop with batching"
        log_info "  ✓ Improved account size classification"
        log_info "  ✓ Query timeout configuration"
        log_info "  ✓ Materialized views and caching"
        log_info "  ✓ Optimized table structures"
        echo ""
        log_info "Next steps:"
        log_info "  1. Monitor performance improvements over 24 hours"
        log_info "  2. Review benchmark results: ${BENCHMARK_FILE}"
        log_info "  3. Run health checks: bq query < monitor_deployment.sql"
        log_info "  4. Schedule regular cleanup: caption_locks cleanup"
        echo ""
        exit 0
    else
        log_error "Phase 2 deployment completed with errors"
        echo ""
        log_warning "Review logs in: ${LOG_DIR}"
        log_warning "Consider running rollback: ./rollback.sh"
        echo ""
        exit 1
    fi
}

# Handle interruption
trap 'log_error "Deployment interrupted"; exit 130' INT TERM

# Run main
main "$@"
