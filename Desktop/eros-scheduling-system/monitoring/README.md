# Caption Restrictions Monitoring Setup

**Project**: OnlyFans Scheduling System - Caption Restrictions Feature
**Dataset**: `of-scheduler-proj.eros_scheduling_brain`
**Last Updated**: 2025-10-29

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [BigQuery to Looker Studio Setup](#bigquery-to-looker-studio-setup)
4. [BigQuery to Grafana Setup](#bigquery-to-grafana-setup)
5. [Monitoring Queries](#monitoring-queries)
6. [Alert Configuration](#alert-configuration)
7. [Cost Monitoring](#cost-monitoring)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This document provides step-by-step instructions to set up monitoring for the Caption Restrictions feature. The monitoring stack tracks:

- Caption pool health (availability by tier/category)
- Restriction filter rates (% of captions blocked)
- Query performance (latency, bytes scanned)
- Cost tracking (daily/monthly spend)
- Audit trail (restriction changes)

**Recommended Tools**:
- **Looker Studio** (free, Google native, easiest setup)
- **Grafana** (advanced, self-hosted, more customization)
- **Cloud Monitoring** (GCP native, integrated alerts)

---

## Quick Start

### Option 1: Looker Studio (Recommended for Beginners)

**Time to Setup**: ~10 minutes

1. Navigate to [Looker Studio](https://lookerstudio.google.com/)
2. Click **Create** → **Data Source**
3. Select **BigQuery**
4. Authorize with Google account that has `bigquery.jobUser` role
5. Select:
   - Project: `of-scheduler-proj`
   - Dataset: `eros_scheduling_brain`
   - Table: `caption_restrictions`
6. Click **Connect**
7. Create Dashboard using pre-built template (see Section 3)

### Option 2: Grafana (Advanced Users)

**Time to Setup**: ~30 minutes

1. Install Grafana: `brew install grafana` (macOS) or use Docker
2. Install BigQuery plugin: `grafana-cli plugins install doitintl-bigquery-datasource`
3. Configure data source with service account (see Section 4)
4. Import dashboard JSON from `/monitoring/grafana_dashboard.json`

### Option 3: Query Scheduling in BigQuery

**Time to Setup**: ~5 minutes

1. Use BigQuery Scheduled Queries (free, no external tools)
2. Schedule queries to run hourly/daily
3. Export results to Google Sheets or send via email
4. See Section 5 for pre-built queries

---

## BigQuery to Looker Studio Setup

### Step 1: Create Data Sources

#### Data Source 1: Caption Restrictions Table

1. Go to [Looker Studio](https://lookerstudio.google.com/)
2. Click **Create** → **Data Source**
3. Select **BigQuery** connector
4. Choose **Custom Query** option
5. Project: `of-scheduler-proj`
6. Paste query:

```sql
SELECT
  restriction_id,
  restriction_type,
  target_scope,
  target_value,
  effective_date,
  expiration_date,
  is_active,
  created_at,
  created_by,
  restriction_notes
FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
WHERE effective_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
```

7. Click **Connect**
8. Name: "Caption Restrictions (90-day)"

#### Data Source 2: Caption Pool Health

1. Create new Data Source (repeat steps above)
2. Use query:

```sql
WITH recent_usage AS (
  SELECT DISTINCT caption_id
  FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE scheduled_send_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND is_active = TRUE
)
SELECT
  ac.price_tier,
  ac.content_category,
  COUNT(*) AS total_captions,
  COUNT(ru.caption_id) AS used_captions,
  COUNT(*) - COUNT(ru.caption_id) AS available_captions,
  CASE
    WHEN COUNT(*) - COUNT(ru.caption_id) < 10 THEN 'CRITICAL'
    WHEN COUNT(*) - COUNT(ru.caption_id) < 50 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS pool_status,
  CURRENT_TIMESTAMP() AS last_updated
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions` ac
LEFT JOIN recent_usage ru ON ac.caption_id = ru.caption_id
GROUP BY ac.price_tier, ac.content_category
```

3. Name: "Caption Pool Health"

#### Data Source 3: Query Performance

1. Create new Data Source
2. Use query:

```sql
SELECT
  TIMESTAMP_TRUNC(creation_time, HOUR) AS query_hour,
  COUNT(*) AS query_count,
  AVG(total_slot_ms) / 1000 AS avg_execution_seconds,
  MAX(total_slot_ms) / 1000 AS max_execution_seconds,
  APPROX_QUANTILES(total_slot_ms / 1000, 100)[OFFSET(95)] AS p95_execution_seconds,
  SUM(total_bytes_processed) / POW(10, 9) AS total_gb_scanned
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND REGEXP_CONTAINS(query, r'caption_restrictions')
GROUP BY query_hour
ORDER BY query_hour DESC
```

3. Name: "Caption Restrictions Query Performance"

### Step 2: Create Dashboard

1. Click **Create** → **Report**
2. Add Data Source: "Caption Pool Health"
3. Add visualizations (see below)

#### Visualization 1: Caption Pool Status (Scorecard)

- **Chart Type**: Scorecard
- **Metric**: `available_captions` (SUM)
- **Dimension**: `pool_status`
- **Filter**: `pool_status = 'CRITICAL'` (add separate scorecards for WARNING, HEALTHY)
- **Style**:
  - CRITICAL: Red background
  - WARNING: Yellow background
  - HEALTHY: Green background

#### Visualization 2: Caption Pool Trend (Time Series)

- **Chart Type**: Time series (line chart)
- **Date Range Dimension**: `last_updated`
- **Dimension**: `price_tier`
- **Metric**: `available_captions`
- **Breakdown Dimension**: `content_category`
- **Date Range**: Last 7 days

#### Visualization 3: Active Restrictions Summary (Table)

- **Data Source**: "Caption Restrictions (90-day)"
- **Chart Type**: Table
- **Dimensions**: `target_scope`, `target_value`, `restriction_type`, `effective_date`
- **Metrics**: `is_active` (filter = TRUE)
- **Sort**: `effective_date` DESC

#### Visualization 4: Restriction Type Distribution (Pie Chart)

- **Data Source**: "Caption Restrictions (90-day)"
- **Chart Type**: Pie chart
- **Dimension**: `restriction_type`
- **Metric**: `restriction_id` (COUNT)
- **Filter**: `is_active = TRUE`

#### Visualization 5: Query Performance (Line Chart)

- **Data Source**: "Caption Restrictions Query Performance"
- **Chart Type**: Time series (line chart)
- **Date Range Dimension**: `query_hour`
- **Metrics**: `p95_execution_seconds`, `avg_execution_seconds`
- **Right Axis**: `total_gb_scanned`

### Step 3: Configure Auto-Refresh

1. Click **File** → **Report Settings**
2. Data Freshness: **1 hour** (for caption pool health)
3. Email Schedule: Daily at 9am (for summary reports)

### Step 4: Share Dashboard

1. Click **Share** button
2. Add email addresses or groups:
   - `engineering@yourcompany.com`
   - `sre-team@yourcompany.com`
3. Permission: **Viewer** (prevents accidental edits)

---

## BigQuery to Grafana Setup

### Step 1: Install Grafana

#### Option A: macOS (Homebrew)
```bash
brew install grafana
brew services start grafana
# Access at http://localhost:3000 (admin/admin)
```

#### Option B: Docker
```bash
docker run -d -p 3000:3000 --name=grafana grafana/grafana
# Access at http://localhost:3000
```

#### Option C: GCP Compute Engine (Production)
```bash
# SSH into VM
gcloud compute ssh grafana-instance --zone=us-central1-a

# Install Grafana
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt-get update
sudo apt-get install grafana

# Start service
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

### Step 2: Install BigQuery Plugin

```bash
# Install plugin
grafana-cli plugins install doitintl-bigquery-datasource

# Restart Grafana
sudo systemctl restart grafana-server  # Linux
brew services restart grafana           # macOS
```

### Step 3: Create Service Account for Grafana

```bash
# Create service account
gcloud iam service-accounts create grafana-bigquery-reader \
  --display-name="Grafana BigQuery Reader" \
  --project=of-scheduler-proj

# Grant BigQuery roles
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# Create key file
gcloud iam service-accounts keys create ~/grafana-bq-key.json \
  --iam-account=grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com

# Secure the key file
chmod 400 ~/grafana-bq-key.json
```

### Step 4: Configure BigQuery Data Source in Grafana

1. Open Grafana: http://localhost:3000
2. Login: admin / admin (change password)
3. Navigate: Configuration → Data Sources → Add data source
4. Select: **BigQuery**
5. Configuration:
   - **Name**: `BigQuery - eros_scheduling_brain`
   - **Authentication Type**: `Google JWT File`
   - **Project**: `of-scheduler-proj`
   - **Upload JWT File**: Select `~/grafana-bq-key.json`
6. Click **Save & Test** (should show "Success")

### Step 5: Import Dashboard

1. Navigate: Dashboards → Import
2. Upload JSON file: `/monitoring/grafana_dashboard.json`
3. Select Data Source: `BigQuery - eros_scheduling_brain`
4. Click **Import**

### Step 6: Configure Alerts (Grafana Alerting)

#### Alert 1: Caption Pool Critical

1. Edit Panel: "Caption Pool Health"
2. Click **Alert** tab
3. Create Alert Rule:
   - **Name**: Caption Pool Critical
   - **Condition**: `WHEN avg() OF query(A, 1h, now) IS BELOW 10`
   - **Evaluate every**: 5 minutes
   - **For**: 10 minutes (prevents flapping)
4. Notification:
   - **Send to**: Slack, PagerDuty, Email
   - **Message**: "Caption pool critical: {{value}} captions available for {{tier}}/{{category}}"

#### Alert 2: High Query Latency

1. Edit Panel: "Query Performance"
2. Create Alert Rule:
   - **Name**: High Query Latency
   - **Condition**: `WHEN avg() OF query(p95_execution_seconds, 1h, now) IS ABOVE 0.5`
   - **Evaluate every**: 15 minutes
   - **For**: 30 minutes
3. Notification:
   - **Send to**: Slack #engineering-alerts
   - **Message**: "Caption restrictions queries are slow: {{value}}s P95 latency"

---

## Monitoring Queries

### Query 1: Caption Pool Health by Tier/Category

**Purpose**: Monitor available captions after cooldown + restrictions
**Schedule**: Every 4 hours
**Alert Threshold**: available_captions < 10

```sql
WITH recent_usage AS (
  SELECT DISTINCT caption_id
  FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
  WHERE scheduled_send_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND is_active = TRUE
),
restricted_captions AS (
  SELECT
    JSON_EXTRACT_SCALAR(restriction_patterns, '$.excluded_caption_ids[0]') AS caption_id
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
  WHERE is_active = TRUE
    AND effective_date <= CURRENT_DATE()
    AND (expiration_date IS NULL OR expiration_date >= CURRENT_DATE())
)
SELECT
  ac.price_tier,
  ac.content_category,
  COUNT(*) AS total_captions,
  COUNT(ru.caption_id) AS cooldown_excluded,
  COUNT(rc.caption_id) AS restriction_excluded,
  COUNT(*) - COUNT(ru.caption_id) - COUNT(rc.caption_id) AS available_captions,
  ROUND(SAFE_DIVIDE(COUNT(rc.caption_id), COUNT(*)) * 100, 2) AS restriction_filter_rate_pct,
  CASE
    WHEN COUNT(*) - COUNT(ru.caption_id) - COUNT(rc.caption_id) < 10 THEN 'CRITICAL'
    WHEN COUNT(*) - COUNT(ru.caption_id) - COUNT(rc.caption_id) < 50 THEN 'WARNING'
    ELSE 'HEALTHY'
  END AS pool_status,
  CURRENT_TIMESTAMP() AS checked_at
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions` ac
LEFT JOIN recent_usage ru ON ac.caption_id = ru.caption_id
LEFT JOIN restricted_captions rc ON ac.caption_id = rc.caption_id
GROUP BY ac.price_tier, ac.content_category
ORDER BY available_captions ASC;
```

**Export to Google Sheets**:
```bash
# Schedule this query to export results to a Google Sheet for daily review
bq query --use_legacy_sql=false --destination_table=of-scheduler-proj:eros_scheduling_brain.caption_pool_health_snapshot --replace < query1.sql
```

### Query 2: Restriction Impact Analysis

**Purpose**: Understand how many captions each restriction blocks
**Schedule**: Daily
**Alert Threshold**: restriction_filter_rate > 80%

```sql
SELECT
  restriction_id,
  restriction_type,
  target_scope,
  target_value,
  effective_date,
  expiration_date,
  is_active,
  ARRAY_LENGTH(JSON_EXTRACT_ARRAY(restriction_patterns, '$.excluded_caption_ids')) AS captions_blocked_count,
  ARRAY_LENGTH(JSON_EXTRACT_ARRAY(restriction_patterns, '$.excluded_keywords')) AS keywords_count,
  restriction_notes,
  created_at,
  created_by
FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
WHERE is_active = TRUE
  AND effective_date <= CURRENT_DATE()
  AND (expiration_date IS NULL OR expiration_date >= CURRENT_DATE())
ORDER BY captions_blocked_count DESC;
```

### Query 3: Query Performance (Latency & Cost)

**Purpose**: Monitor caption restrictions query performance
**Schedule**: Hourly
**Alert Threshold**: p95_latency > 500ms OR daily_cost > $1.00

```sql
SELECT
  DATE(creation_time) AS query_date,
  TIMESTAMP_TRUNC(creation_time, HOUR) AS query_hour,
  COUNT(*) AS query_count,
  -- Latency metrics
  ROUND(AVG(total_slot_ms) / 1000, 3) AS avg_execution_seconds,
  ROUND(MAX(total_slot_ms) / 1000, 3) AS max_execution_seconds,
  ROUND(APPROX_QUANTILES(total_slot_ms / 1000, 100)[OFFSET(50)], 3) AS p50_execution_seconds,
  ROUND(APPROX_QUANTILES(total_slot_ms / 1000, 100)[OFFSET(95)], 3) AS p95_execution_seconds,
  ROUND(APPROX_QUANTILES(total_slot_ms / 1000, 100)[OFFSET(99)], 3) AS p99_execution_seconds,
  -- Cost metrics
  SUM(total_bytes_processed) / POW(10, 9) AS total_gb_scanned,
  SUM(total_bytes_billed) / POW(10, 12) AS total_tb_billed,
  ROUND(SUM(total_bytes_billed) / POW(10, 12) * 5, 4) AS estimated_cost_usd
FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND REGEXP_CONTAINS(query, r'caption_restrictions')
GROUP BY query_date, query_hour
ORDER BY query_hour DESC;
```

### Query 4: Failed Caption Selections (Fallback Level 5)

**Purpose**: Track when caption-selector reaches ABORT state
**Schedule**: Every hour
**Alert Threshold**: failures > 5 per hour

```sql
-- This query assumes caption-selector logs failures to a `caption_selection_logs` table
-- If not implemented, track via application logs or Cloud Logging

SELECT
  page_name,
  schedule_id,
  failure_reason,
  fallback_level_reached,
  available_captions_before_restrictions,
  available_captions_after_restrictions,
  timestamp
FROM `of-scheduler-proj.eros_scheduling_brain.caption_selection_logs`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND fallback_level_reached = 5  -- ABORT level
ORDER BY timestamp DESC;
```

**Note**: If caption_selection_logs table doesn't exist, create it:
```sql
CREATE TABLE `of-scheduler-proj.eros_scheduling_brain.caption_selection_logs` (
  log_id STRING NOT NULL,
  page_name STRING,
  schedule_id STRING,
  failure_reason STRING,
  fallback_level_reached INT64,
  available_captions_before_restrictions INT64,
  available_captions_after_restrictions INT64,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(timestamp)
CLUSTER BY page_name, fallback_level_reached
OPTIONS(
  partition_expiration_days = 90
);
```

### Query 5: Restriction Change Audit

**Purpose**: Track who changed restrictions and when
**Schedule**: Daily
**Alert Threshold**: changes > 20 per day

```sql
-- Requires audit logging enabled (see CAPTION_RESTRICTIONS_PLAYBOOK.md Section 1.3)

SELECT
  timestamp,
  protoPayload.authenticationInfo.principalEmail AS changed_by,
  protoPayload.methodName AS action,
  resource.labels.table_id AS table_name,
  JSON_EXTRACT_SCALAR(protoPayload.metadata, '$.tableDataChange.reason') AS change_reason
FROM `of-scheduler-proj.eros_scheduling_brain.cloudaudit_googleapis_com_data_access_*`
WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
  AND resource.labels.table_id = 'caption_restrictions'
  AND protoPayload.methodName IN (
    'google.cloud.bigquery.v2.TableService.InsertTableData',
    'google.cloud.bigquery.v2.TableService.UpdateTable'
  )
ORDER BY timestamp DESC;
```

---

## Alert Configuration

### Recommended Alert Channels

#### 1. Slack Integration

**Setup**:
1. Create Slack App: https://api.slack.com/apps
2. Enable Incoming Webhooks
3. Add webhook URL to Grafana/Looker Studio notifications
4. Test with curl:

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert: Caption pool critical!"}' \
  YOUR_WEBHOOK_URL
```

#### 2. PagerDuty Integration (for P0/P1 alerts)

**Setup**:
1. Create Integration in PagerDuty: Services → API Access
2. Copy Integration Key
3. Configure in Grafana:
   - Notification Channels → Add Channel
   - Type: PagerDuty
   - Integration Key: [paste key]
4. Assign to critical alerts only (caption pool < 10)

#### 3. Email Alerts

**Setup (BigQuery Scheduled Query)**:
1. Navigate to BigQuery Console
2. Compose Query 1 (Caption Pool Health)
3. Click **Schedule** → **Create new scheduled query**
4. Schedule: **Every 4 hours**
5. Destination: Email to `engineering@yourcompany.com`
6. Email subject: "Caption Pool Health Report"

### Alert Severity Matrix

| Alert | Condition | Severity | Channels | Auto-Remediation |
|-------|-----------|----------|----------|------------------|
| Caption pool CRITICAL | available_captions < 10 | P1 | PagerDuty + Slack | Disable restrictions |
| Caption pool WARNING | available_captions < 50 | P2 | Slack | Manual review |
| High filter rate | restriction_filter_rate > 80% | P2 | Slack | Review restrictions |
| Slow query performance | p95_latency > 500ms | P3 | Email | Check clustering |
| High cost | daily_cost > $1.00 | P2 | Slack + Email | Review queries |
| Frequent failures | failures > 5/hour | P1 | PagerDuty + Slack | Disable restrictions |

### Auto-Remediation Playbook

**Trigger**: Caption pool CRITICAL alert fires

**Automated Steps** (Cloud Function or GitHub Actions):
1. Verify alert severity (query caption pool again)
2. If still critical, execute emergency disable:
   ```sql
   UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
   SET is_active = FALSE
   WHERE target_scope = 'global'  -- Disable global restrictions first
     AND is_active = TRUE;
   ```
3. Post notification to Slack: "#incident-response"
4. Trigger manual caption-selector run for affected creators
5. Create incident ticket in Jira/Linear
6. Page on-call engineer if pool still critical after 15 minutes

---

## Cost Monitoring

### Daily Cost Report

**Schedule**: Daily at 9am
**Recipients**: `finance@yourcompany.com`, `engineering-leads@yourcompany.com`

```sql
SELECT
  DATE(creation_time) AS cost_date,
  user_email,
  COUNT(DISTINCT job_id) AS query_count,
  SUM(total_bytes_processed) / POW(10, 9) AS total_gb_scanned,
  SUM(total_bytes_billed) / POW(10, 12) AS total_tb_billed,
  ROUND(SUM(total_bytes_billed) / POW(10, 12) * 5, 2) AS estimated_cost_usd,
  ROUND(SUM(total_slot_ms) / 1000 / 60, 2) AS total_compute_minutes
FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY cost_date, user_email
ORDER BY estimated_cost_usd DESC;
```

**Export to Google Sheets**:
1. Create scheduled query (as above)
2. Set destination: `of-scheduler-proj:eros_scheduling_brain.daily_cost_report`
3. Create Looker Studio dashboard connected to this table
4. Share with finance team

### Monthly Cost Projection

**Schedule**: 1st of each month

```sql
WITH daily_costs AS (
  SELECT
    DATE(creation_time) AS cost_date,
    SUM(total_bytes_billed) / POW(10, 12) * 5 AS daily_cost_usd
  FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
  WHERE EXTRACT(MONTH FROM creation_time) = EXTRACT(MONTH FROM CURRENT_TIMESTAMP())
    AND EXTRACT(YEAR FROM creation_time) = EXTRACT(YEAR FROM CURRENT_TIMESTAMP())
    AND job_type = 'QUERY'
    AND state = 'DONE'
  GROUP BY cost_date
)
SELECT
  ROUND(AVG(daily_cost_usd), 2) AS avg_daily_cost,
  ROUND(AVG(daily_cost_usd) * 30, 2) AS projected_monthly_cost,
  ROUND(MAX(daily_cost_usd), 2) AS peak_daily_cost,
  ROUND(MIN(daily_cost_usd), 2) AS min_daily_cost,
  COUNT(*) AS days_elapsed
FROM daily_costs;
```

### Cost Optimization Checks

**Query**: Find expensive queries (potential optimizations)

```sql
SELECT
  job_id,
  user_email,
  creation_time,
  total_bytes_processed / POW(10, 9) AS gb_scanned,
  total_bytes_billed / POW(10, 12) * 5 AS cost_usd,
  total_slot_ms / 1000 AS execution_seconds,
  REGEXP_EXTRACT(query, r'FROM `([^`]+)`') AS table_queried
FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND total_bytes_billed / POW(10, 12) * 5 > 0.10  -- Queries costing > $0.10
ORDER BY cost_usd DESC
LIMIT 20;
```

**Action Items from Results**:
- Missing partition filters? → Add `require_partition_filter = true`
- Full table scans? → Add clustering or materialized views
- Duplicate queries? → Cache results or use scheduled queries

---

## Troubleshooting

### Issue 1: Dashboard Not Refreshing

**Symptom**: Looker Studio dashboard shows stale data

**Diagnosis**:
1. Check data source refresh settings: File → Report Settings → Data Freshness
2. Verify query execution: BigQuery Console → Query History
3. Check IAM permissions: Service account has `bigquery.jobUser` role

**Resolution**:
```bash
# Test query manually
bq query --use_legacy_sql=false '
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
'

# If works, issue is with Looker Studio cache
# Solution: Click "Refresh Data" button in Looker Studio
```

### Issue 2: Grafana "Permission Denied" Error

**Symptom**: Grafana shows "BigQuery: Permission denied" when querying

**Diagnosis**:
```bash
# Verify service account has correct roles
gcloud projects get-iam-policy of-scheduler-proj \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com"
```

**Resolution**:
```bash
# Re-grant roles
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:grafana-bigquery-reader@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

### Issue 3: Queries Timing Out

**Symptom**: Monitoring queries fail with "Query execution timeout"

**Diagnosis**:
```sql
-- Check query complexity
EXPLAIN
SELECT ... -- Your query here
```

**Resolution**:
1. Add partition filters: `WHERE effective_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)`
2. Reduce date range: Query last 7 days instead of 90 days
3. Use materialized views for expensive aggregations
4. Increase query timeout in Grafana: Data Source settings → Query timeout: 120s

### Issue 4: Cost Spike

**Symptom**: Daily BigQuery cost exceeds $1.00 (expected: <$0.10)

**Diagnosis**:
```sql
-- Find expensive queries
SELECT
  user_email,
  job_id,
  creation_time,
  total_bytes_billed / POW(10, 12) * 5 AS cost_usd,
  query
FROM `of-scheduler-proj.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
ORDER BY cost_usd DESC
LIMIT 10;
```

**Common Causes**:
- Missing partition filter (scans entire table history)
- Accidental full table scan (no WHERE clause)
- Runaway scheduled query (executing too frequently)

**Resolution**:
```sql
-- Add require_partition_filter to prevent accidents
ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET OPTIONS (require_partition_filter = true);
```

### Issue 5: Alert Fatigue (Too Many Alerts)

**Symptom**: Receiving 50+ alerts per day, team ignoring them

**Diagnosis**: Review alert thresholds and frequency

**Resolution**:
1. Increase thresholds:
   - Caption pool WARNING: 50 → 30 captions
   - Query latency: 500ms → 1000ms (less sensitive)
2. Add "For" duration in Grafana alerts: Trigger only if condition persists for 15 minutes
3. Group alerts: Send 1 digest per hour instead of individual alerts
4. Use smart alerting: Only alert during business hours for non-critical issues

---

## Appendix: Pre-Built Dashboard Templates

### Looker Studio Template

**Download**: `/monitoring/looker_studio_template.json` (see template structure below)

**Key Metrics**:
- Caption Pool Health (Scorecard with color coding)
- Restriction Filter Rate (Gauge: 0-100%)
- Query Performance (Time series: P50, P95, P99 latency)
- Active Restrictions by Type (Pie chart)
- Cost Trend (Line chart: Daily cost over 30 days)

### Grafana Dashboard JSON

**File**: `/monitoring/grafana_dashboard.json`

**Dashboard Structure**:
- Row 1: Overview (4 panels)
  - Total Active Restrictions (Stat)
  - Caption Pool Status (Gauge)
  - Daily Cost (Graph)
  - Query Count (Stat)
- Row 2: Caption Pool Health (2 panels)
  - Pool Size by Tier (Bar chart)
  - Pool Trend (Time series)
- Row 3: Performance (2 panels)
  - Query Latency (Graph: P50, P95, P99)
  - Bytes Scanned (Graph)
- Row 4: Restrictions (2 panels)
  - Active Restrictions Table
  - Filter Rate by Creator (Heatmap)

**Import Instructions**:
1. Copy `/monitoring/grafana_dashboard.json` to your machine
2. Grafana UI → Dashboards → Import → Upload JSON file
3. Select data source: `BigQuery - eros_scheduling_brain`
4. Click Import

---

## Support & Escalation

**For monitoring issues**:
- Slack: #engineering-monitoring
- Email: sre-team@yourcompany.com
- On-Call: PagerDuty escalation policy

**For BigQuery issues**:
- GCP Support: https://cloud.google.com/support
- BigQuery Docs: https://cloud.google.com/bigquery/docs

---

**Document Version**: 1.0
**Last Updated**: 2025-10-29
**Maintained By**: Cloud Architect Team
