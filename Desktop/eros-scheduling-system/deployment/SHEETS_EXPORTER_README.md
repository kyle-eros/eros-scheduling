# EROS Sheets Exporter - Setup and Usage Guide

## Overview

The EROS Sheets Exporter is a production-ready integration that exports schedule recommendations from BigQuery to Google Sheets. It provides both Google Apps Script (for manual/interactive use) and Python client (for programmatic automation).

**Key Features:**
- Read-only exports from BigQuery view
- Duplicate prevention with 24-hour window
- Atomic operations with comprehensive logging
- Custom formatting and data validation
- Support for multiple creators/schedules

---

## Architecture

```
BigQuery (Source)
    ↓
schedule_recommendations_messages VIEW
    ↓
┌─────────────────────────────────┐
│   Google Apps Script            │  ← Manual/Interactive
│   (sheets_exporter.gs)          │
└─────────────────────────────────┘
           ↓
    Google Sheets
           ↓
    schedule_export_log TABLE
           ↑
┌─────────────────────────────────┐
│   Python Client                 │  ← Programmatic/Automation
│   (sheets_export_client.py)     │
└─────────────────────────────────┘
```

---

## Component Files

| File | Purpose | Environment |
|------|---------|-------------|
| `schedule_recommendations_messages_view.sql` | BigQuery view definition | BigQuery |
| `sheets_exporter.gs` | Google Apps Script exporter | Google Sheets |
| `sheets_export_client.py` | Python wrapper client | Local/Cloud |
| `sheets_config.json` | Configuration settings | Local/Cloud |

---

## Prerequisites

### Required Access
- Google Cloud Project: `of-scheduler-proj`
- BigQuery Dataset: `eros_scheduling_brain`
- Google Sheets spreadsheet (editor access)
- Service account with BigQuery permissions

### Required Tools
- Google Cloud SDK (`gcloud`)
- Python 3.8+
- Google Sheets with Apps Script enabled

### Required Python Packages
```bash
pip install google-cloud-bigquery google-auth google-api-python-client
```

---

## Part 1: BigQuery Setup

### Step 1: Deploy the View

```bash
# Navigate to deployment directory
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment

# Deploy the view to BigQuery
bq query --use_legacy_sql=false < schedule_recommendations_messages_view.sql
```

### Step 2: Verify the View

```bash
# Test the view with a sample query
bq query --use_legacy_sql=false "
SELECT schedule_id, page_name, COUNT(*) as message_count
FROM \`of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages\`
GROUP BY schedule_id, page_name
LIMIT 10
"
```

### Step 3: Create Export Log Table

```bash
bq query --use_legacy_sql=false "
CREATE TABLE IF NOT EXISTS \`of-scheduler-proj.eros_scheduling_brain.schedule_export_log\` (
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
"
```

---

## Part 2: Google Apps Script Setup

### Step 1: Open Google Sheets

1. Open your target Google Sheets spreadsheet
2. Click **Extensions > Apps Script**

### Step 2: Add the Script

1. Delete any existing code in `Code.gs`
2. Copy the entire contents of `sheets_exporter.gs`
3. Paste into the Apps Script editor
4. Save the project (Ctrl/Cmd + S)

### Step 3: Enable BigQuery API

1. In Apps Script editor, click **Services** (+ icon)
2. Find **BigQuery API**
3. Click **Add**

### Step 4: Update Configuration

In the Apps Script code, update the `CONFIG` object if needed:

```javascript
const CONFIG = {
  projectId: 'of-scheduler-proj',  // Your GCP project
  dataset: 'eros_scheduling_brain', // Your dataset
  viewName: 'schedule_recommendations_messages',
  logTable: 'schedule_export_log'
};
```

### Step 5: Test the Script

1. In Apps Script editor, select function `testBigQueryConnection`
2. Click **Run** (▶️)
3. Authorize the script when prompted
4. Check **Execution log** for success message

### Step 6: Deploy (Optional)

For automated triggering, deploy as API Executable:
1. Click **Deploy > New deployment**
2. Select type: **API Executable**
3. Set access to appropriate level
4. Copy the deployment ID

---

## Part 3: Python Client Setup

### Step 1: Install Dependencies

```bash
pip install google-cloud-bigquery google-auth google-api-python-client
```

### Step 2: Configure Service Account

1. Create a service account in GCP:
```bash
gcloud iam service-accounts create eros-sheets-exporter \
    --display-name="EROS Sheets Exporter"
```

2. Grant BigQuery permissions:
```bash
gcloud projects add-iam-policy-binding of-scheduler-proj \
    --member="serviceAccount:eros-sheets-exporter@of-scheduler-proj.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding of-scheduler-proj \
    --member="serviceAccount:eros-sheets-exporter@of-scheduler-proj.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"
```

3. Create and download key:
```bash
gcloud iam service-accounts keys create ~/eros-sheets-key.json \
    --iam-account=eros-sheets-exporter@of-scheduler-proj.iam.gserviceaccount.com
```

### Step 3: Update Configuration

Edit `sheets_config.json`:

```json
{
  "project_id": "of-scheduler-proj",
  "dataset": "eros_scheduling_brain",
  "spreadsheet_id": "YOUR_ACTUAL_SPREADSHEET_ID",
  "credentials_path": "/path/to/eros-sheets-key.json"
}
```

### Step 4: Test the Client

```bash
# Setup (create log table)
python3 sheets_export_client.py setup --config sheets_config.json

# Check recent export history
python3 sheets_export_client.py history --config sheets_config.json
```

---

## Usage Examples

### Method 1: Manual Export (Google Sheets UI)

1. Open your Google Sheets spreadsheet
2. Click **EROS Scheduler > Export Schedule from BigQuery**
3. Enter schedule ID (e.g., `SCH_A1B2C3D4`)
4. Click **OK**
5. View exported data in the created/updated sheet tab

### Method 2: Direct Apps Script Function

```javascript
// In Apps Script editor, run this function manually
function myExport() {
  var result = exportScheduleToSheet('SCH_A1B2C3D4', 'CreatorName');
  Logger.log(result);
}
```

### Method 3: Python Client (Programmatic)

```bash
# Export a specific schedule
python3 sheets_export_client.py export \
    --schedule-id SCH_A1B2C3D4 \
    --sheet-name "Creator Name" \
    --config sheets_config.json

# Check export status
python3 sheets_export_client.py status \
    --schedule-id SCH_A1B2C3D4 \
    --config sheets_config.json

# Force re-export (bypass duplicate check)
python3 sheets_export_client.py export \
    --schedule-id SCH_A1B2C3D4 \
    --force \
    --config sheets_config.json
```

### Method 4: Python Library Import

```python
from sheets_export_client import SheetsExportClient

# Initialize client
client = SheetsExportClient(config_path='sheets_config.json')

# Export schedule
result = client.export_schedule(
    schedule_id='SCH_A1B2C3D4',
    sheet_name='Creator Name',
    force=False
)

print(f"Status: {result['status']}")
print(f"Messages: {result.get('message_count', 0)}")

# Check export status
status = client.check_export_status('SCH_A1B2C3D4')
print(status)

# Get recent exports
history = client.get_recent_exports(limit=10)
for export in history:
    print(f"{export['schedule_id']}: {export['export_status']} - {export['record_count']} records")
```

---

## Output Format

### Exported Columns (11 total)

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| Schedule ID | STRING | Unique schedule identifier | SCH_A1B2C3D4 |
| Creator/Page | STRING | OnlyFans page name | creator_name |
| Day of Week | STRING | Day name | Monday |
| Send Time | TIMESTAMP | Scheduled send time | 2024-01-15 09:00:00 |
| Type | STRING | Message type | ppv, text, mass |
| Caption ID | INT64 | Caption identifier | 12345 |
| Caption Text | STRING | Full caption text | "Check out this new content..." |
| Price Tier | STRING | Pricing tier | premium, budget, vip |
| Category | STRING | Content category | teaser, explicit, bts |
| Has Urgency | BOOLEAN | Urgency flag | Yes/No |
| Performance Score | FLOAT64 | Conversion rate | 0.1523 (15.23%) |

### Sheet Formatting

- **Header row**: Bold, blue background (#4285f4), white text, frozen
- **Data rows**: Alternating gray banding for readability
- **Caption text**: Text wrapping enabled
- **Performance score**: Percentage format (0.00%)
- **Send time**: DateTime format (YYYY-MM-DD HH:MM:SS)
- **Columns**: Auto-resized to content

---

## Duplicate Prevention

### How It Works

1. Before export, system checks `schedule_export_log` table
2. If schedule was exported within 24 hours, export is skipped
3. User is notified of previous export details
4. Can be overridden with `force=True` parameter

### Duplicate Check Logic

```sql
-- Query to check for recent exports
SELECT *
FROM schedule_export_log
WHERE schedule_id = 'SCH_A1B2C3D4'
  AND export_status = 'success'
  AND exported_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY exported_at DESC
LIMIT 1
```

### Bypass Duplicate Check

```python
# Python
client.export_schedule('SCH_A1B2C3D4', force=True)
```

```javascript
// Apps Script - modify function to skip check
// Comment out the duplicate check section
```

---

## Error Handling

### Common Errors

#### 1. Schedule Not Found
```
Error: No data found for schedule ID: SCH_INVALID
```
**Solution**: Verify schedule exists in BigQuery view

#### 2. Permission Denied
```
Error: Access Denied: Table of-scheduler-proj:eros_scheduling_brain.schedule_export_log
```
**Solution**: Grant BigQuery permissions to service account

#### 3. Apps Script Timeout
```
Error: Script execution exceeded maximum time
```
**Solution**: Reduce schedule size or increase timeout in script

#### 4. Duplicate Export
```
Status: skipped
Reason: duplicate
Message: Schedule already exported 5 hours ago
```
**Solution**: Wait for 24-hour window or use `force=True`

### Error Logging

All errors are logged to:
1. BigQuery table: `schedule_export_log` (with error_message field)
2. Apps Script execution log
3. Python client log output

---

## Monitoring and Validation

### Query Recent Exports

```sql
-- Last 10 exports
SELECT
  schedule_id,
  export_status,
  record_count,
  sheet_name,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', exported_at) AS exported_at,
  duration_seconds
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
ORDER BY exported_at DESC
LIMIT 10;
```

### Export Success Rate

```sql
-- Success rate by day
SELECT
  DATE(exported_at) AS export_date,
  COUNT(*) AS total_exports,
  COUNT(CASE WHEN export_status = 'success' THEN 1 END) AS successful_exports,
  ROUND(COUNT(CASE WHEN export_status = 'success' THEN 1 END) / COUNT(*) * 100, 2) AS success_rate,
  AVG(duration_seconds) AS avg_duration_seconds
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE exported_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY export_date
ORDER BY export_date DESC;
```

### Failed Exports

```sql
-- Recent failures
SELECT
  schedule_id,
  error_message,
  exported_at
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE export_status = 'error'
  AND exported_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY exported_at DESC;
```

---

## Automation Options

### Option 1: Cloud Function Trigger

Deploy Python client as Cloud Function:

```python
# cloud_function.py
from sheets_export_client import SheetsExportClient

def export_schedule_http(request):
    """HTTP Cloud Function to trigger export."""
    request_json = request.get_json()
    schedule_id = request_json.get('schedule_id')

    client = SheetsExportClient()
    result = client.export_schedule(schedule_id)

    return result
```

### Option 2: Cloud Scheduler + Pub/Sub

```bash
# Create Pub/Sub topic
gcloud pubsub topics create schedule-exports

# Create Cloud Scheduler job
gcloud scheduler jobs create pubsub export-daily-schedules \
    --schedule="0 8 * * *" \
    --topic=schedule-exports \
    --message-body='{"schedule_id": "SCH_A1B2C3D4"}'
```

### Option 3: GitHub Actions

```yaml
# .github/workflows/export_schedules.yml
name: Export Schedules

on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8am
  workflow_dispatch:

jobs:
  export:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
      - run: pip install -r requirements.txt
      - run: python3 sheets_export_client.py export --schedule-id ${{ secrets.SCHEDULE_ID }}
```

---

## Troubleshooting

### Apps Script Issues

**Problem**: "BigQuery API not found"
```
Solution: Enable BigQuery API in Apps Script Services
```

**Problem**: "Authorization required"
```
Solution: Run script manually first to authorize OAuth
```

**Problem**: "Execution timeout"
```
Solution: Increase timeout or reduce schedule size
```

### Python Client Issues

**Problem**: "No module named 'google.cloud'"
```bash
Solution: pip install google-cloud-bigquery
```

**Problem**: "Application Default Credentials not found"
```bash
Solution: Set credentials path in config or run:
gcloud auth application-default login
```

**Problem**: "Permission denied"
```bash
Solution: Grant service account BigQuery permissions
```

---

## Best Practices

### 1. Schedule ID Naming
- Use consistent prefix: `SCH_`
- Include date/creator identifier
- Example: `SCH_20240115_CREATOR1`

### 2. Sheet Organization
- One sheet tab per creator/schedule
- Clear naming conventions
- Archive old schedules to separate sheets

### 3. Export Frequency
- Respect 24-hour duplicate window
- Export after schedule generation
- Use force flag only when necessary

### 4. Error Recovery
- Monitor export logs regularly
- Set up alerts for failures
- Implement retry logic for transient errors

### 5. Performance
- Limit schedule size to <500 messages
- Use partitioned views for large datasets
- Clean up old export logs periodically

---

## Security Considerations

### 1. Service Account Permissions
- Grant minimum required permissions
- Use separate service accounts per environment
- Rotate keys regularly

### 2. API Access
- Restrict Apps Script deployment to authorized users
- Use private/internal access for API executables
- Implement authentication for webhooks

### 3. Data Privacy
- Ensure Sheets have appropriate sharing settings
- Use private/restricted sheets for sensitive data
- Audit access logs regularly

---

## Maintenance

### Regular Tasks

**Weekly:**
- Review export success rate
- Check for failed exports
- Verify data accuracy

**Monthly:**
- Clean up old export logs (>90 days)
- Review and update service account permissions
- Update Apps Script if needed

**Quarterly:**
- Performance tuning
- Schema validation
- Documentation updates

### Cleanup Script

```sql
-- Delete old export logs (keep 90 days)
DELETE FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE exported_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);
```

---

## Support and Contact

For issues or questions:
- Check BigQuery logs: `schedule_export_log` table
- Review Apps Script execution logs
- Examine Python client output
- Consult EROS system documentation

---

## Version History

**v1.0.0** (2025-10-31)
- Initial production release
- BigQuery view integration
- Apps Script exporter
- Python client wrapper
- Duplicate prevention
- Comprehensive logging

---

## Appendix A: Complete File Listing

```
deployment/
├── schedule_recommendations_messages_view.sql   # BigQuery view definition
├── sheets_exporter.gs                          # Google Apps Script
├── sheets_export_client.py                     # Python client
├── sheets_config.json                          # Configuration
└── SHEETS_EXPORTER_README.md                   # This file
```

---

## Appendix B: Sample Export Output

```
Schedule ID: SCH_20240115_CREATOR1
Creator/Page: creator_name
Messages Exported: 42
Export Duration: 2.34 seconds
Sheet Name: creator_name
Exported At: 2024-01-15T08:30:45Z

Sample Data:
+----------------+-------------+------------+---------------------+------+-----------+------------------+------------+----------+-------------+-------------------+
| Schedule ID    | Creator     | Day        | Send Time           | Type | Caption ID| Caption Text     | Price Tier | Category | Has Urgency | Performance Score |
+----------------+-------------+------------+---------------------+------+-----------+------------------+------------+----------+-------------+-------------------+
| SCH_20240115   | creator_name| Monday     | 2024-01-15 09:00:00 | ppv  | 12345     | Check out this...| premium    | teaser   | Yes         | 0.1523           |
| SCH_20240115   | creator_name| Monday     | 2024-01-15 15:00:00 | text | NULL      | Good afternoon!  | NULL       | NULL     | No          | NULL             |
| SCH_20240115   | creator_name| Monday     | 2024-01-15 21:00:00 | ppv  | 12346     | New content...   | vip        | explicit | Yes         | 0.1876           |
+----------------+-------------+------------+---------------------+------+-----------+------------------+------------+----------+-------------+-------------------+
```

---

## Appendix C: SQL Schema Reference

### schedule_recommendations_messages VIEW

```sql
CREATE OR REPLACE VIEW schedule_recommendations_messages AS
SELECT
  sr.schedule_id,              -- STRING: Unique schedule identifier
  sr.page_name,                -- STRING: Creator/page name
  sr.day_of_week,              -- STRING: Day name (Monday-Sunday)
  sr.scheduled_send_time,      -- TIMESTAMP: Scheduled send datetime
  sr.message_type,             -- STRING: ppv, text, mass
  sr.caption_id,               -- INT64: Caption identifier (nullable)
  c.caption_text,              -- STRING: Full caption text (nullable)
  c.price_tier,                -- STRING: Pricing tier (nullable)
  c.content_category,          -- STRING: Content category (nullable)
  c.has_urgency,               -- BOOLEAN: Urgency flag (nullable)
  cbs.avg_conversion_rate      -- FLOAT64: Performance score (nullable)
FROM schedule_recommendations sr
LEFT JOIN captions c ON sr.caption_id = c.caption_id
LEFT JOIN caption_bandit_stats cbs ON sr.caption_id = cbs.caption_id
  AND sr.page_name = cbs.page_name
WHERE sr.is_active = TRUE;
```

### schedule_export_log TABLE

```sql
CREATE TABLE schedule_export_log (
  schedule_id STRING NOT NULL,          -- Schedule that was exported
  export_status STRING NOT NULL,        -- success, error, skipped
  record_count INT64,                   -- Number of records exported
  duration_seconds FLOAT64,             -- Export duration
  sheet_name STRING,                    -- Target sheet name
  error_message STRING,                 -- Error details (if failed)
  exported_at TIMESTAMP NOT NULL,       -- Export timestamp
  exported_by STRING                    -- User/service account
)
PARTITION BY DATE(exported_at)
CLUSTER BY schedule_id, export_status;
```

---

**End of Documentation**
