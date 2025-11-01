# 🤖 EROS Scheduling System - Claude Code AI Agent Workflow

**Architecture:** Claude Code AI Multi-Agent System
**Version:** 2.0 (Claude Code Native)
**Status:** ✅ Production Ready
**Last Updated:** October 31, 2025

---

## 🎯 What This Is

The EROS Scheduling System is a **Claude Code AI agent workflow** that uses 5 specialized AI agents to automatically generate optimized OnlyFans content schedules. It's **not a Python application** - it's a prompt-based agent system that runs entirely within Claude Code.

### Key Concept
- **No Python scripts to run** - Everything is AI agent prompts
- **No manual coding** - Just invoke agents via natural language
- **Fully automated** - Agents coordinate with each other
- **BigQuery integration** - Agents execute SQL and analyze results

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   CLAUDE CODE ENVIRONMENT                    │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐ │
│  │      OnlyFans Orchestrator Agent (Master)             │ │
│  │      Coordinates all 4 sub-agents                     │ │
│  └───────────────────────────────────────────────────────┘ │
│           │                                                  │
│           ├──────────┬──────────┬──────────┬──────────┐    │
│           ▼          ▼          ▼          ▼          ▼    │
│  ┌─────────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐ │
│  │Performance  │ │Caption  │ │Schedule │ │   Sheets    │ │
│  │  Analyzer   │ │Selector │ │ Builder │ │  Exporter   │ │
│  │   Agent     │ │  Agent  │ │  Agent  │ │    Agent    │ │
│  └─────────────┘ └─────────┘ └─────────┘ └─────────────┘ │
│         │            │            │              │          │
└─────────┼────────────┼────────────┼──────────────┼──────────┘
          │            │            │              │
          └────────────┴────────────┴──────────────┘
                         ▼
              ┌──────────────────────┐
              │  BigQuery Backend    │
              │  of-scheduler-proj   │
              │ eros_scheduling_brain│
              └──────────────────────┘
```

---

## 🤖 The 5 AI Agents

### 1. **Orchestrator Agent** (Master Controller)
- **File:** `/agents/onlyfans-orchestrator.md`
- **Purpose:** Coordinates the workflow between all sub-agents
- **Capabilities:**
  - Invokes sub-agents in correct sequence
  - Calculates optimal caption counts (based on account size + saturation)
  - Applies validation gates (skips export if schedule invalid or RED)
  - Handles errors with exponential backoff retries
  - Processes multiple pages in parallel

### 2. **Performance Analyzer Agent**
- **File:** `/agents/performance-analyzer.md`
- **Purpose:** Analyzes creator performance and saturation levels
- **Outputs:**
  - Account classification (SMALL, MEDIUM, LARGE, XL)
  - Saturation score and risk level
  - Daily PPV targets
  - Audience size metrics

### 3. **Caption Selector Agent**
- **File:** `/agents/caption-selector.md`
- **Purpose:** Selects optimal captions using Thompson Sampling
- **Algorithm:** Wilson Score + Beta Distribution
- **Outputs:**
  - PPV captions pool
  - Bump captions pool
  - Selection quality metrics

### 4. **Schedule Builder Agent**
- **File:** `/agents/schedule-builder.md`
- **Purpose:** Builds optimized weekly schedules
- **Features:**
  - Respects daily message limits by account size
  - Responds to saturation zones (GREEN/YELLOW/RED)
  - Generates unique schedule_id
  - Validates schedule completeness
  - Persists to BigQuery

### 5. **Sheets Exporter Agent**
- **File:** `/agents/sheets-exporter.md`
- **Purpose:** Exports validated schedules to Google Sheets
- **Mode:** Read-only from BigQuery view
- **Validation:** Only exports if schedule OK and not RED saturation

---

## 🚀 Quick Start - How to Use

### Prerequisites
1. Claude Code CLI installed
2. BigQuery access configured (project: `of-scheduler-proj`)
3. Agent prompt files in `/agents/` directory

### Running Single Page Schedule

Open Claude Code and type:
```
Run the OnlyFans orchestrator for page "jadebri"
for week starting 2025-11-03 in optimize mode with auto-export
```

That's it! Claude will:
1. Read the orchestrator prompt
2. Invoke all 4 sub-agents sequentially
3. Apply validation gates
4. Return comprehensive results

### Running Multiple Pages

```
Generate OnlyFans schedules for pages: jadebri, miarodriguez, gracebennett
Week: 2025-11-03, mode: optimize, auto-export: true, parallel: true
```

### Using the Cheatsheet

For convenience, copy prompts from:
```
QUICK_PROMPTS_CHEATSHEET.txt
```

Contains ready-to-paste prompts for all 38 active pages.

---

## 📊 Workflow Details

### Data Flow

```
Input: page_name, week_start, mode
  ↓
Performance Analyzer → Account metrics + saturation
  ↓
Caption Target Calculation → Optimal caption count
  ↓
Caption Selector → Thompson Sampling selection
  ↓
Schedule Builder → Generate schedule + validate
  ↓
Validation Gate → Check if OK + not RED
  ↓
Sheets Exporter → Export (if validated)
  ↓
Output: Comprehensive JSON results
```

### Caption Target Formula

```
base_count = {
  NEW: 40,
  SMALL: 60,
  MEDIUM: 80,
  LARGE: 100,
  XL: 140
}

saturation_multiplier = {
  LOW: 1.00,
  MODERATE: 0.85,
  HIGH: 0.70,
  CRITICAL: 0.55
}

final_count = MAX(30, base_count * saturation_multiplier)
```

**Example:** LARGE account (100) with MODERATE risk (0.85) = 85 captions

### Validation Gates

Schedule is exported ONLY if:
- ✅ `validation.ok == true`
- ✅ `saturation_zone != "RED"`
- ✅ `auto_export == true`

Otherwise, export is skipped with reason logged.

---

## 📁 Repository Structure

```
eros-scheduling-system/
├── README.md                          # This file - start here
├── START_HERE.md                      # Quick orientation
├── QUICK_PROMPTS_CHEATSHEET.txt       # Ready-to-use prompts (38 pages)
├── TEST_ORCHESTRATOR.md               # Testing guide
│
├── agents/                            # 🤖 CLAUDE CODE AI AGENTS
│   ├── onlyfans-orchestrator.md       # Master orchestrator (443 lines)
│   ├── performance-analyzer.md        # Performance analysis agent
│   ├── caption-selector.md            # Thompson Sampling agent
│   ├── schedule-builder.md            # Schedule generation agent
│   ├── sheets-exporter.md             # Google Sheets export agent
│   └── onlyfans-orchestrator.backup.md # Backup of old version
│
├── deployment/                        # ⚙️ BIGQUERY INFRASTRUCTURE
│   ├── PRODUCTION_INFRASTRUCTURE.sql  # Complete DDL (1,427 lines)
│   ├── verify_production_infrastructure.sql # 21 automated tests
│   ├── DEPLOYMENT_DAG.md              # Deployment plan (1,654 lines)
│   ├── DEPLOYMENT_SUMMARY.md          # What was deployed
│   ├── SCHEDULED_QUERIES_SETUP.md     # How to configure scheduled queries
│   ├── deploy_production_complete.sh  # Idempotent deployment script
│   ├── quick_health_check.sh          # 10-second health check
│   ├── setup_monitoring_alerts.sh     # Monitoring setup
│   └── logging_config.sh              # Structured logging
│
├── tests/                             # 🧪 VALIDATION SUITE
│   ├── comprehensive_smoke_test.py    # Full orchestrator test
│   ├── smoke_test_results.json        # Test results (9/10 passed)
│   ├── SMOKE_TEST_REPORT.md           # Detailed test report
│   └── SMOKE_TEST_DELIVERY.md         # Test delivery summary
│
├── docs/                              # 📚 DOCUMENTATION
│   ├── DEVOPS_SUMMARY.md              # DevOps overview
│   ├── DEVOPS_QUICKSTART.md           # 15-minute deployment guide
│   ├── OPERATIONAL_RUNBOOK.md         # Operations manual (840 lines)
│   └── FINAL_DEPLOYMENT_SUMMARY.md    # Complete deployment report
│
├── automation/                        # 🔄 SCHEDULED QUERIES
│   ├── run_daily_automation.sql       # Daily automation (03:05 LA)
│   ├── sweep_expired_caption_locks.sql # Hourly lock cleanup
│   └── scheduled_queries_config.yaml  # Query configurations
│
└── sql/                              # 📊 SQL COMPONENTS
    ├── tvfs/                         # Table-valued functions
    ├── procedures/                   # Stored procedures
    └── README.md                     # SQL documentation
```

---

## 💾 BigQuery Infrastructure

### Core Components Deployed

**4 User-Defined Functions:**
- `caption_key_v2` - SHA256 caption key generation
- `caption_key` - Backward compatibility wrapper
- `wilson_score_bounds` - 95% confidence intervals
- `wilson_sample` - Thompson sampling

**3 Core Tables:** (Partitioned & Clustered)
- `caption_bandit_stats` - Caption performance tracking
- `holiday_calendar` - US holidays (20 rows for 2025)
- `schedule_export_log` - Audit logging

**4 Stored Procedures:**
- `update_caption_performance()` - Run every 6h
- `run_daily_automation()` - Daily at 03:05 LA
- `sweep_expired_caption_locks()` - Hourly
- `select_captions_for_creator()` - On-demand

**1 View:**
- `schedule_recommendations_messages` - Schedule export view

### Project & Dataset
- **Project:** `of-scheduler-proj`
- **Dataset:** `eros_scheduling_brain`
- **Timezone:** `America/Los_Angeles` (consistent throughout)

---

## 📝 Active Pages (38 Total)

The system manages schedules for 38 creator pages:

**Free Pages (4):**
- gracebennett_free, itskassielee_free, missalexa_free, oliviahansley_free

**Paid Pages (6):**
- gracebennett_paid, itskassielee_paid, missalexa_paid, oliviahansley_paid, taylorwild_paid, tessathomas_paid

**Standard Pages (28):**
- adriannarodriguez, alexlove, anngrayson, ashlyroux, aspynhayes, calilove, carmenrose, chloewildd, corvettemikayla, del, dianagrace, isabellelayla, jadebri, jadevalentine, jadewilkinson, kayleighashford, lolarivers, madisonsummers, miafoster, miaharper, myahill, neenah, norarhodes, poutyselena, scarlettgraceee, talia, tessadove, tessatan

See `QUICK_PROMPTS_CHEATSHEET.txt` for ready-to-use prompts for each page.

---

## ⚙️ Configuration & Settings

### Scheduling Modes

**Optimize (Default):** Maximum revenue, respects all constraints
**Safe:** Conservative approach, wider message gaps
**Conservative:** Minimal messaging, lowest saturation risk

### Auto-Export

**Enabled (Default):** Automatically exports valid schedules to Sheets
**Disabled:** Generate schedule but wait for manual export approval

### Parallel Processing

**Enabled (Default):** Process multiple pages concurrently
**Disabled:** Sequential processing (for debugging)

---

## 🔍 Monitoring & Validation

### Health Check (10 seconds)
```bash
cd deployment
./quick_health_check.sh
```

Returns health score (0-100) and status of 7 key metrics.

### Verify Infrastructure (21 tests)
```sql
bq query --project_id=of-scheduler-proj --use_legacy_sql=false \
  < deployment/verify_production_infrastructure.sql
```

Expected: All 21 tests return `PASS ✓`

### View Recent Schedules
```sql
SELECT
  schedule_id,
  page_name,
  created_at,
  total_messages,
  saturation_zone
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
ORDER BY created_at DESC
LIMIT 10;
```

---

## 💰 Cost Analysis

### Per-Page Cost: ~$0.33
| Component | Data Scanned | Cost |
|-----------|--------------|------|
| Performance Analyzer | ~29 GB | $0.145 |
| Caption Selector | ~4.6 GB | $0.023 |
| Schedule Builder | ~0.2 GB | $0.001 |
| Sheets Exporter | ~11 GB | $0.055 |
| Overhead | ~2 GB | $0.010 |
| **TOTAL** | **~47 GB** | **~$0.33** |

### Monthly Cost Scenarios
- **38 pages, weekly:** ~$500/month
- **38 pages, 2x weekly:** ~$1,000/month
- **All pages, daily:** ~$4,560/month (not recommended)

### Cost Protection
- Query timeouts configured (outside SQL)
- Maximum bytes billed limits
- All operations idempotent (safe to re-run)

---

## 🚨 Troubleshooting

### Common Issues

**"Agent file not found"**
→ Ensure all .md files exist in `/agents/` directory

**"No captions available"**
→ Check `caption_bank` table has data for the page
```sql
SELECT COUNT(*) as caption_count
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
WHERE page_name = 'jadebri';
```

**"Export skipped"**
→ Check validation gate conditions:
- Was `validation.ok == false`?
- Was `saturation_zone == "RED"`?
- Was `auto_export == false`?

**"BigQuery timeout"**
→ Check query performance:
```bash
cd deployment
./quick_health_check.sh
```

### Debug Single Agent

Test individual agents:
```
# Test performance analyzer only
Run the performance analyzer agent for page "jadebri"
with 90 day lookback and include saturation analysis

# Test caption selector only (requires caption count)
Run the caption selector agent for page "jadebri"
with 85 captions needed
```

---

## 📊 Expected Results

### Successful Run Output

```json
{
  "orchestration_summary": {
    "status": "completed",
    "total_pages": 1,
    "successful": 1,
    "exported": 1,
    "execution_time_seconds": 8.2,
    "saturation_breakdown": {
      "GREEN": 0,
      "YELLOW": 1,
      "RED": 0
    }
  },
  "page_results": {
    "jadebri": {
      "status": "success",
      "performance": {
        "account_classification": {
          "size_tier": "LARGE"
        },
        "saturation_analysis": {
          "risk_level": "MODERATE"
        }
      },
      "caption_selection": {
        "target_count": 85,
        "selected_count": 85
      },
      "schedule": {
        "schedule_id": "SCH_2025W45_JADEBRI_ABC123",
        "total_messages": 42,
        "saturation_zone": "YELLOW"
      },
      "export": {
        "status": "exported",
        "schedule_id": "SCH_2025W45_JADEBRI_ABC123"
      }
    }
  }
}
```

---

## 🎯 Success Criteria

After running orchestrator, verify:
- ✅ Performance data includes `size_tier` and `risk_level`
- ✅ Caption count matches formula (base × multiplier)
- ✅ Schedule has valid `schedule_id`
- ✅ Messages respect daily limits by account size
- ✅ Export only happens if validation OK and not RED
- ✅ All timestamps in LA timezone
- ✅ Execution completes in <30 seconds per page

---

## 📚 Essential Documentation

**For Users:**
1. This README - System overview
2. `QUICK_PROMPTS_CHEATSHEET.txt` - Copy-paste prompts
3. `TEST_ORCHESTRATOR.md` - Testing guide

**For Operators:**
1. `OPERATIONAL_RUNBOOK.md` - Daily operations (840 lines)
2. `deployment/DEPLOYMENT_SUMMARY.md` - What's deployed
3. `deployment/SCHEDULED_QUERIES_SETUP.md` - Configure automation

**For Developers:**
1. `agents/onlyfans-orchestrator.md` - Orchestrator spec (443 lines)
2. `deployment/PRODUCTION_INFRASTRUCTURE.sql` - Full DDL (1,427 lines)
3. `DEVOPS_SUMMARY.md` - DevOps guide

---

## 🔄 Scheduled Automation

### Configured Scheduled Queries

**Caption Performance Update** (Every 6 hours)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.update_caption_performance`();
```

**Daily Automation** (Daily at 03:05 LA)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.run_daily_automation`(
  CURRENT_DATE('America/Los_Angeles')
);
```

**Lock Cleanup** (Hourly)
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.sweep_expired_caption_locks`();
```

See `deployment/SCHEDULED_QUERIES_SETUP.md` for configuration instructions.

---

## 🎓 How It Works Internally

### When You Invoke the Orchestrator

1. **Claude reads orchestrator prompt** from `/agents/onlyfans-orchestrator.md`
2. **Executes workflow** per the instructions in the prompt
3. **Calls sub-agents** by reading their .md files and following their logic
4. **Executes SQL** against BigQuery as specified in each agent
5. **Passes data** between agents using the defined JSON structures
6. **Applies validation** gates before proceeding
7. **Returns results** in comprehensive JSON format

### This Is NOT:
- ❌ A Python application to install
- ❌ Scripts to execute with `python script.py`
- ❌ Code that needs to be "run"

### This IS:
- ✅ AI agent prompts that Claude interprets
- ✅ Natural language workflow orchestration
- ✅ Prompt-based BigQuery interactions
- ✅ Fully within Claude Code environment

---

## 🏁 Next Steps

### First Time Users
1. Read this README completely
2. Open `QUICK_PROMPTS_CHEATSHEET.txt`
3. Copy a prompt for a test page
4. Paste into Claude Code
5. Observe the orchestrator in action

### Regular Operations
1. Copy prompt from cheatsheet
2. Adjust week_start date (must be Monday)
3. Paste into Claude Code
4. Review results
5. Check Google Sheets for exported schedule

### Weekly Workflow
```
Monday morning:
→ Copy "Run ALL pages" prompt
→ Update date to current Monday
→ Paste into Claude Code
→ Monitor for ~5-10 minutes
→ Review exported schedules in Google Sheets
```

---

## 📞 Support & Documentation

### Quick References
- `QUICK_PROMPTS_CHEATSHEET.txt` - All prompts ready to copy
- `TEST_ORCHESTRATOR.md` - How to test the system
- `SMOKE_TEST_REPORT.md` - Validation test results

### Operations Guides
- `OPERATIONAL_RUNBOOK.md` - Daily operations manual
- `DEVOPS_QUICKSTART.md` - 15-minute deployment guide
- `deployment/DEPLOYMENT_SUMMARY.md` - What's deployed

### Technical Documentation
- `agents/onlyfans-orchestrator.md` - Orchestrator specification
- `deployment/PRODUCTION_INFRASTRUCTURE.sql` - Complete DDL
- `FINAL_DEPLOYMENT_SUMMARY.md` - Deployment report

---

## ✅ System Status

**Architecture:** Claude Code AI Multi-Agent System
**Orchestrator:** Version 2.0 (Native Claude Code Agent)
**BigQuery:** Fully deployed and validated
**Test Results:** 9/10 smoke tests passed (90%)
**Status:** ✅ PRODUCTION READY
**Confidence:** HIGH

**Ready to generate schedules!** 🚀

---

**Version:** 2.0
**Last Updated:** October 31, 2025
**Type:** Claude Code AI Agent Workflow
**License:** Proprietary