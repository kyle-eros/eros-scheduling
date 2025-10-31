# EROS Deployment DAG - Quick Reference

**Project:** of-scheduler-proj | **Dataset:** eros_scheduling_brain | **Timezone:** America/Los_Angeles

---

## 🎯 One-Page Deployment Overview

### Total Time: 4-6 hours | Risk: LOW | Confidence: HIGH

```
TIMELINE
════════════════════════════════════════════════════════════════════════════

T-24h ┃ PHASE 0: PREPARATION (2-4h)
      ┃ ✓ Environment setup
      ┃ ✓ Prerequisites check
      ┃ ✓ Team notification
      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+0   ┃ PHASE 1: FILE INVENTORY (15 min)
      ┃ ✓ SQL files readable
      ┃ ✓ Python modules importable
      ┃ ✓ Shell scripts executable
      ┃ ✓ Manifest created
      ┗━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                      ┃
      ┏━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━┓
      ┃                               ┃
T+15  ┃ LANE A: BQ HARDENING (45m)    ┃ LANE B: ORCHESTRATOR (45m)
      ┃ ✓ Deploy UDFs (2)             ┃ ✓ Validate imports
      ┃ ✓ Deploy TVFs (7)             ┃ ✓ Test sub-agents
      ┃ ✓ Deploy procedures (4)       ┃ ✓ Compile orchestrator
      ┃ ✓ Create views (1)            ┃ ✓ Verify dependencies
      ┃ ✓ Setup scheduled queries (3) ┃ ✓ Integration tests
      ┗━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━┛
                      ┃
T+60  ┃ PHASE 3: VALIDATION GATE (30 min) - ALL TESTS MUST PASS
      ┃ ✓ Test #1: Analyzer (performance metrics valid)
      ┃ ✓ Test #2: Selector (caption selection < 2s)
      ┃ ✓ Test #3: Builder (schedule generation complete)
      ┃ ✓ Test #4: Exporter (CSV formatted correctly)
      ┃ ✓ Test #5: Timezone (all timestamps in LA timezone)
      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+90  ┃ PHASE 4: IDEMPOTENT SCRIPTS (30 min)
      ┃ ✓ Generate deployment script
      ┃ ✓ Create rollback procedures
      ┃ ✓ Document runbook
      ┃ ✓ Setup monitoring alerts
      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

T+120 ┃ PHASE 5: FINAL DEPLOYMENT (2-4h)
      ┃ ✓ Execute production deployment
      ┃ ✓ Monitor system health (24 hours)
      ┃ ✓ Generate deployment summary
      ┃ ✓ Stakeholder communication
      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 📋 Phase Acceptance Criteria

### Phase 1: File Inventory ✓
- [ ] All SQL files readable (absolute paths)
- [ ] All Python modules importable
- [ ] All shell scripts executable
- [ ] File manifest created

**Files:**
```
✓ 6 SQL files (procedures, infrastructure, TVFs)
✓ 4 Python files (builder, exporter, tests)
✓ 7 Shell scripts (deploy, rollback, validate)
✓ 6 Agent specs (orchestrator, selector, analyzer, builder, monitor, exporter)
```

### Phase 2A: BigQuery Hardening ✓
- [ ] 2 UDFs exist (wilson_score_bounds, wilson_sample)
- [ ] 7 TVFs exist (classify, analyze, calculate functions)
- [ ] 4 Procedures exist (update, select, lock, analyze)
- [ ] 3 Scheduled queries created (daily, sweep, health)
- [ ] No session settings in SQL (SAFE_DIVIDE used)

**Validation:**
```sql
-- Check object count
SELECT routine_type, COUNT(*) 
FROM INFORMATION_SCHEMA.ROUTINES 
GROUP BY routine_type;

-- Expected: FUNCTION=2, TABLE_FUNCTION=7, PROCEDURE=4
```

### Phase 2B: Orchestrator Code ✓
- [ ] schedule_builder imports correctly
- [ ] sheets_export_client imports correctly
- [ ] Sub-agents compile successfully
- [ ] Dependency graph validated (no cycles)
- [ ] Integration tests pass

**Test Command:**
```bash
cd python && python3 test_schedule_builder.py && python3 test_sheets_exporter.py
```

### Phase 3: 5 Smoke Tests ✓ (VALIDATION GATE)
- [ ] Test #1: Analyzer returns valid JSON with all fields
- [ ] Test #2: Selector returns captions in < 2 seconds
- [ ] Test #3: Builder generates complete schedule
- [ ] Test #4: Exporter creates correctly formatted CSV
- [ ] Test #5: Timezone validates as America/Los_Angeles

**Run All Tests:**
```bash
bq query --use_legacy_sql=false < tests/comprehensive_smoke_tests.sql
```

### Phase 4: Idempotent Scripts ✓
- [ ] deploy_production.sh created and executable
- [ ] rollback.sh verified and tested
- [ ] OPERATIONAL_RUNBOOK.md created
- [ ] Monitoring alerts configured

**Verify:**
```bash
ls -lh deployment/deploy_production.sh deployment/rollback.sh
cat deployment/OPERATIONAL_RUNBOOK.md | head -50
```

### Phase 5: Final Deployment ✓
- [ ] All database objects deployed
- [ ] All smoke tests passing
- [ ] System health score > 90/100
- [ ] No critical errors in 24h
- [ ] Deployment summary generated
- [ ] Stakeholders notified

**Health Check:**
```bash
bq query --use_legacy_sql=false < deployment/monitor_deployment.sql | grep "Health Score"
```

---

## 🚀 Quick Start Commands

### Prerequisites (Phase 0)
```bash
export EROS_PROJECT_ID="of-scheduler-proj"
export EROS_DATASET="eros_scheduling_brain"
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./verify_deployment_package.sh
```

### Execute Deployment (Phase 5)
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./deploy_production.sh
```

### Monitor Health
```bash
bq query --use_legacy_sql=false < deployment/monitor_deployment.sql
```

### Emergency Rollback
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./rollback.sh
```

---

## 📊 Component Inventory

### BigQuery Objects (Lane A)
| Type | Count | Names |
|------|-------|-------|
| UDFs | 2 | wilson_score_bounds, wilson_sample |
| TVFs | 7 | classify_account_size, analyze_saturation_status, calculate_performance_metrics, get_recent_performance_window, detect_anomalies, calculate_engagement_rates, get_creator_baseline |
| Procedures | 4 | update_caption_performance, select_captions_for_creator, lock_caption_assignments, analyze_creator_performance |
| Views | 1 | schedule_recommendations_with_messages |
| Scheduled Queries | 3 | daily_caption_update, expired_lock_sweep, health_check |

### Python Modules (Lane B)
| Module | Purpose | Dependencies |
|--------|---------|--------------|
| schedule_builder.py | Generate weekly schedules | BigQuery, pandas |
| sheets_export_client.py | Export to Google Sheets | BigQuery, gspread |
| test_schedule_builder.py | Unit tests | pytest |
| test_sheets_exporter.py | Export tests | pytest |

### Agent Specifications
| Agent | Role | Status |
|-------|------|--------|
| onlyfans-orchestrator | Master coordinator | Production |
| caption-selector | Thompson sampling | Production |
| performance-analyzer | Metrics & saturation | Production |
| schedule-builder | Volume & timing | Production |
| real-time-monitor | Health checks | Production |
| sheets-exporter | CSV export | Production |

---

## ⚠️ Critical Constraints

### NO DESTRUCTIVE DDL
- ✅ All DDL uses CREATE OR REPLACE
- ❌ No DROP statements
- ❌ No DELETE without WHERE
- ❌ No UPDATE without WHERE
- ✅ Backups before all changes

### NO SESSION SETTINGS
- ❌ No SET statements in SQL
- ✅ Use SAFE_DIVIDE instead
- ✅ Compatible with scheduled queries
- ✅ Settings in procedure body only

### TIMEZONE CONSISTENCY
- ✅ All times: America/Los_Angeles
- ✅ Python: ZoneInfo
- ✅ BigQuery: AT TIME ZONE
- ❌ No UTC/PST confusion

### IDEMPOTENCY
- ✅ Scripts run multiple times safely
- ✅ No cumulative effects
- ✅ Deterministic results
- ✅ Safe retries

---

## 🎯 Success Metrics

### Deployment Success (Immediate)
- Health score > 90/100
- All tests passing
- Zero critical errors
- Cost < $10/day

### Operational Success (Week 1)
- Query performance < 30s
- Zero duplicate assignments
- Zero data corruption
- Monitoring alerts working

### Business Success (Week 4)
- EMV improvement > 10%
- Revenue increase measurable
- Cost stable ($5-10/day)
- Team satisfaction high

---

## 🔥 Rollback Decision Matrix

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Health Score | < 70 | ROLLBACK |
| Query Costs | > $100/day | ROLLBACK |
| Error Rate | > 10% | ROLLBACK |
| Data Corruption | Any | ROLLBACK |
| Performance Regression | > 50% slower | INVESTIGATE |

**Rollback Command:**
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./rollback.sh
```

---

## 📞 Emergency Contacts

### Deployment Team
- **Lead:** [NAME]
- **Slack:** #eros-deployment
- **Email:** team@example.com

### Escalation Path
1. Deployment Lead (immediate)
2. Engineering Manager (< 30 min)
3. VP Engineering (critical only)

---

## 📁 Key File Paths

All paths are absolute from repository root:
```
/Users/kylemerriman/Desktop/eros-scheduling-system/

deployment/
  ├── DEPLOYMENT_DAG.md              ← Full detailed DAG
  ├── DEPLOYMENT_DAG_QUICKREF.md     ← This document
  ├── deploy_production.sh           ← Main deployment script
  ├── rollback.sh                    ← Emergency rollback
  ├── monitor_deployment.sql         ← Health monitoring
  └── OPERATIONAL_RUNBOOK.md         ← Daily operations

sql/
  ├── procedures/select_captions_for_creator_FIXED.sql
  └── tvfs/deploy_tvf_agent2.sql, deploy_tvf_agent3.sql

python/
  ├── schedule_builder.py            ← Main orchestrator
  └── sheets_export_client.py        ← Exporter

agents/
  ├── onlyfans-orchestrator.md       ← Master spec
  ├── caption-selector.md
  ├── performance-analyzer.md
  ├── schedule-builder.md
  ├── real-time-monitor.md
  └── sheets-exporter.md

tests/
  └── comprehensive_smoke_tests.sql  ← All 5 smoke tests
```

---

## ✅ Pre-Flight Checklist

Before starting deployment:
- [ ] Read DEPLOYMENT_DAG.md completely
- [ ] Environment variables set
- [ ] Prerequisites verified
- [ ] Team notified
- [ ] Backup plan confirmed
- [ ] Monitoring ready
- [ ] Rollback tested
- [ ] Stakeholders informed

---

**Status:** Production Ready  
**Version:** 1.0  
**Created:** 2025-10-31  
**Last Updated:** 2025-10-31

For full details, see: **DEPLOYMENT_DAG.md** (1,654 lines, 51 KB)
