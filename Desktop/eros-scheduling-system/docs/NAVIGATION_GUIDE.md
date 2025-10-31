# EROS Scheduling System - Navigation Guide

**Quick Start:** Read this guide first to understand the repository structure.

---

## Repository Structure

```
eros-scheduling-system/
├── README.md                          # Start here - Project overview
├── FINAL_DEPLOYMENT_SUMMARY.md        # Complete deployment report
├── COST_ANALYSIS_CORRECTION.md        # Cost analysis ($0-5/month)
│
├── agents/                            # Agent specifications (6 agents)
│   ├── caption-selector.md
│   ├── performance-analyzer.md
│   ├── schedule-builder.md
│   ├── sheets-exporter.md
│   ├── onlyfans-orchestrator.md
│   └── real-time-monitor.md
│
├── deployment/                        # SQL deployment files
│   ├── bigquery_infrastructure_setup.sql
│   ├── select_captions_procedure_FIXED.sql
│   ├── CORRECTED_analyze_creator_performance_FULL.sql
│   ├── schedule_recommendations_messages_view.sql
│   └── [40+ other SQL and documentation files]
│
├── automation/                        # Automation framework
│   ├── run_daily_automation.sql
│   ├── sweep_expired_caption_locks.sql
│   ├── deploy_scheduled_queries.sh
│   ├── test_automation.sh
│   └── [7 other configuration and doc files]
│
├── python/                           # Python implementations
│   ├── schedule_builder.py           # Main schedule builder
│   ├── sheets_export_client.py       # Sheets integration
│   ├── test_schedule_builder.py      # Tests
│   └── requirements.txt              # Dependencies
│
├── tests/                            # Test suites
│   ├── comprehensive_smoke_tests.sql # Main smoke tests
│   ├── test_performance_analyzer_complete.sql
│   └── [12 other test files]
│
├── docs/                             # Documentation
│   ├── NAVIGATION_GUIDE.md          # This file
│   ├── QUICKSTART.md                # 5-minute quick start
│   └── [5 other documentation files]
│
├── sql/                              # SQL reference library
│   └── [TVF and procedure references]
│
└── archive/                          # Historical files
    └── [Old analysis and deprecated files]
```

---

## Where to Find Things

### Getting Started
- **First time?** → `README.md`
- **Ready to deploy?** → `FINAL_DEPLOYMENT_SUMMARY.md`
- **Need quick start?** → `docs/QUICKSTART.md`
- **Understanding costs?** → `COST_ANALYSIS_CORRECTION.md`

### Development
- **Agent specs** → `agents/` directory
- **SQL code** → `deployment/` directory
- **Python code** → `python/` directory
- **Tests** → `tests/` directory

### Deployment
- **Infrastructure SQL** → `deployment/bigquery_infrastructure_setup.sql`
- **Caption Selector** → `deployment/select_captions_procedure_FIXED.sql`
- **Performance Analyzer** → `deployment/CORRECTED_analyze_creator_performance_FULL.sql`
- **Automation** → `automation/` directory
- **Smoke tests** → `tests/comprehensive_smoke_tests.sql`

### Documentation
- **All guides** → `docs/` directory
- **API references** → Individual component README files
- **Troubleshooting** → See component-specific docs

---

## Common Tasks

### Run Smoke Tests
```bash
cd /Users/kylemerriman/Desktop/eros-scheduling-system
bq query --use_legacy_sql=false < tests/comprehensive_smoke_tests.sql
```

### Deploy Infrastructure
```bash
bq query --use_legacy_sql=false < deployment/bigquery_infrastructure_setup.sql
bq query --use_legacy_sql=false < deployment/select_captions_procedure_FIXED.sql
bq query --use_legacy_sql=false < deployment/CORRECTED_analyze_creator_performance_FULL.sql
```

### Generate Schedule
```bash
cd python
python3 schedule_builder.py --page-name jadebri --start-date 2025-11-04
```

### Deploy Automation
```bash
cd automation
./deploy_scheduled_queries.sh
```

---

## File Organization Rules

1. **Root directory** - Key documentation and navigation files only
2. **agents/** - Agent specifications (markdown)
3. **deployment/** - All SQL deployment files and validation reports
4. **automation/** - Automation procedures, configs, and scripts
5. **python/** - All Python implementations
6. **tests/** - All test files (SQL and Python)
7. **docs/** - General documentation
8. **sql/** - Reference SQL (TVFs, procedures)
9. **archive/** - Deprecated/historical files

---

## Quick Reference

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Timezone:** America/Los_Angeles
**Cost:** $0-5/month (within free tier)

**Total Deliverables:**
- 40+ SQL objects
- 3 Python agents
- 1 Apps Script
- 70+ files total
- 150+ pages documentation

---

**Last Updated:** 2025-10-31
**Status:** Production Ready (95%)
