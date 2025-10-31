# EROS Scheduling System - DevOps Quick Start

**Get the system running in production in 15 minutes**

---

## Prerequisites (2 minutes)

### Required Tools

```bash
# Check you have these installed
gcloud --version    # Google Cloud SDK
bq --version        # BigQuery CLI
python3 --version   # Python 3.11+
```

### Install if Missing

```bash
# macOS
brew install --cask google-cloud-sdk
brew install python@3.11

# Ubuntu/Debian
sudo apt-get install google-cloud-sdk python3.11

# Verify installation
which gcloud bq python3
```

---

## Step 1: Authentication (3 minutes)

```bash
# 1. Login to Google Cloud
gcloud auth login

# 2. Set default project
gcloud config set project of-scheduler-proj

# 3. Application default credentials (for scripts)
gcloud auth application-default login

# 4. Verify access
bq ls
# Should show your datasets
```

---

## Step 2: Environment Setup (2 minutes)

```bash
# Navigate to project
cd /Users/kylemerriman/Desktop/eros-scheduling-system

# Set environment variables (add to ~/.zshrc or ~/.bashrc)
export EROS_PROJECT_ID="of-scheduler-proj"
export EROS_DATASET="eros_scheduling_brain"
export EROS_NOTIFICATION_EMAIL="your-email@company.com"  # Optional
export EROS_SLACK_WEBHOOK="https://hooks.slack.com/..."  # Optional

# Source the changes
source ~/.zshrc  # or source ~/.bashrc
```

---

## Step 3: Deploy System (5 minutes)

### Option A: Full Production Deployment (Recommended)

```bash
cd deployment

# Dry run first (see what will be deployed)
./deploy_production_complete.sh --dry-run

# Deploy for real
./deploy_production_complete.sh --verbose

# Expected output:
# ✓ Prerequisites check passed
# ✓ Backup completed
# ✓ Dataset created/exists
# ✓ Infrastructure deployed
# ✓ Procedures deployed
# ✓ Validation passed
# ✓ DEPLOYMENT SUCCESSFUL
```

### Option B: Step-by-Step Deployment

```bash
cd deployment

# 1. Create backup (if existing data)
./backup_tables.sh

# 2. Deploy infrastructure
bq query --use_legacy_sql=false < bigquery_infrastructure_setup.sql

# 3. Deploy procedures
bq query --use_legacy_sql=false < stored_procedures.sql

# 4. Validate
./validate_infrastructure.sh
```

---

## Step 4: Verify Deployment (3 minutes)

```bash
cd deployment

# Run health check
./quick_health_check.sh

# Expected output:
# ✓ Authentication: gcloud authenticated
# ✓ Project Access: Can access project of-scheduler-proj
# ✓ BigQuery Access: Can access BigQuery
# ✓ Dataset: Dataset eros_scheduling_brain exists
# ✓ Tables: All 5 tables exist
# ✓ Query Performance: Performance normal (0 slow queries)
# ✓ Error Rate: 0.00%
# ✓ Daily Cost: $0.00
# ✓ Caption Pool: 1200 captions available
# ✓ Caption Locks: 0 expired locks
# ✓ Recent Activity: 45 assignments in last 24 hours
#
# Health Score: 100/100
# Status: HEALTHY - All systems operational
```

---

## Step 5: Setup Monitoring (2 minutes)

```bash
cd deployment

# Configure monitoring and alerts
./setup_monitoring_alerts.sh \
  --notification-email "your-email@company.com" \
  --slack-webhook "https://hooks.slack.com/..."

# This creates:
# • Health check scheduled queries
# • Cost monitoring queries
# • Alert policies
# • Notification channels
# • Slack integration
# • Automated alerting script
```

### Setup Cron Jobs

```bash
# Edit crontab
crontab -e

# Add these lines (adjust paths)
*/5 * * * * /path/to/deployment/check_and_alert.sh
0 8 * * * cd /path/to/deployment && bq query < monitor_deployment.sql | mail -s "EROS Daily Report" your-email@company.com
0 2 * * 0 source /path/to/deployment/logging_config.sh && rotate_logs
```

---

## Verification Checklist

After completing setup, verify:

- [ ] Can run `bq ls of-scheduler-proj:eros_scheduling_brain`
- [ ] Health check returns score >90
- [ ] All 5 tables exist (caption_bank, caption_bandit_stats, etc.)
- [ ] Procedures exist (run validation script)
- [ ] Monitoring alerts configured
- [ ] Received test Slack notification (if configured)
- [ ] Daily cost report working

---

## Common Issues and Solutions

### Issue: "Permission denied" errors

```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login

# Check IAM permissions
gcloud projects get-iam-policy of-scheduler-proj | grep $(gcloud config get-value account)

# Needed roles:
# • BigQuery Admin
# • BigQuery Data Editor
# • Storage Admin (for backups)
```

### Issue: "Dataset not found"

```bash
# Check project
gcloud config get-value project

# List datasets
bq ls --project_id=of-scheduler-proj

# Create dataset if missing
bq mk --dataset --location=US of-scheduler-proj:eros_scheduling_brain
```

### Issue: Deployment fails with SQL errors

```bash
# Check logs
cat /tmp/eros_deployment_*/deployment.log

# Common fixes:
# 1. Re-run deployment (it's idempotent)
./deploy_production_complete.sh

# 2. If still failing, rollback and retry
./rollback.sh
./deploy_production_complete.sh --force
```

### Issue: High costs

```bash
# Check today's costs
bq query --use_legacy_sql=false "
SELECT ROUND(SUM(total_bytes_billed)/POW(10,12)*5,2) as cost_usd
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time) = CURRENT_DATE()"

# If high, check for runaway queries
bq ls -j -a --max_results=20 --project_id=of-scheduler-proj

# Cancel expensive queries
bq cancel <job_id>
```

---

## Daily Operations

### Morning Routine (5 minutes)

```bash
# 1. Health check
./deployment/quick_health_check.sh

# 2. Review any alerts from overnight
# Check Slack #eros-alerts or email

# 3. Check costs
bq query --use_legacy_sql=false < deployment/monitor_deployment.sql | grep -A 5 "Cost Tracking"
```

### Generate Weekly Schedules (Mondays)

```bash
cd python

# For each active creator
python schedule_builder.py \
  --page-name jadebri \
  --start-date 2025-11-04 \
  --output schedules/jadebri_20251104.csv

# Verify output
ls -lh schedules/
cat schedules/jadebri_20251104.csv | head -10

# Export to Google Sheets (if configured)
python sheets_export_client.py --schedule-id SCH_jadebri_20251104_...
```

### Incident Response

```bash
# Quick diagnosis
./deployment/quick_health_check.sh --verbose

# Check recent errors
bq query --use_legacy_sql=false "
SELECT timestamp, error_result
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND error_result IS NOT NULL
LIMIT 10"

# If critical, rollback
./deployment/rollback.sh
```

---

## Testing Your Setup

### Run Smoke Tests

```bash
cd tests
python3 comprehensive_smoke_test.py

# Expected: 9/10 tests pass
# Any failures are documented and non-critical
```

### Test Schedule Generation

```bash
cd python

# Test with mock data
python3 test_schedule_builder.py

# Should complete without errors
```

### Test Procedures

```bash
cd deployment
bq query --use_legacy_sql=false < test_procedures.sql

# Should return results for all procedures
```

---

## Next Steps

After successful deployment:

1. **Read the Operational Runbook**
   ```bash
   cat OPERATIONAL_RUNBOOK.md
   ```

2. **Review DevOps Summary**
   ```bash
   cat DEVOPS_SUMMARY.md
   ```

3. **Setup CI/CD (if using GitHub)**
   - Copy `.github/workflows/ci.yml` to your repo
   - Configure GitHub secrets
   - Push to trigger first run

4. **Configure Additional Monitoring**
   - Cloud Monitoring dashboards
   - PagerDuty integration
   - Custom alerts

5. **Schedule Regular Maintenance**
   - Weekly: Log rotation, lock cleanup
   - Monthly: Backup testing, performance review
   - Quarterly: DR drill, optimization analysis

---

## Quick Command Reference

```bash
# Health check
./deployment/quick_health_check.sh

# Full deployment
./deployment/deploy_production_complete.sh

# Rollback
./deployment/rollback.sh [TIMESTAMP]

# Monitor system
bq query < deployment/monitor_deployment.sql

# Run tests
python3 tests/comprehensive_smoke_test.py

# Generate schedule
python3 python/schedule_builder.py --page-name <creator>

# Check costs
bq query --use_legacy_sql=false "SELECT ROUND(SUM(total_bytes_billed)/POW(10,12)*5,2) FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT WHERE DATE(creation_time)=CURRENT_DATE()"

# Clean expired locks
bq query --use_legacy_sql=false "DELETE FROM \`of-scheduler-proj.eros_scheduling_brain.caption_locks\` WHERE expires_at<CURRENT_TIMESTAMP()"
```

---

## Support

- **Documentation:** See `OPERATIONAL_RUNBOOK.md` and `DEVOPS_SUMMARY.md`
- **Issues:** Check logs in `/tmp/eros_deployment_*/`
- **Slack:** #eros-incidents
- **Email:** devops@company.com

---

## Success Criteria

Your deployment is successful when:

- ✅ Health check returns 100/100 score
- ✅ All tables and procedures deployed
- ✅ Can generate test schedule
- ✅ Monitoring alerts working
- ✅ Daily costs <$0.20
- ✅ No critical errors in logs

---

**Congratulations! Your EROS Scheduling System is now deployed and operational.**

For detailed operations, see: `OPERATIONAL_RUNBOOK.md`
For troubleshooting, see: `DEVOPS_SUMMARY.md`
For architecture details, see: `README.md`
