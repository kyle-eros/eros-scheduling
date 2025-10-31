# EROS Python Components

This directory contains all Python implementations for the EROS Scheduling System.

---

## Contents

### Schedule Builder
- **schedule_builder.py** - Main schedule generation engine
- **test_schedule_builder.py** - Unit and integration tests
- **SCHEDULE_BUILDER_README.md** - Complete documentation
- **sample_schedule_output.csv** - Example output

### Sheets Exporter
- **sheets_export_client.py** - Python client for Google Sheets integration
- **sheets_exporter.gs** - Google Apps Script (deploy to Sheets)
- **sheets_config.json** - Configuration template
- **test_sheets_exporter.py** - Validation tests
- **sample_execution_log.json** - Example export log

### Dependencies
- **requirements.txt** - Python package dependencies

---

## Quick Start

### Install Dependencies
```bash
cd python
pip install -r requirements.txt
```

### Run Schedule Builder
```bash
python3 schedule_builder.py --page-name jadebri --start-date 2025-11-04 --output schedule.csv
```

### Test Sheets Exporter
```bash
python3 test_sheets_exporter.py
```

---

## Documentation

- **Schedule Builder:** See `SCHEDULE_BUILDER_README.md`
- **Sheets Exporter:** See `../deployment/SHEETS_EXPORTER_README.md`

---

## Requirements

- Python 3.8+
- google-cloud-bigquery
- pandas
- pytz (zoneinfo)

---

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Cost:** $0-5/month (within BigQuery free tier)
