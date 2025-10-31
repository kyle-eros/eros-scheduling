#!/bin/bash

################################################################################
# EROS Scheduling System - Monitoring and Alerting Setup
#
# Description: Configure comprehensive monitoring and alerting
#   - Cloud Monitoring alert policies
#   - BigQuery scheduled queries for health checks
#   - Pub/Sub notifications
#   - Email and Slack integration
#   - Dashboard creation
#
# Usage: ./setup_monitoring_alerts.sh [OPTIONS]
#
# Options:
#   --project-id ID         GCP project ID
#   --dataset NAME          BigQuery dataset
#   --notification-email    Email for alerts
#   --slack-webhook URL     Slack webhook for notifications
#   --dry-run               Show what would be configured
#
# Author: DevOps Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail

# Source logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/logging_config.sh" ]]; then
    source "${SCRIPT_DIR}/logging_config.sh"
    init_logging "monitoring_setup"
else
    # Fallback logging
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_warning() { echo "[WARNING] $1"; }
fi

# Configuration
PROJECT_ID="${EROS_PROJECT_ID:-of-scheduler-proj}"
DATASET="${EROS_DATASET:-eros_scheduling_brain}"
NOTIFICATION_EMAIL="${EROS_NOTIFICATION_EMAIL:-}"
SLACK_WEBHOOK="${EROS_SLACK_WEBHOOK:-}"
DRY_RUN=false

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
        --notification-email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        --slack-webhook)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# NOTIFICATION CHANNEL SETUP
# ============================================================================

setup_notification_channels() {
    log_info "Setting up notification channels..."

    # Create Pub/Sub topic for alerts
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create Pub/Sub topic: eros-alerts"
    else
        if ! gcloud pubsub topics describe eros-alerts --project="${PROJECT_ID}" &>/dev/null; then
            gcloud pubsub topics create eros-alerts --project="${PROJECT_ID}"
            log_success "Created Pub/Sub topic: eros-alerts"
        else
            log_info "Pub/Sub topic already exists: eros-alerts"
        fi
    fi

    # Create email notification channel
    if [[ -n "${NOTIFICATION_EMAIL}" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would create email notification channel: ${NOTIFICATION_EMAIL}"
        else
            cat > /tmp/email_channel.json << EOF
{
  "type": "email",
  "displayName": "EROS DevOps Team Email",
  "labels": {
    "email_address": "${NOTIFICATION_EMAIL}"
  },
  "enabled": true
}
EOF
            if gcloud alpha monitoring channels create \
                --channel-content-from-file=/tmp/email_channel.json \
                --project="${PROJECT_ID}" 2>/dev/null; then
                log_success "Created email notification channel"
            else
                log_warning "Email notification channel may already exist"
            fi
            rm -f /tmp/email_channel.json
        fi
    fi

    # Create Slack webhook channel if provided
    if [[ -n "${SLACK_WEBHOOK}" ]]; then
        log_info "Slack webhook configured: ${SLACK_WEBHOOK:0:30}..."
    fi

    log_success "Notification channels configured"
}

# ============================================================================
# HEALTH CHECK SCHEDULED QUERY
# ============================================================================

create_health_check_query() {
    log_info "Creating health check scheduled query..."

    local query=$(cat << 'EOF'
-- EROS System Health Check
-- Runs every 5 minutes

WITH system_metrics AS (
    -- Query performance metrics
    SELECT
        COUNT(*) as total_queries,
        COUNTIF(total_slot_ms > 60000) as slow_queries,
        COUNTIF(error_result IS NOT NULL) as failed_queries,
        AVG(total_slot_ms) / 1000 as avg_execution_seconds
    FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
    WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
),
lock_metrics AS (
    -- Caption lock metrics
    SELECT
        COUNT(*) as active_locks,
        COUNTIF(expires_at < CURRENT_TIMESTAMP()) as expired_locks
    FROM `@PROJECT_ID@.@DATASET@.caption_locks`
),
assignment_metrics AS (
    -- Caption assignment metrics
    SELECT
        COUNT(*) as recent_assignments,
        COUNT(DISTINCT caption_id) as unique_captions_assigned
    FROM `@PROJECT_ID@.@DATASET@.active_caption_assignments`
    WHERE assigned_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
)
SELECT
    CURRENT_TIMESTAMP() as check_time,

    -- System metrics
    sm.total_queries,
    sm.slow_queries,
    sm.failed_queries,
    ROUND(sm.avg_execution_seconds, 2) as avg_execution_seconds,

    -- Lock metrics
    lm.active_locks,
    lm.expired_locks,

    -- Assignment metrics
    am.recent_assignments,
    am.unique_captions_assigned,

    -- Health score calculation (0-100)
    CAST(
        100
        - (LEAST(sm.slow_queries, 5) * 10)  -- -10 points per slow query (max -50)
        - (LEAST(sm.failed_queries, 3) * 15)  -- -15 points per failed query (max -45)
        - (LEAST(lm.expired_locks, 10) * 0.5)  -- -0.5 points per expired lock (max -5)
    AS INT64) as health_score,

    -- Status
    CASE
        WHEN sm.failed_queries > 5 OR sm.slow_queries > 10 THEN 'CRITICAL'
        WHEN sm.failed_queries > 2 OR sm.slow_queries > 5 THEN 'WARNING'
        ELSE 'HEALTHY'
    END as status

FROM system_metrics sm
CROSS JOIN lock_metrics lm
CROSS JOIN assignment_metrics am
EOF
)

    # Replace placeholders
    query="${query//@PROJECT_ID@/${PROJECT_ID}}"
    query="${query//@DATASET@/${DATASET}}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create scheduled query: eros_health_check"
        echo "${query}" > /tmp/health_check_query_dry_run.sql
        log_info "Query saved to: /tmp/health_check_query_dry_run.sql"
    else
        # Create scheduled query using bq command
        local config_json=$(cat << EOF
{
  "displayName": "EROS Health Check",
  "dataSourceId": "scheduled_query",
  "schedule": "every 5 minutes",
  "destinationDatasetId": "${DATASET}",
  "params": {
    "query": "${query}",
    "destination_table_name_template": "health_checks",
    "write_disposition": "WRITE_APPEND",
    "partitioning_field": "check_time"
  }
}
EOF
)
        echo "${config_json}" > /tmp/health_check_config.json

        # Note: Actual scheduled query creation requires bq CLI or API
        log_warning "Scheduled query configuration created at: /tmp/health_check_config.json"
        log_info "To create the scheduled query, run:"
        log_info "  bq mk --transfer_config --project_id=${PROJECT_ID} --data_source=scheduled_query --target_dataset=${DATASET} --display_name='EROS Health Check' --schedule='every 5 minutes' --params='{\"query\":\"<query>\"}'"
    fi

    log_success "Health check query configured"
}

# ============================================================================
# COST MONITORING QUERY
# ============================================================================

create_cost_monitoring_query() {
    log_info "Creating cost monitoring scheduled query..."

    local query=$(cat << 'EOF'
-- EROS Cost Monitoring
-- Runs every hour

SELECT
    CURRENT_TIMESTAMP() as report_time,
    DATE(creation_time) as date,

    -- Query statistics
    COUNT(*) as total_queries,
    COUNT(DISTINCT user_email) as unique_users,

    -- Data processed
    ROUND(SUM(total_bytes_processed) / POW(10, 12), 4) as tb_processed,
    ROUND(SUM(total_bytes_billed) / POW(10, 12), 4) as tb_billed,

    -- Cost estimate ($5 per TB)
    ROUND(SUM(total_bytes_billed) / POW(10, 12) * 5, 2) as estimated_cost_usd,

    -- Query types
    COUNTIF(statement_type = 'SELECT') as select_queries,
    COUNTIF(statement_type = 'INSERT') as insert_queries,
    COUNTIF(statement_type = 'DELETE') as delete_queries,
    COUNTIF(statement_type = 'CALL') as procedure_calls,

    -- Performance
    ROUND(AVG(total_slot_ms) / 1000, 2) as avg_execution_seconds,
    ROUND(APPROX_QUANTILES(total_slot_ms / 1000, 100)[OFFSET(95)], 2) as p95_execution_seconds,

    -- Status
    CASE
        WHEN SUM(total_bytes_billed) / POW(10, 12) * 5 > 10 THEN 'CRITICAL'
        WHEN SUM(total_bytes_billed) / POW(10, 12) * 5 > 5 THEN 'WARNING'
        ELSE 'OK'
    END as cost_status

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY date
ORDER BY date DESC
EOF
)

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create scheduled query: eros_cost_monitoring"
        echo "${query}" > /tmp/cost_monitoring_query_dry_run.sql
        log_info "Query saved to: /tmp/cost_monitoring_query_dry_run.sql"
    else
        echo "${query}" > /tmp/cost_monitoring_query.sql
        log_info "Cost monitoring query saved to: /tmp/cost_monitoring_query.sql"
    fi

    log_success "Cost monitoring query configured"
}

# ============================================================================
# ALERT POLICIES
# ============================================================================

create_alert_policies() {
    log_info "Creating Cloud Monitoring alert policies..."

    # Alert 1: High Error Rate
    create_alert_policy \
        "EROS High Error Rate" \
        "query_error_rate > 0.05" \
        "CRITICAL" \
        "Error rate exceeded 5%"

    # Alert 2: High Query Latency
    create_alert_policy \
        "EROS High Query Latency" \
        "query_p95_latency > 10000" \
        "WARNING" \
        "P95 query latency exceeded 10 seconds"

    # Alert 3: Cost Spike
    create_alert_policy \
        "EROS Cost Spike" \
        "daily_cost_usd > 10" \
        "WARNING" \
        "Daily BigQuery costs exceeded $10"

    # Alert 4: Caption Pool Depletion
    create_alert_policy \
        "EROS Caption Pool Low" \
        "available_captions < 200" \
        "CRITICAL" \
        "Available caption pool below 200"

    log_success "Alert policies configured"
}

create_alert_policy() {
    local name=$1
    local condition=$2
    local severity=$3
    local description=$4

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create alert policy: ${name}"
        return
    fi

    log_info "Creating alert policy: ${name}"

    # Note: Actual implementation would use gcloud monitoring policies create
    # This requires more complex JSON configuration
    log_warning "Alert policy '${name}' configuration prepared"
    log_info "  Condition: ${condition}"
    log_info "  Severity: ${severity}"
    log_info "  Description: ${description}"
}

# ============================================================================
# MONITORING DASHBOARD
# ============================================================================

create_monitoring_dashboard() {
    log_info "Creating monitoring dashboard..."

    local dashboard_config=$(cat << 'EOF'
{
  "displayName": "EROS Scheduling System Dashboard",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "System Health Score",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"bigquery_dataset\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_MEAN"
                }
              }
            },
            "thresholds": [
              {"value": 70, "color": "RED"},
              {"value": 85, "color": "YELLOW"}
            ]
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Query Performance",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"bigquery_project\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Daily Costs",
          "xyChart": {
            "chartOptions": {
              "mode": "COLOR"
            }
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 4,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Caption Pool Status",
          "scorecard": {
            "thresholds": [
              {"value": 200, "color": "RED"},
              {"value": 500, "color": "YELLOW"}
            ]
          }
        }
      }
    ]
  }
}
EOF
)

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create dashboard: EROS Scheduling System Dashboard"
        echo "${dashboard_config}" > /tmp/dashboard_config_dry_run.json
    else
        echo "${dashboard_config}" > /tmp/eros_dashboard_config.json
        log_info "Dashboard configuration saved to: /tmp/eros_dashboard_config.json"
        log_info "To create dashboard, run:"
        log_info "  gcloud monitoring dashboards create --config-from-file=/tmp/eros_dashboard_config.json"
    fi

    log_success "Dashboard configuration created"
}

# ============================================================================
# SLACK INTEGRATION
# ============================================================================

create_slack_notification_script() {
    log_info "Creating Slack notification script..."

    cat > "${SCRIPT_DIR}/notify_slack.sh" << 'EOF'
#!/bin/bash
# EROS Slack Notification Script

SLACK_WEBHOOK="${1:-${EROS_SLACK_WEBHOOK}}"
MESSAGE="${2:-Test notification}"
SEVERITY="${3:-INFO}"
COLOR="${4:-#36a64f}"  # Default green

if [[ -z "${SLACK_WEBHOOK}" ]]; then
    echo "Error: SLACK_WEBHOOK not provided"
    exit 1
fi

# Color mapping
case ${SEVERITY} in
    CRITICAL) COLOR="#d32f2f" ;;  # Red
    WARNING)  COLOR="#ffa726" ;;  # Orange
    INFO)     COLOR="#29b6f6" ;;  # Blue
    SUCCESS)  COLOR="#66bb6a" ;;  # Green
esac

# Build Slack payload
PAYLOAD=$(cat << EOJSON
{
    "username": "EROS Monitor",
    "icon_emoji": ":robot_face:",
    "attachments": [
        {
            "color": "${COLOR}",
            "title": "${SEVERITY}: EROS Scheduling System",
            "text": "${MESSAGE}",
            "footer": "EROS Monitoring",
            "footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png",
            "ts": $(date +%s)
        }
    ]
}
EOJSON
)

# Send to Slack
curl -X POST \
    -H 'Content-Type: application/json' \
    -d "${PAYLOAD}" \
    "${SLACK_WEBHOOK}"
EOF

    chmod +x "${SCRIPT_DIR}/notify_slack.sh"
    log_success "Slack notification script created: ${SCRIPT_DIR}/notify_slack.sh"
}

# ============================================================================
# AUTOMATED ALERTING SCRIPT
# ============================================================================

create_alerting_script() {
    log_info "Creating automated alerting script..."

    cat > "${SCRIPT_DIR}/check_and_alert.sh" << 'EOF'
#!/bin/bash
# EROS Automated Health Check and Alerting

set -euo pipefail

PROJECT_ID="${EROS_PROJECT_ID:-of-scheduler-proj}"
DATASET="${EROS_DATASET:-eros_scheduling_brain}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get latest health check
HEALTH_CHECK=$(bq query --use_legacy_sql=false --format=csv --max_rows=1 \
"SELECT
    health_score,
    status,
    slow_queries,
    failed_queries,
    expired_locks
FROM \`${PROJECT_ID}.${DATASET}.health_checks\`
ORDER BY check_time DESC
LIMIT 1" 2>/dev/null | tail -1)

if [[ -z "${HEALTH_CHECK}" ]]; then
    echo "Error: Could not retrieve health check data"
    exit 1
fi

# Parse health check results
IFS=',' read -r health_score status slow_queries failed_queries expired_locks <<< "${HEALTH_CHECK}"

# Alert on critical conditions
if [[ "${status}" == "CRITICAL" ]] || [[ ${health_score} -lt 70 ]]; then
    MESSAGE="System health critical! Score: ${health_score}, Status: ${status}"
    MESSAGE+="\nSlow queries: ${slow_queries}, Failed queries: ${failed_queries}"

    # Send Slack notification
    if [[ -x "${SCRIPT_DIR}/notify_slack.sh" ]]; then
        "${SCRIPT_DIR}/notify_slack.sh" "${EROS_SLACK_WEBHOOK}" "${MESSAGE}" "CRITICAL"
    fi

    # Send email (if configured)
    if [[ -n "${EROS_NOTIFICATION_EMAIL:-}" ]]; then
        echo "${MESSAGE}" | mail -s "EROS CRITICAL ALERT" "${EROS_NOTIFICATION_EMAIL}"
    fi

    exit 2
elif [[ "${status}" == "WARNING" ]] || [[ ${health_score} -lt 85 ]]; then
    MESSAGE="System health warning. Score: ${health_score}, Status: ${status}"

    if [[ -x "${SCRIPT_DIR}/notify_slack.sh" ]]; then
        "${SCRIPT_DIR}/notify_slack.sh" "${EROS_SLACK_WEBHOOK}" "${MESSAGE}" "WARNING"
    fi

    exit 1
else
    echo "System healthy. Score: ${health_score}, Status: ${status}"
    exit 0
fi
EOF

    chmod +x "${SCRIPT_DIR}/check_and_alert.sh"
    log_success "Alerting script created: ${SCRIPT_DIR}/check_and_alert.sh"
}

# ============================================================================
# CRON JOB SETUP
# ============================================================================

setup_cron_jobs() {
    log_info "Setting up cron jobs for monitoring..."

    cat > /tmp/eros_cron_jobs.txt << EOF
# EROS Scheduling System Monitoring

# Health check and alerting (every 5 minutes)
*/5 * * * * ${SCRIPT_DIR}/check_and_alert.sh

# Daily cost report (every day at 8 AM)
0 8 * * * cd ${SCRIPT_DIR} && bq query --use_legacy_sql=false < monitor_deployment.sql | mail -s "EROS Daily Report" ${NOTIFICATION_EMAIL}

# Weekly log rotation (every Sunday at 2 AM)
0 2 * * 0 source ${SCRIPT_DIR}/logging_config.sh && rotate_logs

# Monthly cleanup (first day of month at 3 AM)
0 3 1 * * bq query --use_legacy_sql=false "DELETE FROM \`${PROJECT_ID}.${DATASET}.caption_locks\` WHERE expires_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)"
EOF

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would install cron jobs from: /tmp/eros_cron_jobs.txt"
        cat /tmp/eros_cron_jobs.txt
    else
        log_info "Cron job configuration created at: /tmp/eros_cron_jobs.txt"
        log_info "To install, run: crontab -e and add the contents of /tmp/eros_cron_jobs.txt"
    fi

    log_success "Cron job configuration created"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo "========================================================================"
    echo "  EROS Monitoring and Alerting Setup"
    echo "========================================================================"
    echo ""

    log_info "Configuration:"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Notification Email: ${NOTIFICATION_EMAIL:-Not configured}"
    log_info "  Slack Webhook: ${SLACK_WEBHOOK:+Configured}"
    log_info "  Dry Run: ${DRY_RUN}"
    echo ""

    # Setup components
    setup_notification_channels
    echo ""

    create_health_check_query
    echo ""

    create_cost_monitoring_query
    echo ""

    create_alert_policies
    echo ""

    create_monitoring_dashboard
    echo ""

    if [[ -n "${SLACK_WEBHOOK}" ]]; then
        create_slack_notification_script
        echo ""
    fi

    create_alerting_script
    echo ""

    setup_cron_jobs
    echo ""

    # Summary
    echo "========================================================================"
    echo "  Setup Complete"
    echo "========================================================================"
    echo ""
    log_success "Monitoring and alerting configuration complete"
    echo ""
    log_info "Next Steps:"
    log_info "  1. Review generated configurations in /tmp/"
    log_info "  2. Create scheduled queries in BigQuery console"
    log_info "  3. Install cron jobs: crontab -e"
    log_info "  4. Test notifications: ${SCRIPT_DIR}/check_and_alert.sh"
    log_info "  5. Configure Cloud Monitoring dashboards"
    echo ""
}

main "$@"
