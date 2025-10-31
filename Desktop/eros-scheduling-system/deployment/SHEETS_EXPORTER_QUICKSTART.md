# EROS Sheets Exporter - Quick Start Guide

## 5-Minute Setup

### Prerequisites
- Access to GCP project `of-scheduler-proj`
- Google Sheets with editor permissions
- Python 3.8+ installed locally

---

## Step 1: Deploy BigQuery View (2 minutes)

```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment

# Deploy the view
bq query --use_legacy_sql=false < schedule_recommendations_messages_view.sql

# Create log table
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

## Step 2: Add Apps Script to Google Sheets (2 minutes)

1. **Open your Google Sheets spreadsheet**

2. **Click: Extensions > Apps Script**

3. **Copy/paste entire `sheets_exporter.gs` file**

4. **Enable BigQuery API:**
   - Click Services (+ icon)
   - Select "BigQuery API"
   - Click Add

5. **Save the project** (Ctrl/Cmd + S)

6. **Test the connection:**
   - Select function: `testBigQueryConnection`
   - Click Run (▶️)
   - Authorize when prompted
   - Check logs for "BigQuery connection successful"

---

## Step 3: Export Your First Schedule (1 minute)

### Method A: From Sheets Menu (Easiest)

1. In Google Sheets, click **EROS Scheduler > Export Schedule from BigQuery**
2. Enter your schedule ID (e.g., `SCH_A1B2C3D4`)
3. Click OK
4. View exported data in new/updated sheet tab

### Method B: Run Function Directly

In Apps Script editor:

```javascript
function myExport() {
  exportScheduleToSheet('SCH_YOUR_SCHEDULE_ID', 'Optional_Sheet_Name');
}
```

Click Run (▶️)

---

## Python Client Setup (Optional - for automation)

```bash
# Install dependencies
pip install google-cloud-bigquery google-auth google-api-python-client

# Update config
# Edit sheets_config.json with your spreadsheet_id and credentials_path

# Test
python3 sheets_export_client.py history --config sheets_config.json
```

---

## Verify Success

### Check in Google Sheets:
- [ ] New sheet tab created with schedule name
- [ ] 11 columns with headers (bold, blue background)
- [ ] Data rows populated
- [ ] Performance score shows as percentage
- [ ] Caption text is readable

### Check in BigQuery:
```sql
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
ORDER BY exported_at DESC
LIMIT 5;
```

Should show your export with status = 'success'

---

## Common Issues

**"Schedule not found"**
```sql
-- Verify schedule exists
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations_messages`
WHERE schedule_id = 'YOUR_SCHEDULE_ID'
LIMIT 10;
```

**"Permission denied"**
- Ensure you have BigQuery Data Viewer role
- Authorize Apps Script when prompted

**"Apps Script timeout"**
- Schedule is too large (>500 messages)
- Try smaller schedule or increase timeout

---

## Need Help?

- Full documentation: `SHEETS_EXPORTER_README.md`
- Agent spec: `/agents/sheets-exporter.md`
- Test validation: `python3 test_sheets_exporter.py`

---

## What's Next?

1. **Export schedules for all creators**
2. **Set up automated exports** (Cloud Function/Scheduler)
3. **Monitor export logs** in BigQuery
4. **Share sheets** with team members

---

**That's it! You're ready to export schedules to Google Sheets.**
