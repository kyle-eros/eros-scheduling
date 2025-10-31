# 🚀 EROS Orchestrator Deployment - START HERE

**Project:** of-scheduler-proj  
**Dataset:** eros_scheduling_brain  
**Timezone:** America/Los_Angeles  
**Status:** Production Ready ✅

---

## 📚 Documentation Guide

You have **THREE deployment documents** to work with:

### 1. START_HERE_DEPLOYMENT.md (This File)
**Purpose:** Quick orientation and decision guide  
**Read Time:** 2 minutes  
**Use When:** First time deploying or need quick orientation

### 2. DEPLOYMENT_DAG_QUICKREF.md
**Purpose:** One-page visual reference with all acceptance criteria  
**Read Time:** 5-10 minutes  
**Use When:** 
- During deployment (quick reference)
- Checking phase completion criteria
- Emergency rollback decisions
- Team briefings

**Location:** `/Users/kylemerriman/Desktop/eros-scheduling-system/deployment/DEPLOYMENT_DAG_QUICKREF.md`

### 3. DEPLOYMENT_DAG.md (Comprehensive)
**Purpose:** Complete deployment playbook with detailed instructions  
**Read Time:** 30-45 minutes  
**Use When:**
- First-time deployment (read completely)
- Need detailed commands and scripts
- Troubleshooting issues
- Training new team members

**Location:** `/Users/kylemerriman/Desktop/eros-scheduling-system/deployment/DEPLOYMENT_DAG.md`  
**Size:** 1,654 lines, 51 KB

---

## 🎯 Quick Decision Tree

```
┌─────────────────────────────────────────────────────┐
│ What do you want to do?                             │
└──────────────┬──────────────────────────────────────┘
               │
   ┌───────────┴───────────┬─────────────────┬─────────────┐
   │                       │                 │             │
   ▼                       ▼                 ▼             ▼
Deploy for           Get quick         Understand      Troubleshoot
first time           reference         details         an issue
   │                       │                 │             │
   ▼                       ▼                 ▼             ▼
Read all 3           QUICKREF.md        Full DAG.md    Full DAG.md
documents            (5 min)            (30 min)       (search/scan)
in order
```

---

## 🏃 Quick Start (Already Familiar?)

If you've deployed before and just need a reminder:

```bash
# 1. Set environment
export EROS_PROJECT_ID="of-scheduler-proj"
export EROS_DATASET="eros_scheduling_brain"

# 2. Navigate to deployment
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment

# 3. Verify prerequisites
./verify_deployment_package.sh

# 4. Deploy to production
./deploy_production.sh

# 5. Monitor health
bq query --use_legacy_sql=false < monitor_deployment.sql
```

**IMPORTANT:** Only use quick start if you've read the full DAG at least once!

---

## 📖 First-Time Deployment Reading Order

### Step 1: Read This File (2 min)
You're here! ✅

### Step 2: Read DEPLOYMENT_DAG_QUICKREF.md (5-10 min)
Get visual overview of:
- Timeline and phases
- Acceptance criteria for each phase
- Component inventory
- Critical constraints
- Rollback decision matrix

**Go to:** `deployment/DEPLOYMENT_DAG_QUICKREF.md`

### Step 3: Read DEPLOYMENT_DAG.md (30-45 min)
Understand complete details:
- Phase 0: Preparation (T-24h)
- Phase 1: File Inventory (T+0)
- Phase 2A: BigQuery Hardening (T+15, parallel)
- Phase 2B: Orchestrator Code (T+15, parallel)
- Phase 3: Validation Gate (T+60)
- Phase 4: Idempotent Scripts (T+90)
- Phase 5: Final Deployment (T+120)

**Go to:** `deployment/DEPLOYMENT_DAG.md`

### Step 4: Execute Deployment
Follow Phase-by-Phase instructions in DEPLOYMENT_DAG.md

### Step 5: Reference QUICKREF During Deployment
Keep QUICKREF open as you work through each phase

---

## 🎯 Deployment Overview (60-Second Version)

### Two Parallel Lanes → Validation Gate → Deploy

```
LANE A (BigQuery)        LANE B (Python)
      ↓                        ↓
  Deploy SQL              Test Python
  Deploy UDFs             Validate imports
  Deploy TVFs             Integration tests
  Deploy Procedures       Dependency graph
      ↓                        ↓
      └────────┬───────────────┘
               ↓
      VALIDATION GATE
      (5 Smoke Tests)
      ALL MUST PASS ✓
               ↓
       Generate Scripts
       Create Runbook
               ↓
      Deploy to Production
               ↓
      Monitor 24 Hours
```

**Total Time:** 4-6 hours (including monitoring)  
**Risk Level:** LOW  
**Rollback Available:** YES (instant via `./rollback.sh`)

---

## ✅ What You'll Deploy

### BigQuery (Lane A)
- **2 UDFs:** wilson_score_bounds, wilson_sample
- **7 TVFs:** Account classification, saturation analysis, performance metrics
- **4 Procedures:** Caption selection, performance updates, locking, analysis
- **1 View:** Schedule recommendations with messages
- **3 Scheduled Queries:** Daily updates, lock sweeps, health checks

### Python Orchestrator (Lane B)
- **Schedule Builder:** Main orchestration engine
- **Sheets Exporter:** CSV export functionality
- **Integration Tests:** End-to-end validation
- **Sub-Agents:** 6 specialized agents (selector, analyzer, builder, monitor, exporter, orchestrator)

### Total Components: 17 database objects + 6 Python modules + 6 agent specs = 29 components

---

## 🔥 Emergency Information

### Rollback (< 10 minutes)
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
./rollback.sh
```

### Health Check
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system/deployment
bq query --use_legacy_sql=false < monitor_deployment.sql | grep "Health Score"
```

### When to Rollback
- Health score < 70
- Query costs > $100/day
- Error rate > 10%
- Any data corruption

**See DEPLOYMENT_DAG_QUICKREF.md for complete rollback decision matrix**

---

## 🎓 Key Concepts to Understand

Before deploying, make sure you understand:

1. **Parallel Lanes:** Lane A (SQL) and Lane B (Python) run simultaneously
2. **Validation Gate:** All 5 smoke tests must pass before proceeding
3. **Idempotency:** All scripts can run multiple times safely
4. **No Destructive DDL:** All operations use CREATE OR REPLACE
5. **Timezone:** Everything uses America/Los_Angeles (not UTC!)
6. **Acceptance Criteria:** Each phase has clear pass/fail criteria

---

## 📋 Pre-Deployment Checklist

Before you start, ensure:
- [ ] You've read DEPLOYMENT_DAG.md completely
- [ ] You've reviewed DEPLOYMENT_DAG_QUICKREF.md
- [ ] Environment variables are set
- [ ] Prerequisites are verified (`./verify_deployment_package.sh`)
- [ ] Team is notified
- [ ] Deployment window is scheduled (low-traffic period)
- [ ] You have 4-6 hours available
- [ ] Rollback plan is understood

**If any checkbox is unchecked, DO NOT PROCEED**

---

## 🗺️ Repository Structure Reference

```
/Users/kylemerriman/Desktop/eros-scheduling-system/
│
├── START_HERE_DEPLOYMENT.md        ← You are here
├── README.md                       ← System overview
│
├── deployment/
│   ├── DEPLOYMENT_DAG.md           ← Full deployment playbook (1,654 lines)
│   ├── DEPLOYMENT_DAG_QUICKREF.md  ← Quick reference (one page)
│   ├── deploy_production.sh        ← Main deployment script
│   ├── rollback.sh                 ← Emergency rollback
│   ├── monitor_deployment.sql      ← Health monitoring
│   ├── OPERATIONAL_RUNBOOK.md      ← Daily operations
│   └── [other deployment files]
│
├── sql/
│   ├── procedures/                 ← Stored procedures
│   └── tvfs/                       ← Table-valued functions
│
├── python/
│   ├── schedule_builder.py         ← Main orchestrator
│   ├── sheets_export_client.py     ← Exporter
│   └── [tests]
│
├── agents/
│   ├── onlyfans-orchestrator.md    ← Master orchestrator spec
│   ├── caption-selector.md         ← Selector spec
│   ├── performance-analyzer.md     ← Analyzer spec
│   ├── schedule-builder.md         ← Builder spec
│   ├── real-time-monitor.md        ← Monitor spec
│   └── sheets-exporter.md          ← Exporter spec
│
└── tests/
    └── comprehensive_smoke_tests.sql ← 5 smoke tests
```

---

## 🎯 Your Next Steps

### New to EROS Deployment?
1. **Read:** DEPLOYMENT_DAG_QUICKREF.md (5-10 min)
2. **Read:** DEPLOYMENT_DAG.md (30-45 min)
3. **Verify:** Run `./verify_deployment_package.sh`
4. **Plan:** Schedule deployment window
5. **Deploy:** Follow DEPLOYMENT_DAG.md phase-by-phase

### Already Familiar?
1. **Quick Review:** DEPLOYMENT_DAG_QUICKREF.md
2. **Verify:** Run `./verify_deployment_package.sh`
3. **Deploy:** Run `./deploy_production.sh`
4. **Monitor:** Run `monitor_deployment.sql`

### In Emergency?
1. **Rollback:** Run `./rollback.sh`
2. **Check Health:** Run `monitor_deployment.sql`
3. **Review Logs:** Check `/tmp/eros_*` logs
4. **Escalate:** Contact deployment team

---

## 📞 Support & Escalation

### Documentation Issues?
- Check DEPLOYMENT_DAG.md (comprehensive)
- Check DEPLOYMENT_DAG_QUICKREF.md (quick answers)
- Check OPERATIONAL_RUNBOOK.md (daily operations)

### Technical Issues?
- Review deployment logs in `/tmp/eros_*`
- Run health check: `monitor_deployment.sql`
- Check individual component tests
- Consult rollback decision matrix

### Need Human Help?
1. Deployment Lead (immediate)
2. Engineering Manager (< 30 min)
3. VP Engineering (critical only)

---

## ✨ Success Criteria

You'll know deployment was successful when:
- ✅ All 5 smoke tests pass
- ✅ Health score > 90/100
- ✅ No critical errors in 24 hours
- ✅ Query costs < $10/day
- ✅ Schedules generating correctly
- ✅ Zero data corruption

**Full metrics in DEPLOYMENT_DAG_QUICKREF.md**

---

## 🎓 Document Metadata

| Document | Lines | Size | Read Time | Use Case |
|----------|-------|------|-----------|----------|
| START_HERE_DEPLOYMENT.md | ~300 | 12 KB | 2 min | Orientation |
| DEPLOYMENT_DAG_QUICKREF.md | ~450 | 18 KB | 5-10 min | Quick reference |
| DEPLOYMENT_DAG.md | 1,654 | 51 KB | 30-45 min | Complete guide |

---

## 🚀 Ready to Deploy?

### ✅ Yes, I'm Ready
→ Go to `deployment/DEPLOYMENT_DAG.md` and start with Phase 0

### ⏸️ Not Yet
→ Read `deployment/DEPLOYMENT_DAG_QUICKREF.md` first

### 🆘 I Have Questions
→ Review full `deployment/DEPLOYMENT_DAG.md` or contact deployment team

---

**Created:** 2025-10-31  
**Version:** 1.0  
**Status:** Production Ready ✅  

**Next Step:** Read `deployment/DEPLOYMENT_DAG_QUICKREF.md` →
