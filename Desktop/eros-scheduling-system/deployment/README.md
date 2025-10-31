# BigQuery Infrastructure - Deployment

This directory contains the BigQuery infrastructure SQL and deployment scripts for the EROS Scheduling System.

## Core Files

### SQL Infrastructure

**PRODUCTION_INFRASTRUCTURE.sql** (1,427 lines)
- Complete BigQuery DDL
- 4 UDFs (caption_key_v2, wilson_score_bounds, etc.)
- 3 Tables (caption_bandit_stats, holiday_calendar, schedule_export_log)
- 4 Stored Procedures (update_caption_performance, run_daily_automation, etc.)
- 1 View (schedule_recommendations_messages)

**verify_production_infrastructure.sql** (504 lines)
- 21 automated validation tests
- Tests all UDFs, tables, procedures, and views
- Expected result: All tests return `PASS ✓`

### Deployment Scripts

**deploy_production_complete.sh**
- Main deployment script (idempotent)
- Creates backups before deployment
- Applies all SQL safely
- Verifies deployment success

**quick_health_check.sh**
- 10-second system health check
- Returns health score (0-100)
- Checks 7 key metrics

### Configuration

**SCHEDULED_QUERIES_SETUP.md**
- How to configure BigQuery scheduled queries
- 3 queries to set up:
  - update_caption_performance (every 6h)
  - run_daily_automation (daily at 03:05 LA)
  - sweep_expired_caption_locks (hourly)

**DEPLOYMENT_SUMMARY.md**
- What was deployed
- Object counts and status
- Post-deployment checklist

## Quick Deployment

```bash
cd deployment

# 1. Deploy infrastructure (idempotent - safe to re-run)
./deploy_production_complete.sh --verbose

# 2. Verify deployment
bq query --project_id=of-scheduler-proj --use_legacy_sql=false \
  < verify_production_infrastructure.sql

# 3. Check health
./quick_health_check.sh
```

Expected: All tests pass, health score > 90/100

## What Gets Deployed

### User-Defined Functions (4)
- `caption_key_v2` - SHA256 caption key generation
- `caption_key` - Backward compatibility wrapper
- `wilson_score_bounds` - 95% confidence intervals
- `wilson_sample` - Thompson sampling

### Tables (3) - All Partitioned & Clustered
- `caption_bandit_stats` - Caption performance (partitioned by DATE(last_updated))
- `holiday_calendar` - US holidays 2025 (20 rows seeded)
- `schedule_export_log` - Export audit log (partitioned by DATE(export_timestamp))

### Stored Procedures (4)
- `update_caption_performance()` - Updates caption metrics (run every 6h)
- `run_daily_automation(DATE)` - Daily automation (run at 03:05 LA)
- `sweep_expired_caption_locks()` - Cleans expired locks (run hourly)
- `select_captions_for_creator(...)` - Caption selection (on-demand)

### View (1)
- `schedule_recommendations_messages` - Exploded schedule view for export

## Project Configuration

- **Project ID:** `of-scheduler-proj`
- **Dataset:** `eros_scheduling_brain`
- **Timezone:** `America/Los_Angeles` (consistent throughout)
- **Region:** US (multi-region)

## Deployment Safety

All deployment operations are:
- ✅ **Idempotent** - Safe to re-run multiple times
- ✅ **CREATE OR REPLACE** - No destructive DDL
- ✅ **Backed up** - Automatic backups before changes
- ✅ **Verified** - Automated tests after deployment
- ✅ **Logged** - All operations logged with timestamps

## Scheduled Queries

After deploying infrastructure, configure 3 scheduled queries:

### 1. Caption Performance Update (Every 6 hours)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
```

### 2. Daily Automation (Daily at 03:05 LA timezone)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  CURRENT_DATE('America/Los_Angeles')
);
```

### 3. Lock Cleanup (Hourly)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
```

See `SCHEDULED_QUERIES_SETUP.md` for detailed configuration instructions.

## Health Monitoring

### Quick Health Check (10 seconds)
```bash
./quick_health_check.sh
```

Returns:
- Overall health score (0-100)
- Status of 7 key metrics
- Any issues detected

### Full Verification (21 tests)
```bash
bq query --project_id=of-scheduler-proj --use_legacy_sql=false \
  < verify_production_infrastructure.sql
```

Expected: All 21 tests show `PASS ✓`

## Cost Estimates

**Monthly operational costs:**
- Infrastructure storage: ~$1.50/month
- Scheduled queries: ~$50-100/month
- **Total: ~$51.50-101.50/month**

**Per-page orchestrator run:** ~$0.33

**Cost protection:**
- Query timeouts configured
- Maximum bytes billed limits
- All operations idempotent (no wasted retries)

## Troubleshooting

### Deployment Issues

**"Table already exists"**
→ This is fine - deployment uses CREATE OR REPLACE

**"Permission denied"**
→ Check BigQuery access to of-scheduler-proj

**"Query timeout"**
→ Increase timeout in job configuration

### Health Check Issues

**Health score < 90**
→ Run `./quick_health_check.sh` to see specific issues

**"UDF not found"**
→ Re-run deployment script

**"Table has no data"**
→ Check if table needs initial seeding

## Additional Scripts

**logging_config.sh**
- Structured JSON logging configuration
- Log rotation settings
- Cloud Logging integration

**setup_monitoring_alerts.sh**
- Creates monitoring alert policies
- Configures notification channels
- Sets up cost alerts

**configure_scheduled_queries.sh**
- Automated scheduled query setup
- Requires manual configuration via Console first

## File Organization

- `*.sql` - SQL DDL and queries
- `*.sh` - Shell scripts (deployment, monitoring)
- `*.md` - Documentation
- `*.yaml` - Configuration files

## Archive Directory

Old deployment files and artifacts have been moved to:
`/archive/old_deployment_20241031/`

This keeps the deployment directory clean and focused on current infrastructure.

## Support

For deployment issues:
1. Check `DEPLOYMENT_SUMMARY.md`
2. Review `SCHEDULED_QUERIES_SETUP.md`
3. Run `./quick_health_check.sh`
4. Consult main `README.md` in root

## Version

- Infrastructure Version: 1.0
- Deployment Type: Idempotent
- Last Updated: October 31, 2024
- Status: Production Ready