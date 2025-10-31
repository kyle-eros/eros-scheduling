#!/bin/bash

################################################################################
# EROS Scheduling System - Table Backup Script
#
# Description: Backs up critical BigQuery tables with timestamp
# Tables: caption_bank, caption_bandit_stats, active_caption_assignments
#
# Usage: ./backup_tables.sh [PROJECT_ID] [DATASET]
#
# Requirements:
#   - bq CLI installed and authenticated
#   - Write permissions to gs://eros-platform-backups/
#   - BigQuery read permissions
#
# Author: Deployment Engineer
# Version: 1.0
# Date: 2025-10-31
################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
BACKUP_BUCKET="gs://eros-platform-backups"
BACKUP_PATH="${BACKUP_BUCKET}/${TIMESTAMP}"

# Tables to backup
TABLES=(
    "caption_bank"
    "caption_bandit_stats"
    "active_caption_assignments"
)

# Parse command line arguments
PROJECT_ID="${1:-}"
DATASET="${2:-}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [PROJECT_ID] [DATASET]

Arguments:
    PROJECT_ID    Google Cloud project ID (optional if gcloud config set)
    DATASET       BigQuery dataset name (default: eros_platform)

Examples:
    $0 my-project-id eros_platform
    $0  # Uses default gcloud project and eros_platform dataset

Environment Variables:
    EROS_PROJECT_ID    Default project ID if not provided
    EROS_DATASET       Default dataset if not provided
EOF
    exit 1
}

# Get project ID from various sources
get_project_id() {
    if [[ -n "${PROJECT_ID}" ]]; then
        echo "${PROJECT_ID}"
    elif [[ -n "${EROS_PROJECT_ID:-}" ]]; then
        echo "${EROS_PROJECT_ID}"
    else
        # Try to get from gcloud config
        local gcloud_project=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "${gcloud_project}" ]]; then
            echo "${gcloud_project}"
        else
            log_error "Project ID not provided and cannot be determined from gcloud config"
            usage
        fi
    fi
}

# Get dataset name
get_dataset() {
    if [[ -n "${DATASET}" ]]; then
        echo "${DATASET}"
    elif [[ -n "${EROS_DATASET:-}" ]]; then
        echo "${EROS_DATASET}"
    else
        echo "eros_platform"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI not found. Please install Google Cloud SDK."
        log_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil not found. Please install Google Cloud SDK."
        exit 1
    fi

    # Verify authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Verify backup bucket exists
verify_backup_bucket() {
    log_info "Verifying backup bucket: ${BACKUP_BUCKET}"

    if ! gsutil ls "${BACKUP_BUCKET}" &> /dev/null; then
        log_warning "Backup bucket does not exist. Creating: ${BACKUP_BUCKET}"
        if ! gsutil mb "${BACKUP_BUCKET}"; then
            log_error "Failed to create backup bucket"
            exit 1
        fi
        log_success "Backup bucket created"
    else
        log_success "Backup bucket verified"
    fi
}

# Get table row count
get_row_count() {
    local project_id=$1
    local dataset=$2
    local table=$3

    local count=$(bq query --use_legacy_sql=false --format=csv --quiet \
        "SELECT COUNT(*) as count FROM \`${project_id}.${dataset}.${table}\`" 2>/dev/null | tail -n 1)

    echo "${count}"
}

# Get table size in bytes
get_table_size() {
    local project_id=$1
    local dataset=$2
    local table=$3

    local size=$(bq show --format=json "${project_id}:${dataset}.${table}" 2>/dev/null | \
        grep -o '"numBytes": "[0-9]*"' | grep -o '[0-9]*' || echo "0")

    echo "${size}"
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if ((bytes < 1024)); then
        echo "${bytes} B"
    elif ((bytes < 1048576)); then
        echo "$((bytes / 1024)) KB"
    elif ((bytes < 1073741824)); then
        echo "$((bytes / 1048576)) MB"
    else
        echo "$((bytes / 1073741824)) GB"
    fi
}

# Backup a single table
backup_table() {
    local project_id=$1
    local dataset=$2
    local table=$3
    local backup_uri="${BACKUP_PATH}/${table}.json"

    log_info "Backing up table: ${table}"

    # Get table metadata before backup
    local row_count=$(get_row_count "${project_id}" "${dataset}" "${table}")
    local table_size=$(get_table_size "${project_id}" "${dataset}" "${table}")
    local size_formatted=$(format_bytes "${table_size}")

    log_info "  Rows: ${row_count}, Size: ${size_formatted}"

    # Export table to GCS
    if bq extract \
        --destination_format=NEWLINE_DELIMITED_JSON \
        --compression=GZIP \
        "${project_id}:${dataset}.${table}" \
        "${backup_uri}.gz" 2>&1; then

        log_success "  Backup completed: ${backup_uri}.gz"

        # Verify backup file exists
        if gsutil ls "${backup_uri}.gz" &> /dev/null; then
            local backup_size=$(gsutil du -s "${backup_uri}.gz" | awk '{print $1}')
            local backup_size_formatted=$(format_bytes "${backup_size}")
            log_success "  Verified backup size: ${backup_size_formatted}"

            # Store metadata
            echo "${row_count}" > "/tmp/${table}_rows.txt"
            echo "${table_size}" > "/tmp/${table}_size.txt"

            return 0
        else
            log_error "  Backup file not found in GCS"
            return 1
        fi
    else
        log_error "  Failed to backup table: ${table}"
        return 1
    fi
}

# Create backup metadata file
create_backup_metadata() {
    local project_id=$1
    local dataset=$2
    local metadata_file="/tmp/backup_metadata_${TIMESTAMP}.json"

    log_info "Creating backup metadata..."

    cat > "${metadata_file}" << EOF
{
  "backup_timestamp": "${TIMESTAMP}",
  "backup_date": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "project_id": "${project_id}",
  "dataset": "${dataset}",
  "backup_location": "${BACKUP_PATH}",
  "tables": [
EOF

    local first=true
    for table in "${TABLES[@]}"; do
        if [[ -f "/tmp/${table}_rows.txt" ]]; then
            if [[ "${first}" == "false" ]]; then
                echo "," >> "${metadata_file}"
            fi
            first=false

            local rows=$(cat "/tmp/${table}_rows.txt")
            local size=$(cat "/tmp/${table}_size.txt")

            cat >> "${metadata_file}" << EOF
    {
      "table_name": "${table}",
      "row_count": ${rows},
      "size_bytes": ${size},
      "backup_file": "${BACKUP_PATH}/${table}.json.gz"
    }
EOF
        fi
    done

    cat >> "${metadata_file}" << EOF

  ],
  "backup_script_version": "1.0",
  "backup_completed": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}
EOF

    # Upload metadata to GCS
    if gsutil cp "${metadata_file}" "${BACKUP_PATH}/metadata.json"; then
        log_success "Metadata uploaded: ${BACKUP_PATH}/metadata.json"
        rm -f "${metadata_file}"
        return 0
    else
        log_error "Failed to upload metadata"
        return 1
    fi
}

# List recent backups
list_recent_backups() {
    log_info "Recent backups (last 10):"
    gsutil ls -l "${BACKUP_BUCKET}/" | grep "/$" | tail -n 10 || log_warning "No backups found"
}

# Cleanup old backups (keep last 30 days)
cleanup_old_backups() {
    log_info "Checking for old backups to cleanup..."

    local retention_days=30
    local cutoff_date=$(date -v-${retention_days}d '+%Y-%m-%d' 2>/dev/null || date -d "${retention_days} days ago" '+%Y-%m-%d')

    log_info "Retention policy: ${retention_days} days (cutoff: ${cutoff_date})"

    # List all backup directories
    local backup_dirs=$(gsutil ls "${BACKUP_BUCKET}/" | grep "/$" || echo "")

    if [[ -z "${backup_dirs}" ]]; then
        log_info "No backups found for cleanup"
        return 0
    fi

    local deleted_count=0
    while IFS= read -r backup_dir; do
        # Extract date from backup directory name (format: YYYY-MM-DD_HHMMSS)
        local backup_date=$(basename "${backup_dir}" | cut -d'_' -f1)

        if [[ "${backup_date}" < "${cutoff_date}" ]]; then
            log_info "Deleting old backup: ${backup_dir}"
            if gsutil -m rm -r "${backup_dir}"; then
                ((deleted_count++))
                log_success "Deleted: ${backup_dir}"
            else
                log_warning "Failed to delete: ${backup_dir}"
            fi
        fi
    done <<< "${backup_dirs}"

    if [[ ${deleted_count} -gt 0 ]]; then
        log_success "Cleaned up ${deleted_count} old backup(s)"
    else
        log_info "No old backups to cleanup"
    fi
}

# Main backup function
main() {
    echo ""
    echo "=============================================="
    echo "  EROS Scheduling System - Table Backup Script"
    echo "=============================================="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Get configuration
    PROJECT_ID=$(get_project_id)
    DATASET=$(get_dataset)

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Dataset: ${DATASET}"
    log_info "  Backup Location: ${BACKUP_PATH}"
    log_info "  Timestamp: ${TIMESTAMP}"
    echo ""

    # Verify backup bucket
    verify_backup_bucket
    echo ""

    # Backup each table
    log_info "Starting backup process..."
    echo ""

    local success_count=0
    local failure_count=0

    for table in "${TABLES[@]}"; do
        if backup_table "${PROJECT_ID}" "${DATASET}" "${table}"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
        echo ""
    done

    # Create metadata
    create_backup_metadata "${PROJECT_ID}" "${DATASET}"
    echo ""

    # Cleanup temporary files
    for table in "${TABLES[@]}"; do
        rm -f "/tmp/${table}_rows.txt" "/tmp/${table}_size.txt"
    done

    # List recent backups
    list_recent_backups
    echo ""

    # Cleanup old backups
    cleanup_old_backups
    echo ""

    # Summary
    echo "=============================================="
    echo "  Backup Summary"
    echo "=============================================="
    echo ""
    log_info "Total tables: ${#TABLES[@]}"
    log_success "Successful backups: ${success_count}"
    if [[ ${failure_count} -gt 0 ]]; then
        log_error "Failed backups: ${failure_count}"
    fi
    echo ""
    log_info "Backup location: ${BACKUP_PATH}"
    log_info "Backup timestamp: ${TIMESTAMP}"
    echo ""

    if [[ ${failure_count} -eq 0 ]]; then
        log_success "All backups completed successfully!"
        echo ""
        echo "To restore from this backup, run:"
        echo "  ./rollback.sh ${TIMESTAMP}"
        echo ""
        exit 0
    else
        log_error "Some backups failed. Please review errors above."
        echo ""
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Backup interrupted. Cleaning up..."; exit 130' INT TERM

# Run main function
main "$@"
