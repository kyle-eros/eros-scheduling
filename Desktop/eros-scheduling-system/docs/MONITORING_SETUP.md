# Monitoring Setup for Caption Pool Health

## Overview
This document provides complete instructions for setting up automated monitoring of caption pool health, including BigQuery scheduled queries, alert configuration, and dashboard integration.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     MONITORING PIPELINE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  pool_health.sql                                                │
│  (Daily at 8am UTC)                                             │
│         │                                                       │
│         ├──> BigQuery Scheduled Query                           │
│         │                                                       │
│         └──> monitoring.pool_health_daily                       │
│                      │                                          │
│                      ├──> Pub/Sub Topic (optional)              │
│                      │        │                                 │
│                      │        └──> Cloud Function → PagerDuty   │
│                      │                                          │
│                      ├──> Grafana Dashboard                     │
│                      │                                          │
│                      └──> Looker Studio Report                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## TASK 3: Monitoring Integration

### Step 1: Create Monitoring Dataset and Table

```bash
#!/bin/bash
# Create monitoring dataset and destination table

PROJECT_ID="of-scheduler-proj"
MONITORING_DATASET="monitoring"
TABLE_NAME="pool_health_daily"

# Create monitoring dataset if it doesn't exist
bq mk --dataset \
  --location=US \
  --description="Monitoring and observability data for OnlyFans scheduling system" \
  "${PROJECT_ID}:${MONITORING_DATASET}" 2>/dev/null || echo "Dataset already exists"

# Create destination table for pool health results
bq mk --table \
  --description="Daily caption pool health snapshots per creator" \
  --time_partitioning_field=check_date \
  --clustering_fields=overall_status,page_name \
  "${PROJECT_ID}:${MONITORING_DATASET}.${TABLE_NAME}" \
  page_name:STRING,\
  available_ppv_count:INTEGER,\
  available_bump_count:INTEGER,\
  ppv_pool_status:STRING,\
  bump_pool_status:STRING,\
  overall_status:STRING,\
  restriction_count:INTEGER,\
  hard_rule_count:INTEGER,\
  remediation:STRING,\
  check_date:DATE

echo "Monitoring table created: ${PROJECT_ID}:${MONITORING_DATASET}.${TABLE_NAME}"
```

Save as: `/Users/kylemerriman/Desktop/eros-scheduling-system/scripts/setup_monitoring_table.sh`

Run:
```bash
chmod +x /Users/kylemerriman/Desktop/eros-scheduling-system/scripts/setup_monitoring_table.sh
./scripts/setup_monitoring_table.sh
```

---

### Step 2: Configure Alert Thresholds

Create configurable alert thresholds table:

```sql
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.monitoring.alert_thresholds` (
  metric_name STRING NOT NULL,
  warning_threshold INT64,
  critical_threshold INT64,
  is_active BOOL DEFAULT TRUE,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY DATE(updated_at)
CLUSTER BY metric_name;

INSERT INTO `of-scheduler-proj.monitoring.alert_thresholds`
(metric_name, warning_threshold, critical_threshold, is_active)
VALUES
  ('ppv_pool_size', 200, 50, TRUE),
  ('bump_pool_size', 50, 10, TRUE);
```

---

## Alert Configuration Summary

| Condition | Threshold | Action | Channel | Priority |
|-----------|-----------|--------|---------|----------|
| PPV pool < 50 | CRITICAL | PagerDuty + Slack | #caption-alerts | P1 |
| PPV pool < 200 | WARNING | Slack only | #caption-alerts | P2 |
| Bump pool < 10 | CRITICAL | PagerDuty + Slack | #caption-alerts | P1 |
| Bump pool < 50 | WARNING | Slack only | #caption-alerts | P2 |

---

## Validation

Run these queries to verify monitoring is working:

```sql
-- Check monitoring data freshness
SELECT
  MAX(check_date) as latest_check,
  COUNT(DISTINCT page_name) as creators_monitored,
  COUNTIF(overall_status = 'CRITICAL') as critical_count,
  COUNTIF(overall_status = 'WARNING') as warning_count
FROM `of-scheduler-proj.monitoring.pool_health_daily`
WHERE check_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY);

-- Expected: latest_check = today, creators_monitored > 0
```

---

## Maintenance

### Daily Operations

- Review dashboard at start of day (9am PST)
- Investigate CRITICAL alerts immediately
- Plan caption imports for WARNING alerts

### Weekly Review

- Analyze pool size trends
- Adjust thresholds if too noisy
- Review restriction effectiveness

### Monthly Audit

- Verify scheduled query execution history
- Check alert delivery success rate
- Update documentation with new creators

---

## References

- [BigQuery Scheduled Queries](https://cloud.google.com/bigquery/docs/scheduling-queries)
- [BigQuery Data Transfer Service](https://cloud.google.com/bigquery-transfer/docs/introduction)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Grafana BigQuery Plugin](https://grafana.com/grafana/plugins/grafana-bigquery-datasource/)
