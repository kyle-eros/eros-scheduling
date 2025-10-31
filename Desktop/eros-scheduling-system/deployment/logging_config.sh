#!/bin/bash

################################################################################
# EROS Scheduling System - Logging Configuration
#
# Description: Centralized logging configuration and management
#   - Structured logging with JSON format
#   - Log rotation and retention policies
#   - Log aggregation and shipping
#   - Query audit logging in BigQuery
#
# Usage: source ./logging_config.sh
#
# Author: DevOps Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

# Log levels
declare -gA LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARNING]=2
    [ERROR]=3
    [CRITICAL]=4
)

# Current log level (can be overridden)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Log directory structure
LOG_BASE_DIR="${EROS_LOG_DIR:-/var/log/eros}"
DEPLOYMENT_LOG_DIR="${LOG_BASE_DIR}/deployment"
APPLICATION_LOG_DIR="${LOG_BASE_DIR}/application"
AUDIT_LOG_DIR="${LOG_BASE_DIR}/audit"
PERFORMANCE_LOG_DIR="${LOG_BASE_DIR}/performance"

# Log retention (days)
LOG_RETENTION_DAYS=30
AUDIT_LOG_RETENTION_DAYS=90

# Color codes for terminal output
readonly LOG_COLOR_DEBUG='\033[0;35m'     # Magenta
readonly LOG_COLOR_INFO='\033[0;34m'      # Blue
readonly LOG_COLOR_WARNING='\033[1;33m'   # Yellow
readonly LOG_COLOR_ERROR='\033[0;31m'     # Red
readonly LOG_COLOR_CRITICAL='\033[1;31m'  # Bold Red
readonly LOG_COLOR_RESET='\033[0m'

################################################################################
# Logging Functions
################################################################################

# Initialize logging system
init_logging() {
    local component=${1:-"eros"}

    # Create log directories
    mkdir -p "${DEPLOYMENT_LOG_DIR}"
    mkdir -p "${APPLICATION_LOG_DIR}"
    mkdir -p "${AUDIT_LOG_DIR}"
    mkdir -p "${PERFORMANCE_LOG_DIR}"

    # Set current log file
    export CURRENT_LOG_FILE="${APPLICATION_LOG_DIR}/${component}_$(date +%Y%m%d).log"

    # Log initialization
    log_structured "INFO" "Logging initialized" \
        "component=${component}" \
        "log_file=${CURRENT_LOG_FILE}" \
        "log_level=${CURRENT_LOG_LEVEL}"
}

# Check if log level should be printed
should_log() {
    local level=$1
    local level_value=${LOG_LEVELS[$level]:-1}
    local current_value=${LOG_LEVELS[$CURRENT_LOG_LEVEL]:-1}

    [[ ${level_value} -ge ${current_value} ]]
}

# Structured logging function
log_structured() {
    local level=$1
    shift
    local message=$1
    shift

    # Check log level
    if ! should_log "${level}"; then
        return 0
    fi

    # Build JSON log entry
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local hostname=$(hostname)
    local pid=$$

    # Parse additional key-value pairs
    local additional_fields=""
    for arg in "$@"; do
        if [[ $arg == *=* ]]; then
            local key="${arg%%=*}"
            local value="${arg#*=}"
            additional_fields="${additional_fields}, \"${key}\": \"${value}\""
        fi
    done

    # Create JSON log entry
    local json_log=$(cat <<EOF
{
  "timestamp": "${timestamp}",
  "level": "${level}",
  "message": "${message}",
  "hostname": "${hostname}",
  "pid": ${pid},
  "component": "${COMPONENT:-eros}"${additional_fields}
}
EOF
)

    # Write to log file
    if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
        echo "${json_log}" >> "${CURRENT_LOG_FILE}"
    fi

    # Also output to console with colors
    local color=""
    case ${level} in
        DEBUG)   color="${LOG_COLOR_DEBUG}" ;;
        INFO)    color="${LOG_COLOR_INFO}" ;;
        WARNING) color="${LOG_COLOR_WARNING}" ;;
        ERROR)   color="${LOG_COLOR_ERROR}" ;;
        CRITICAL) color="${LOG_COLOR_CRITICAL}" ;;
    esac

    echo -e "${color}[${level}]${LOG_COLOR_RESET} ${timestamp} - ${message}" >&2
}

# Convenience logging functions
log_debug() {
    log_structured "DEBUG" "$@"
}

log_info() {
    log_structured "INFO" "$@"
}

log_warning() {
    log_structured "WARNING" "$@"
}

log_error() {
    log_structured "ERROR" "$@"
}

log_critical() {
    log_structured "CRITICAL" "$@"
}

################################################################################
# Audit Logging
################################################################################

# Log audit event
audit_log() {
    local event_type=$1
    local user=${2:-$(whoami)}
    shift 2
    local description="$*"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local audit_file="${AUDIT_LOG_DIR}/audit_$(date +%Y%m%d).log"

    local audit_entry=$(cat <<EOF
{
  "timestamp": "${timestamp}",
  "event_type": "${event_type}",
  "user": "${user}",
  "description": "${description}",
  "hostname": "$(hostname)",
  "source_ip": "${SSH_CLIENT%% *}"
}
EOF
)

    echo "${audit_entry}" >> "${audit_file}"

    # Also log to BigQuery if configured
    if [[ -n "${EROS_PROJECT_ID:-}" ]] && [[ -n "${EROS_DATASET:-}" ]]; then
        log_audit_to_bigquery "${event_type}" "${user}" "${description}"
    fi
}

# Log audit event to BigQuery
log_audit_to_bigquery() {
    local event_type=$1
    local user=$2
    local description=$3

    # Create audit table if it doesn't exist
    bq query --use_legacy_sql=false --project_id="${EROS_PROJECT_ID}" <<EOF >/dev/null 2>&1
    CREATE TABLE IF NOT EXISTS \`${EROS_PROJECT_ID}.${EROS_DATASET}.audit_log\` (
        timestamp TIMESTAMP,
        event_type STRING,
        user STRING,
        description STRING,
        hostname STRING,
        source_ip STRING
    )
    PARTITION BY DATE(timestamp)
    CLUSTER BY event_type, user;
EOF

    # Insert audit record
    bq query --use_legacy_sql=false --project_id="${EROS_PROJECT_ID}" <<EOF >/dev/null 2>&1
    INSERT INTO \`${EROS_PROJECT_ID}.${EROS_DATASET}.audit_log\`
    (timestamp, event_type, user, description, hostname, source_ip)
    VALUES (
        CURRENT_TIMESTAMP(),
        '${event_type}',
        '${user}',
        '${description}',
        '$(hostname)',
        '${SSH_CLIENT%% *}'
    );
EOF
}

################################################################################
# Performance Logging
################################################################################

# Start performance timer
perf_timer_start() {
    local timer_name=$1
    export "PERF_TIMER_${timer_name}=$(date +%s%N)"
}

# End performance timer and log
perf_timer_end() {
    local timer_name=$1
    local description=${2:-"Operation"}

    local start_var="PERF_TIMER_${timer_name}"
    local start_time=${!start_var}

    if [[ -z "${start_time}" ]]; then
        log_warning "Performance timer '${timer_name}' was not started"
        return 1
    fi

    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    local duration_s=$((duration_ms / 1000))

    # Log to performance log
    local perf_file="${PERFORMANCE_LOG_DIR}/performance_$(date +%Y%m%d).log"
    local perf_entry=$(cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "timer_name": "${timer_name}",
  "description": "${description}",
  "duration_ms": ${duration_ms},
  "duration_s": ${duration_s}
}
EOF
)

    echo "${perf_entry}" >> "${perf_file}"

    log_info "${description} completed" "duration=${duration_ms}ms" "timer=${timer_name}"

    # Clean up timer variable
    unset "${start_var}"
}

################################################################################
# Query Logging
################################################################################

# Log BigQuery query execution
log_query() {
    local query_type=$1
    local query=$2
    local duration_ms=${3:-0}
    local bytes_processed=${4:-0}
    local status=${5:-"success"}

    local query_log_file="${AUDIT_LOG_DIR}/queries_$(date +%Y%m%d).log"

    local query_entry=$(cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
  "query_type": "${query_type}",
  "query": "${query}",
  "duration_ms": ${duration_ms},
  "bytes_processed": ${bytes_processed},
  "status": "${status}",
  "user": "$(whoami)"
}
EOF
)

    echo "${query_entry}" >> "${query_log_file}"
}

################################################################################
# Log Rotation
################################################################################

# Rotate logs older than retention period
rotate_logs() {
    log_info "Starting log rotation" "retention_days=${LOG_RETENTION_DAYS}"

    local rotated_count=0

    # Rotate application logs
    while IFS= read -r -d '' log_file; do
        local file_date=$(date -r "${log_file}" +%s)
        local cutoff_date=$(date -d "${LOG_RETENTION_DAYS} days ago" +%s)

        if [[ ${file_date} -lt ${cutoff_date} ]]; then
            gzip "${log_file}"
            ((rotated_count++))
            log_debug "Rotated log file" "file=${log_file}"
        fi
    done < <(find "${APPLICATION_LOG_DIR}" -name "*.log" -type f -print0)

    # Delete old compressed logs (beyond 2x retention)
    find "${APPLICATION_LOG_DIR}" -name "*.log.gz" -mtime +$((LOG_RETENTION_DAYS * 2)) -delete

    log_info "Log rotation completed" "rotated=${rotated_count}"
}

# Rotate audit logs
rotate_audit_logs() {
    log_info "Starting audit log rotation" "retention_days=${AUDIT_LOG_RETENTION_DAYS}"

    find "${AUDIT_LOG_DIR}" -name "*.log" -mtime +${AUDIT_LOG_RETENTION_DAYS} -exec gzip {} \;
    find "${AUDIT_LOG_DIR}" -name "*.log.gz" -mtime +$((AUDIT_LOG_RETENTION_DAYS * 2)) -delete

    log_info "Audit log rotation completed"
}

################################################################################
# Log Shipping (optional)
################################################################################

# Ship logs to Cloud Logging
ship_logs_to_cloud() {
    if [[ -z "${EROS_PROJECT_ID:-}" ]]; then
        log_debug "Cloud logging not configured - skipping log shipping"
        return 0
    fi

    log_info "Shipping logs to Cloud Logging" "project=${EROS_PROJECT_ID}"

    # Ship application logs
    while IFS= read -r -d '' log_file; do
        if [[ -f "${log_file}" ]]; then
            # Read each JSON log entry and send to Cloud Logging
            while IFS= read -r log_entry; do
                if [[ -n "${log_entry}" ]]; then
                    echo "${log_entry}" | gcloud logging write eros-application-log \
                        --project="${EROS_PROJECT_ID}" \
                        --severity=INFO \
                        --payload-type=json - 2>/dev/null || true
                fi
            done < "${log_file}"
        fi
    done < <(find "${APPLICATION_LOG_DIR}" -name "*$(date +%Y%m%d).log" -type f -print0)

    log_info "Log shipping completed"
}

################################################################################
# Log Analysis
################################################################################

# Analyze logs for errors
analyze_logs() {
    local time_range=${1:-"1h"}

    log_info "Analyzing logs" "time_range=${time_range}"

    local error_count=$(grep -c '"level": "ERROR"' "${APPLICATION_LOG_DIR}"/*$(date +%Y%m%d).log 2>/dev/null || echo 0)
    local critical_count=$(grep -c '"level": "CRITICAL"' "${APPLICATION_LOG_DIR}"/*$(date +%Y%m%d).log 2>/dev/null || echo 0)

    log_info "Log analysis results" \
        "errors=${error_count}" \
        "critical=${critical_count}"

    # Print summary
    echo "Log Analysis Summary:"
    echo "  Time Range: ${time_range}"
    echo "  Errors: ${error_count}"
    echo "  Critical: ${critical_count}"

    if [[ ${critical_count} -gt 0 ]]; then
        echo ""
        echo "Recent Critical Errors:"
        grep '"level": "CRITICAL"' "${APPLICATION_LOG_DIR}"/*$(date +%Y%m%d).log 2>/dev/null | tail -5
    fi
}

# Export functions for use in other scripts
export -f init_logging
export -f log_structured
export -f log_debug
export -f log_info
export -f log_warning
export -f log_error
export -f log_critical
export -f audit_log
export -f perf_timer_start
export -f perf_timer_end
export -f log_query
export -f rotate_logs
export -f analyze_logs

################################################################################
# Usage Example
################################################################################

# Example usage:
# source ./logging_config.sh
# init_logging "deployment"
# log_info "Starting deployment" "version=1.0"
# perf_timer_start "deploy"
# # ... do work ...
# perf_timer_end "deploy" "Deployment completed"
# audit_log "DEPLOYMENT" "$(whoami)" "Deployed version 1.0"
