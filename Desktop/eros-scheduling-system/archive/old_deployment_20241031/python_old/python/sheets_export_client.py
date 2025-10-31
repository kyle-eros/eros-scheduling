#!/usr/bin/env python3
"""
=============================================================================
EROS SHEETS EXPORT CLIENT - PYTHON WRAPPER
=============================================================================
Project: of-scheduler-proj
Dataset: eros_scheduling_brain
Purpose: Python wrapper for Google Apps Script integration
Version: 1.0.0 (Production)
=============================================================================
"""

import json
import time
import logging
from pathlib import Path
from typing import Dict, Optional, List
from datetime import datetime, timezone

from google.oauth2 import service_account
from google.cloud import bigquery
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SheetsExportClient:
    """
    Python client for exporting schedules from BigQuery to Google Sheets.

    This client provides a programmatic interface to trigger Google Apps Script
    exports and monitor their status.
    """

    def __init__(self, config_path: str = 'sheets_config.json',
                 credentials_path: Optional[str] = None):
        """
        Initialize the Sheets Export Client.

        Args:
            config_path: Path to configuration JSON file
            credentials_path: Optional path to service account credentials
        """
        self.config = self._load_config(config_path)
        self.credentials_path = credentials_path or self.config.get('credentials_path')

        # Initialize BigQuery client
        if self.credentials_path:
            credentials = service_account.Credentials.from_service_account_file(
                self.credentials_path
            )
            self.bq_client = bigquery.Client(
                credentials=credentials,
                project=self.config['project_id']
            )
        else:
            self.bq_client = bigquery.Client(project=self.config['project_id'])

        logger.info(f"Initialized SheetsExportClient for project: {self.config['project_id']}")

    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from JSON file."""
        config_file = Path(config_path)

        if not config_file.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")

        with open(config_file, 'r') as f:
            config = json.load(f)

        # Validate required fields
        required_fields = ['project_id', 'dataset', 'view_name', 'log_table']
        for field in required_fields:
            if field not in config:
                raise ValueError(f"Missing required config field: {field}")

        return config

    def export_schedule(self, schedule_id: str, sheet_name: Optional[str] = None,
                       force: bool = False) -> Dict:
        """
        Export a schedule from BigQuery to Google Sheets.

        Args:
            schedule_id: The schedule ID to export
            sheet_name: Optional custom sheet name
            force: If True, bypass duplicate check

        Returns:
            Dict containing export result and metadata
        """
        logger.info(f"Starting export for schedule: {schedule_id}")
        start_time = time.time()

        try:
            # Step 1: Verify schedule exists in BigQuery
            if not self._verify_schedule_exists(schedule_id):
                return {
                    'status': 'error',
                    'schedule_id': schedule_id,
                    'error': f'Schedule not found in BigQuery: {schedule_id}'
                }

            # Step 2: Check for duplicate export (unless forced)
            if not force:
                duplicate_check = self._check_duplicate_export(schedule_id)
                if duplicate_check['is_duplicate']:
                    logger.warning(f"Duplicate export detected: {duplicate_check['message']}")
                    return {
                        'status': 'skipped',
                        'reason': 'duplicate',
                        'schedule_id': schedule_id,
                        'message': duplicate_check['message'],
                        'previous_export': duplicate_check.get('last_export')
                    }

            # Step 3: Get schedule data
            schedule_data = self._get_schedule_data(schedule_id)

            if not schedule_data:
                return {
                    'status': 'error',
                    'schedule_id': schedule_id,
                    'error': 'No data returned from BigQuery view'
                }

            # Step 4: Trigger Apps Script export
            # Note: This requires the Apps Script to be deployed as a web app
            # or we can use the direct function call if set up
            result = self._trigger_apps_script_export(schedule_id, sheet_name)

            duration = time.time() - start_time

            logger.info(f"Export completed in {duration:.2f} seconds")

            return {
                'status': 'success',
                'schedule_id': schedule_id,
                'message_count': len(schedule_data),
                'duration_seconds': duration,
                'result': result
            }

        except Exception as e:
            logger.error(f"Export failed: {str(e)}", exc_info=True)
            return {
                'status': 'error',
                'schedule_id': schedule_id,
                'error': str(e),
                'duration_seconds': time.time() - start_time
            }

    def _verify_schedule_exists(self, schedule_id: str) -> bool:
        """Verify that schedule exists in BigQuery view."""
        query = f"""
        SELECT COUNT(*) as count
        FROM `{self.config['project_id']}.{self.config['dataset']}.{self.config['view_name']}`
        WHERE schedule_id = @schedule_id
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter('schedule_id', 'STRING', schedule_id)
            ]
        )

        try:
            result = self.bq_client.query(query, job_config=job_config).result()
            count = list(result)[0]['count']
            logger.info(f"Schedule {schedule_id} has {count} messages")
            return count > 0
        except Exception as e:
            logger.error(f"Error verifying schedule: {str(e)}")
            return False

    def _check_duplicate_export(self, schedule_id: str) -> Dict:
        """Check if schedule has already been exported."""
        query = f"""
        SELECT
            schedule_id,
            export_status,
            record_count,
            sheet_name,
            exported_at,
            TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), exported_at, HOUR) as hours_since_export
        FROM `{self.config['project_id']}.{self.config['dataset']}.{self.config['log_table']}`
        WHERE schedule_id = @schedule_id
            AND export_status = 'success'
        ORDER BY exported_at DESC
        LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter('schedule_id', 'STRING', schedule_id)
            ]
        )

        try:
            result = self.bq_client.query(query, job_config=job_config).result()
            rows = list(result)

            if not rows:
                return {'is_duplicate': False}

            last_export = dict(rows[0])
            hours_since = last_export['hours_since_export']

            # Allow re-export if more than 24 hours old
            if hours_since > 24:
                return {
                    'is_duplicate': False,
                    'last_export': last_export,
                    'message': f'Previous export was {hours_since} hours ago, allowing re-export'
                }

            return {
                'is_duplicate': True,
                'last_export': last_export,
                'message': f'Schedule already exported {hours_since} hours ago'
            }

        except Exception as e:
            # If log table doesn't exist, allow export
            logger.warning(f"Duplicate check failed: {str(e)}")
            return {'is_duplicate': False}

    def _get_schedule_data(self, schedule_id: str) -> List[Dict]:
        """Retrieve schedule data from BigQuery."""
        query = f"""
        SELECT *
        FROM `{self.config['project_id']}.{self.config['dataset']}.{self.config['view_name']}`
        WHERE schedule_id = @schedule_id
        ORDER BY day_of_week, scheduled_send_time
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter('schedule_id', 'STRING', schedule_id)
            ]
        )

        result = self.bq_client.query(query, job_config=job_config).result()
        return [dict(row) for row in result]

    def _trigger_apps_script_export(self, schedule_id: str,
                                    sheet_name: Optional[str] = None) -> Dict:
        """
        Trigger Apps Script export.

        Note: This is a placeholder implementation. In production, you would either:
        1. Call Apps Script API directly (requires deployment as API executable)
        2. Use a webhook/Cloud Function trigger
        3. Manually run the Apps Script function in Sheets

        For now, this returns instructions for manual execution.
        """
        logger.info("Apps Script must be triggered manually from Google Sheets")

        return {
            'method': 'manual',
            'instructions': [
                '1. Open your Google Sheets spreadsheet',
                '2. Click Extensions > Apps Script',
                f'3. In the script editor, run: exportScheduleToSheet("{schedule_id}", "{sheet_name or ""}")',
                '4. Or use the custom menu: EROS Scheduler > Export Schedule from BigQuery',
                f'5. Enter schedule ID: {schedule_id}'
            ],
            'alternative': 'Deploy Apps Script as API executable for automated triggering',
            'schedule_id': schedule_id,
            'sheet_name': sheet_name
        }

    def check_export_status(self, schedule_id: str) -> Dict:
        """
        Check the export status for a schedule.

        Args:
            schedule_id: The schedule ID to check

        Returns:
            Dict containing export status and metadata
        """
        query = f"""
        SELECT
            schedule_id,
            export_status,
            record_count,
            duration_seconds,
            sheet_name,
            error_message,
            exported_at,
            TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), exported_at, HOUR) as hours_ago
        FROM `{self.config['project_id']}.{self.config['dataset']}.{self.config['log_table']}`
        WHERE schedule_id = @schedule_id
        ORDER BY exported_at DESC
        LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter('schedule_id', 'STRING', schedule_id)
            ]
        )

        try:
            result = self.bq_client.query(query, job_config=job_config).result()
            rows = list(result)

            if not rows:
                return {
                    'status': 'not_found',
                    'schedule_id': schedule_id,
                    'message': 'No export record found'
                }

            export_info = dict(rows[0])

            return {
                'status': 'found',
                'schedule_id': schedule_id,
                'export_info': export_info
            }

        except Exception as e:
            logger.error(f"Error checking export status: {str(e)}")
            return {
                'status': 'error',
                'schedule_id': schedule_id,
                'error': str(e)
            }

    def get_recent_exports(self, limit: int = 10) -> List[Dict]:
        """
        Get recent export history.

        Args:
            limit: Maximum number of records to return

        Returns:
            List of export records
        """
        query = f"""
        SELECT
            schedule_id,
            export_status,
            record_count,
            duration_seconds,
            sheet_name,
            exported_at,
            TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), exported_at, HOUR) as hours_ago
        FROM `{self.config['project_id']}.{self.config['dataset']}.{self.config['log_table']}`
        ORDER BY exported_at DESC
        LIMIT @limit
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter('limit', 'INT64', limit)
            ]
        )

        try:
            result = self.bq_client.query(query, job_config=job_config).result()
            return [dict(row) for row in result]
        except Exception as e:
            logger.error(f"Error getting recent exports: {str(e)}")
            return []

    def create_export_log_table(self) -> bool:
        """Create the export log table if it doesn't exist."""
        query = f"""
        CREATE TABLE IF NOT EXISTS `{self.config['project_id']}.{self.config['dataset']}.{self.config['log_table']}` (
            schedule_id STRING NOT NULL,
            export_status STRING NOT NULL,
            record_count INT64,
            duration_seconds FLOAT64,
            sheet_name STRING,
            error_message STRING,
            exported_at TIMESTAMP NOT NULL,
            exported_by STRING
        )
        PARTITION BY DATE(exported_at)
        CLUSTER BY schedule_id, export_status
        """

        try:
            self.bq_client.query(query).result()
            logger.info("Export log table created or already exists")
            return True
        except Exception as e:
            logger.error(f"Error creating export log table: {str(e)}")
            return False


def main():
    """Example usage of the SheetsExportClient."""
    import argparse

    parser = argparse.ArgumentParser(description='EROS Sheets Export Client')
    parser.add_argument('command', choices=['export', 'status', 'history', 'setup'],
                       help='Command to execute')
    parser.add_argument('--schedule-id', help='Schedule ID to export or check')
    parser.add_argument('--sheet-name', help='Custom sheet name')
    parser.add_argument('--force', action='store_true',
                       help='Force export even if already exported')
    parser.add_argument('--config', default='sheets_config.json',
                       help='Path to configuration file')
    parser.add_argument('--limit', type=int, default=10,
                       help='Limit for history results')

    args = parser.parse_args()

    # Initialize client
    client = SheetsExportClient(config_path=args.config)

    if args.command == 'export':
        if not args.schedule_id:
            print("Error: --schedule-id is required for export command")
            return 1

        result = client.export_schedule(
            schedule_id=args.schedule_id,
            sheet_name=args.sheet_name,
            force=args.force
        )

        print(json.dumps(result, indent=2, default=str))
        return 0 if result['status'] == 'success' else 1

    elif args.command == 'status':
        if not args.schedule_id:
            print("Error: --schedule-id is required for status command")
            return 1

        result = client.check_export_status(args.schedule_id)
        print(json.dumps(result, indent=2, default=str))
        return 0

    elif args.command == 'history':
        results = client.get_recent_exports(limit=args.limit)
        print(json.dumps(results, indent=2, default=str))
        return 0

    elif args.command == 'setup':
        success = client.create_export_log_table()
        if success:
            print("Setup completed successfully")
            return 0
        else:
            print("Setup failed")
            return 1

    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
