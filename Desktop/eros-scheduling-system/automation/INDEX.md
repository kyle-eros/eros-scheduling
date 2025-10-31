# EROS Automation Package - Quick Index

## Overview

Complete automation configuration for the EROS Scheduling System, including orchestration procedures, scheduled queries, monitoring, and alerting.

**Total Files:** 9
**Status:** Production Ready
**Created:** 2025-10-31

---

## Files

### Core Procedures

| File | Lines | Purpose | Deployment |
|------|-------|---------|------------|
| `run_daily_automation.sql` | 370 | Main orchestrator that analyzes creators, queues schedules, and manages errors | Deploy first |
| `sweep_expired_caption_locks.sql` | 240 | Hourly cleanup of expired caption locks | Deploy second |

**Dependencies:**
- `update_caption_performance` (existing)
- `analyze_creator_performance` (existing)
- Supporting tables (auto-created on first run)

---

### Configuration Files

| File | Lines | Purpose | Usage |
|------|-------|---------|-------|
| `scheduled_queries_config.yaml` | 180 | Defines all BigQuery scheduled query configurations | Reference for deployment |
| `alerts_config.yaml` | 350 | Alert rules, thresholds, and notification channels | Configure monitoring system |

---

### Deployment Scripts

| File | Lines | Purpose | Usage |
|------|-------|---------|-------|
| `deploy_scheduled_queries.sh` | 260 | Automated deployment script for scheduled queries | `./deploy_scheduled_queries.sh` |
| `test_automation.sh` | 410 | Comprehensive test suite for automation components | `./test_automation.sh` |

**Permissions:** Both scripts are executable (`chmod +x`)

---

### Monitoring & Documentation

| File | Lines | Purpose | Usage |
|------|-------|---------|-------|
| `automation_health_check.sql` | 380 | 10 monitoring queries for system health | Run daily or in dashboard |
| `AUTOMATION_SETUP_README.md` | 850 | Complete setup guide with examples | Primary documentation |
| `DEPLOYMENT_CHECKLIST.md` | 480 | Step-by-step deployment checklist | Use during deployment |
| `INDEX.md` | This file | Quick reference index | Start here |

---

## Quick Start

```bash
# 1. Deploy procedures
cd /Users/kylemerriman/Desktop/eros-scheduling-system/automation
bq query --use_legacy_sql=false < run_daily_automation.sql
bq query --use_legacy_sql=false < sweep_expired_caption_locks.sql

# 2. Test everything
./test_automation.sh

# 3. Deploy scheduled queries
./deploy_scheduled_queries.sh

# 4. Monitor first runs
bq query --use_legacy_sql=false < automation_health_check.sql
```

---

## Automation Schedule

| Process | Schedule | Procedure | Purpose |
|---------|----------|-----------|---------|
| Performance Updates | Every 6 hours | `update_caption_performance()` | Learn from message performance |
| Daily Orchestration | Daily @ 3:05 AM LA | `run_daily_automation()` | Analyze creators, generate schedules |
| Lock Cleanup | Every 1 hour | `sweep_expired_caption_locks()` | Prevent table bloat |

---

## Key Features

### run_daily_automation.sql
- Processes all active creators (last 30 days)
- Calls `analyze_creator_performance` per creator
- Checks saturation levels (<80% triggers scheduling)
- Queues schedule generation
- Circuit breaker after 5 failures
- Comprehensive error logging
- Alert generation on failures

### sweep_expired_caption_locks.sql
- Deactivates locks past send date
- Deactivates stale locks (>7 days)
- Monitors for table bloat (>10k locks)
- Logs all cleanup operations
- Alerts on high volume cleanup

### automation_health_check.sql
- 10 comprehensive monitoring queries
- System health scorecard (pass/fail)
- Performance trends (30 days)
- Failure analysis
- Lock table status
- Alert summary

---

## Supporting Tables Created

These tables are auto-created on first procedure run:

1. **etl_job_runs** - Job execution logs
2. **creator_processing_errors** - Per-creator error tracking
3. **schedule_generation_queue** - Schedule generation queue
4. **automation_alerts** - Alert management
5. **lock_sweep_log** - Lock cleanup history

All tables are partitioned by date and clustered for performance.

---

## Critical Monitoring Queries

```sql
-- Check automation health
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation'
ORDER BY job_start_time DESC LIMIT 10;

-- Check for alerts
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.automation_alerts`
WHERE acknowledged = FALSE
ORDER BY alert_time DESC;

-- Check active lock count
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE is_active = TRUE;

-- Check data freshness
SELECT MAX(last_updated),
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) AS hours_stale
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;
```

---

## Alert Thresholds

| Alert | Threshold | Severity | Action Required |
|-------|-----------|----------|-----------------|
| Daily automation failure | Job status = FAILED | CRITICAL | Investigate immediately |
| Automation not run | >28 hours since last | CRITICAL | Check scheduled query |
| Performance updates stale | >12 hours | CRITICAL | Check update procedure |
| Lock table bloat | >10,000 active | CRITICAL | Review cleanup |
| High creator failure rate | >10% failures | WARNING | Review errors |
| Lock cleanup high volume | >100 avg cleanup | WARNING | Monitor trends |

---

## Troubleshooting Quick Reference

### Daily automation fails
```sql
-- 1. Check error
SELECT error_message FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
WHERE job_name = 'daily_automation' AND job_status = 'FAILED'
ORDER BY job_start_time DESC LIMIT 1;

-- 2. Check creator errors
SELECT page_name, error_message, COUNT(*)
FROM `of-scheduler-proj.eros_scheduling_brain.creator_processing_errors`
WHERE error_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY page_name, error_message;

-- 3. Manually retry
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(CURRENT_DATE('America/Los_Angeles'));
```

### Performance updates stale
```sql
-- 1. Check freshness
SELECT MAX(last_updated) FROM `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats`;

-- 2. Manually run
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();

-- 3. Verify scheduled query
-- bq ls --transfer_config --transfer_location=us --project_id=of-scheduler-proj
```

### Lock table bloat
```sql
-- 1. Check count
SELECT COUNT(*) FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE is_active = TRUE;

-- 2. Manually cleanup
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();

-- 3. Check cleanup logs
SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.lock_sweep_log`
ORDER BY sweep_time DESC LIMIT 10;
```

---

## File Dependencies

```
Prerequisites (must exist):
├── caption_bandit_stats (table)
├── mass_messages (table)
├── caption_bank (table)
├── active_caption_assignments (table)
├── update_caption_performance (procedure)
├── analyze_creator_performance (procedure)
└── lock_caption_assignments (procedure)

This Package:
├── run_daily_automation.sql
│   ├── Creates: etl_job_runs
│   ├── Creates: creator_processing_errors
│   ├── Creates: schedule_generation_queue
│   ├── Creates: automation_alerts
│   └── Calls: analyze_creator_performance, sweep_expired_caption_locks
│
├── sweep_expired_caption_locks.sql
│   ├── Creates: lock_sweep_log
│   └── Updates: active_caption_assignments
│
├── deploy_scheduled_queries.sh
│   └── Creates: 3 BigQuery scheduled queries
│
└── test_automation.sh
    └── Tests: All procedures and tables
```

---

## Integration Points

### Schedule Builder (Python)
Poll the `schedule_generation_queue` table for PENDING items:

```python
query = """
SELECT page_name, execution_date
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_generation_queue`
WHERE status = 'PENDING' AND execution_date = CURRENT_DATE('America/Los_Angeles')
"""
```

### Monitoring Dashboard
Use `automation_health_check.sql` queries for dashboard:
- Query 7: System Health Scorecard (overall status)
- Query 1: Daily Automation Status (trend)
- Query 4: Active Lock Table Status (capacity)

### Alert Notifications
Implement notification processor using `automation_alerts` table:
- Poll every 5 minutes for unacknowledged alerts
- Send to appropriate channel based on severity
- Update `acknowledged` flag after processing

---

## Performance Characteristics

| Metric | Typical Value | Alert Threshold |
|--------|---------------|-----------------|
| Daily automation duration | 2-5 minutes | >10 minutes |
| Performance update duration | 30-90 seconds | >5 minutes |
| Lock cleanup duration | 1-5 seconds | >30 seconds |
| Active lock count | 1,000-3,000 | >10,000 |
| Daily automation success rate | >95% | <90% |

---

## Capacity Planning

Current design scales to:
- **Creators:** 100+ active
- **Captions:** 10,000+ per creator
- **Messages:** 1M+ per month
- **Active Locks:** 10,000 max

For larger scale:
1. Increase circuit breaker threshold
2. Implement parallel creator processing
3. Adjust lock cleanup frequency
4. Add creator cohort processing

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-31 | Initial release |

---

## Contact & Support

**Documentation:** See `AUTOMATION_SETUP_README.md` for detailed setup
**Deployment:** See `DEPLOYMENT_CHECKLIST.md` for step-by-step guide
**Testing:** Run `./test_automation.sh` to verify deployment
**Monitoring:** Run `automation_health_check.sql` for system health

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Timezone:** America/Los_Angeles

---

**Ready to deploy? Start with the DEPLOYMENT_CHECKLIST.md!**
