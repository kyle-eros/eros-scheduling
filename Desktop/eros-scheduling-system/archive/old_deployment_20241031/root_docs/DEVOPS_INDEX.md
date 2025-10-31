# EROS Scheduling System - DevOps Index

**Quick navigation to all DevOps deliverables**

---

## Start Here

**New to DevOps setup?** → Read [DEVOPS_QUICKSTART.md](DEVOPS_QUICKSTART.md) (15 minutes to production)

**Want full overview?** → Read [DEVOPS_DELIVERY_SUMMARY.md](DEVOPS_DELIVERY_SUMMARY.md)

**Daily operations?** → Read [OPERATIONAL_RUNBOOK.md](OPERATIONAL_RUNBOOK.md)

---

## Quick Actions

| I want to... | Run this command |
|-------------|------------------|
| Deploy system | `./deployment/deploy_production_complete.sh` |
| Check health | `./deployment/quick_health_check.sh` |
| Setup monitoring | `./deployment/setup_monitoring_alerts.sh` |
| Rollback | `./deployment/rollback.sh` |
| Run tests | `python3 tests/comprehensive_smoke_test.py` |

---

## Deliverable #1: Idempotent Deployment

### Primary Script
- **File:** `/deployment/deploy_production_complete.sh`
- **Lines:** 650+
- **Purpose:** Complete production deployment with automatic rollback
- **Key Features:**
  - Idempotent (safe to re-run)
  - Automatic backup creation
  - State tracking (JSON)
  - Post-deployment validation
  - Rollback on failure

### Usage
```bash
# Standard deployment
./deployment/deploy_production_complete.sh

# Dry run
./deployment/deploy_production_complete.sh --dry-run

# Force re-deployment
./deployment/deploy_production_complete.sh --force
```

### Supporting Scripts
- `/deployment/deploy_idempotent.sh` - Legacy idempotent deployment
- `/deployment/rollback.sh` - Emergency rollback procedures
- `/deployment/backup_tables.sh` - Automated backup creation
- `/deployment/validate_infrastructure.sh` - Post-deployment validation
- `/deployment/validate_procedures.sh` - Procedure validation

---

## Deliverable #2: Logging Configuration

### Primary Script
- **File:** `/deployment/logging_config.sh`
- **Lines:** 436
- **Purpose:** Structured logging with rotation and audit trail
- **Key Features:**
  - JSON structured logs
  - Multiple log types (app, audit, performance)
  - Automatic rotation
  - Performance tracking
  - Audit logging

### Usage
```bash
# Source logging configuration
source ./deployment/logging_config.sh

# Initialize logging
init_logging "my-component"

# Log messages
log_info "Starting operation"
log_error "Operation failed" "error=timeout"

# Performance tracking
perf_timer_start "operation"
# ... do work ...
perf_timer_end "operation" "Operation completed"

# Audit logging
audit_log "DEPLOYMENT" "$(whoami)" "Deployed version 1.0"
```

### Log Locations
- Application: `/var/log/eros/application/`
- Audit: `/var/log/eros/audit/`
- Performance: `/var/log/eros/performance/`
- Deployment: `/var/log/eros/deployment/`

---

## Deliverable #3: Operational Runbook

### Primary Document
- **File:** `/OPERATIONAL_RUNBOOK.md`
- **Lines:** 840
- **Purpose:** Complete operational guide for daily operations, monitoring, and incident response
- **Sections:**
  1. Daily Operations (3 routines)
  2. Monitoring and Alerting
  3. Incident Response (4 severity levels)
  4. Common Issues and Solutions (5 scenarios)
  5. Rollback Procedures
  6. Performance Tuning
  7. Troubleshooting Guide
  8. Maintenance Tasks
  9. Emergency Contacts

### Key Routines

**Morning Health Check (9:00 AM PT, 5 min)**
```bash
cd deployment
bq query --use_legacy_sql=false < monitor_deployment.sql
./quick_health_check.sh
```

**Afternoon Performance Review (2:00 PM PT, 10 min)**
```bash
# Check query performance and costs
bq query --use_legacy_sql=false < monitor_deployment.sql | grep -A 10 "Performance"
```

**Evening Summary (6:00 PM PT, 5 min)**
```bash
# Review schedule generation and exports
bq query --use_legacy_sql=false < monitor_deployment.sql | grep -A 10 "Summary"
```

---

## Deliverable #4: Monitoring & Alerting

### Primary Script
- **File:** `/deployment/setup_monitoring_alerts.sh`
- **Lines:** 550+
- **Purpose:** Configure comprehensive monitoring and alerting
- **Components:**
  - Health check scheduled queries (every 5 min)
  - Cost monitoring queries (hourly)
  - Alert policies (4 policies)
  - Notification channels (email, Slack, Pub/Sub)
  - Automated alerting script

### Setup
```bash
cd deployment

# Configure monitoring
./setup_monitoring_alerts.sh \
  --notification-email "devops@company.com" \
  --slack-webhook "https://hooks.slack.com/..."

# Install cron jobs
crontab -e
# Add lines from /tmp/eros_cron_jobs.txt
```

### Health Check Script
- **File:** `/deployment/quick_health_check.sh`
- **Execution:** ~10 seconds
- **Checks:** 7 comprehensive checks
- **Output:** Standard or JSON

```bash
# Quick check
./deployment/quick_health_check.sh

# Verbose
./deployment/quick_health_check.sh --verbose

# JSON (for automation)
./deployment/quick_health_check.sh --json
```

### Automated Alerting
- **File:** `/deployment/check_and_alert.sh`
- **Frequency:** Every 5 minutes (via cron)
- **Actions:** Sends Slack/email alerts on warnings/critical

---

## Deliverable #5: CI/CD Pipeline

### Primary Configuration
- **File:** `/.github/workflows/ci.yml`
- **Lines:** 300+
- **Jobs:** 8 automated jobs
- **Purpose:** Automated linting, testing, and validation

### Pipeline Jobs

1. **Lint** - Python code quality (Black, flake8, pylint, mypy)
2. **SQL Validation** - SQL linting and syntax checking
3. **Shellcheck** - Shell script validation
4. **Unit Tests** - Pytest with coverage reporting
5. **Dry-Run Analyzer** - Test analyzer with fixture data (PR only)
6. **Smoke Tests** - Comprehensive integration tests
7. **Security Scan** - Bandit, Safety, secret detection
8. **Documentation Check** - Validate all docs exist

### Triggers
- Push to `main` or `develop`
- Pull requests to `main` or `develop`
- Manual workflow dispatch

### Setup
1. Copy `.github/workflows/ci.yml` to your repo
2. Configure GitHub secrets (`GCP_SA_KEY`)
3. Enable GitHub Actions
4. Push to trigger first run

---

## Deliverable #6: Health Check Automation

### Quick Health Check
- **File:** `/deployment/quick_health_check.sh`
- **Execution:** ~10 seconds
- **Checks:** 7 system health checks
- **Exit Codes:** 0 (healthy), 1 (warnings), 2 (critical)

### Checks Performed
1. ✅ System Connectivity (gcloud, BigQuery, dataset)
2. ✅ Table Health (all 5 tables exist)
3. ✅ Query Performance (slow queries, error rate)
4. ✅ Cost Monitoring (daily costs vs thresholds)
5. ✅ Caption Pool (available captions >200)
6. ✅ Caption Locks (expired locks <10)
7. ✅ Recent Activity (assignments in last 24h)

### Health Score
- Base: 100 points
- Warnings: -5 points each
- Critical issues: -20 points each
- Minimum: 0 points

### Integration
```bash
# Manual check
./deployment/quick_health_check.sh

# Automated (via cron, every 5 minutes)
*/5 * * * * /path/to/deployment/check_and_alert.sh
```

---

## Documentation

### Primary Documents

| Document | Lines | Purpose |
|----------|-------|---------|
| [DEVOPS_QUICKSTART.md](DEVOPS_QUICKSTART.md) | 250+ | 15-minute deployment guide |
| [DEVOPS_SUMMARY.md](DEVOPS_SUMMARY.md) | 600+ | Comprehensive DevOps overview |
| [DEVOPS_DELIVERY_SUMMARY.md](DEVOPS_DELIVERY_SUMMARY.md) | 700+ | Complete delivery summary |
| [OPERATIONAL_RUNBOOK.md](OPERATIONAL_RUNBOOK.md) | 840 | Daily operations and incident response |
| [deployment/README.md](deployment/README.md) | 400+ | Deployment automation guide |
| [START_HERE.md](START_HERE.md) | 130 | Repository navigation |

### Quick Reference

**15-minute deployment?** → [DEVOPS_QUICKSTART.md](DEVOPS_QUICKSTART.md)
**Daily operations?** → [OPERATIONAL_RUNBOOK.md](OPERATIONAL_RUNBOOK.md)
**Full overview?** → [DEVOPS_SUMMARY.md](DEVOPS_SUMMARY.md)
**Deployment details?** → [deployment/README.md](deployment/README.md)
**What was delivered?** → [DEVOPS_DELIVERY_SUMMARY.md](DEVOPS_DELIVERY_SUMMARY.md)

---

## Scripts Reference

### Deployment Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy_production_complete.sh` | Full deployment | `./deploy_production_complete.sh` |
| `deploy_idempotent.sh` | Legacy idempotent | `./deploy_idempotent.sh` |
| `rollback.sh` | Emergency rollback | `./rollback.sh [TIMESTAMP]` |
| `backup_tables.sh` | Create backups | `./backup_tables.sh` |
| `validate_infrastructure.sh` | Validate deployment | `./validate_infrastructure.sh` |
| `validate_procedures.sh` | Test procedures | `./validate_procedures.sh` |

### Monitoring Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup_monitoring_alerts.sh` | Setup monitoring | `./setup_monitoring_alerts.sh` |
| `quick_health_check.sh` | Fast health check | `./quick_health_check.sh` |
| `check_and_alert.sh` | Automated alerting | `./check_and_alert.sh` |
| `notify_slack.sh` | Slack notifications | `./notify_slack.sh <webhook> <msg>` |
| `logging_config.sh` | Logging functions | `source ./logging_config.sh` |

### SQL Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `bigquery_infrastructure_setup.sql` | Infrastructure | `bq query < ...` |
| `stored_procedures.sql` | Procedures | `bq query < ...` |
| `monitor_deployment.sql` | Monitoring | `bq query < ...` |
| `verify_infrastructure.sql` | Verification | `bq query < ...` |

---

## Command Cheat Sheet

### Daily Operations

```bash
# Morning health check
./deployment/quick_health_check.sh

# Check costs
bq query --use_legacy_sql=false "
SELECT ROUND(SUM(total_bytes_billed)/POW(10,12)*5,2) as cost_usd
FROM \`region-us\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE DATE(creation_time) = CURRENT_DATE()"

# Full monitoring report
bq query < deployment/monitor_deployment.sql

# Clean expired locks
bq query --use_legacy_sql=false "
DELETE FROM \`of-scheduler-proj.eros_scheduling_brain.caption_locks\`
WHERE expires_at < CURRENT_TIMESTAMP()"
```

### Deployment

```bash
# Full deployment
./deployment/deploy_production_complete.sh

# Dry run
./deployment/deploy_production_complete.sh --dry-run

# Force re-deployment
./deployment/deploy_production_complete.sh --force

# Validate
./deployment/validate_infrastructure.sh
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

# Rollback
./deployment/rollback.sh
```

### Testing

```bash
# Run smoke tests
python3 tests/comprehensive_smoke_test.py

# Test schedule builder
python3 python/test_schedule_builder.py

# Test procedures
bq query < deployment/test_procedures.sql
```

---

## File Locations

### Scripts
- **Deployment:** `/deployment/*.sh` (10 scripts)
- **Python:** `/python/*.py` (5 files)
- **Tests:** `/tests/*.py` (3 files)

### SQL
- **Infrastructure:** `/deployment/*.sql` (10+ files)
- **Procedures:** `/deployment/stored_procedures.sql`
- **Monitoring:** `/deployment/monitor_deployment.sql`

### Documentation
- **Root:** `/*.md` (6 files)
- **Deployment:** `/deployment/*.md` (2 files)
- **Docs:** `/docs/*.md` (10+ files)

### Configuration
- **CI/CD:** `/.github/workflows/ci.yml`
- **Logging:** `/deployment/logging_config.sh`
- **Monitoring:** `/deployment/setup_monitoring_alerts.sh`

---

## Environment Variables

```bash
# Required
export EROS_PROJECT_ID="of-scheduler-proj"
export EROS_DATASET="eros_scheduling_brain"

# Optional
export EROS_NOTIFICATION_EMAIL="devops@company.com"
export EROS_SLACK_WEBHOOK="https://hooks.slack.com/..."
export EROS_LOG_DIR="/var/log/eros"
export LOG_LEVEL="INFO"
```

Add to `~/.zshrc` or `~/.bashrc` for persistence.

---

## Support

### Documentation
- [DEVOPS_QUICKSTART.md](DEVOPS_QUICKSTART.md) - Quick start guide
- [OPERATIONAL_RUNBOOK.md](OPERATIONAL_RUNBOOK.md) - Operations manual
- [DEVOPS_SUMMARY.md](DEVOPS_SUMMARY.md) - Complete overview

### Troubleshooting
- Check logs: `/tmp/eros_deployment_*/`
- Run health check: `./deployment/quick_health_check.sh --verbose`
- Review runbook: [OPERATIONAL_RUNBOOK.md](OPERATIONAL_RUNBOOK.md)

### Contact
- Slack: #eros-incidents
- Email: devops@company.com

---

## Summary Statistics

- **Total Scripts:** 15+
- **Total SQL Files:** 15+
- **Total Documentation:** 3,000+ lines
- **Total Code:** 5,000+ lines
- **CI/CD Jobs:** 8
- **Health Checks:** 7
- **Alert Policies:** 4

---

**Status:** ✅ Complete and Production Ready

**Last Updated:** 2025-10-31
