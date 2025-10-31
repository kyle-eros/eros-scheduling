# EROS Schedule Builder - Complete Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Account Size Framework](#account-size-framework)
6. [Saturation Response System](#saturation-response-system)
7. [API Reference](#api-reference)
8. [CSV Output Format](#csv-output-format)
9. [BigQuery Integration](#bigquery-integration)
10. [Error Handling](#error-handling)
11. [Testing](#testing)
12. [Monitoring](#monitoring)
13. [Troubleshooting](#troubleshooting)

---

## Overview

The EROS Schedule Builder is a production-ready Python application that generates optimized weekly schedules for OnlyFans creators. It intelligently manages message volume based on account size and audience saturation, ensuring maximum revenue while maintaining subscriber engagement.

### Key Features

- **Account-Size-Based Volume Controls**: Automatically adjusts message frequency based on creator tier (MICRO to MEGA)
- **Saturation Detection**: RED/YELLOW/GREEN zone system prevents audience burnout
- **BigQuery Integration**: Leverages stored procedures for caption selection and performance analysis
- **Atomic Operations**: Prevents duplicate caption assignments through conflict detection
- **CSV Export**: Generates scheduler-ready output with comprehensive metadata
- **Audit Logging**: Tracks all schedule generation with execution metrics

### What It Does

1. Analyzes creator performance and saturation levels
2. Calculates optimal PPV and Bump message volumes
3. Selects high-performing captions using Thompson Sampling
4. Builds time-optimized weekly schedules with proper gaps
5. Persists schedules to BigQuery with JSON structure
6. Locks caption assignments to prevent conflicts
7. Exports human-readable CSV for review and deployment

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                  Schedule Builder Agent                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Analyze Creator Performance                              │
│     ├─→ analyze_creator_performance() procedure              │
│     ├─→ Account size classification (MICRO-MEGA)             │
│     ├─→ Behavioral segment (BUDGET-LUXURY)                   │
│     └─→ Saturation score (0.0-1.0)                           │
│                                                               │
│  2. Calculate Volume Targets                                 │
│     ├─→ Apply account size parameters                        │
│     ├─→ Apply saturation adjustments (GREEN/YELLOW/RED)      │
│     └─→ Determine PPV and Bump counts                        │
│                                                               │
│  3. Select Captions                                          │
│     ├─→ select_captions_for_creator() procedure              │
│     ├─→ Thompson Sampling with Wilson Score                  │
│     ├─→ Pattern diversity enforcement                        │
│     └─→ Budget penalty for overused categories               │
│                                                               │
│  4. Build Time Slots                                         │
│     ├─→ Distribute across peak hours                         │
│     ├─→ Enforce minimum gaps                                 │
│     ├─→ Add cooling days if RED zone                         │
│     └─→ Variety enforcement (no repetition)                  │
│                                                               │
│  5. Persist to BigQuery                                      │
│     ├─→ schedule_recommendations table (JSON)                │
│     ├─→ lock_caption_assignments() procedure                 │
│     ├─→ active_caption_assignments table                     │
│     └─→ schedule_export_log table                            │
│                                                               │
│  6. Export CSV                                               │
│     ├─→ Pandas DataFrame generation                          │
│     ├─→ 11-column format                                     │
│     └─→ Scheduler-ready output                               │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Input: page_name, start_date
    ↓
[BigQuery: analyze_creator_performance]
    ↓
Account Size: MICRO/SMALL/MEDIUM/LARGE/MEGA
Saturation: GREEN/YELLOW/RED (score 0.0-1.0)
    ↓
[Volume Calculator]
    ↓
PPV Count: 5-25/week (adjusted by saturation)
Bump Count: 3-18/week (increased if saturated)
    ↓
[BigQuery: select_captions_for_creator]
    ↓
Selected Captions: Budget/Mid/Premium + Bumps
    ↓
[Time Slot Builder]
    ↓
Schedule: 7 days × 2-25 messages/day
    ↓
[BigQuery: Persist & Lock]
    ↓
schedule_recommendations (JSON)
active_caption_assignments (rows)
    ↓
[CSV Export]
    ↓
Output: {schedule_id}.csv
```

---

## Installation

### Prerequisites

- Python 3.9 or higher
- Google Cloud SDK (for authentication)
- Access to `of-scheduler-proj.eros_scheduling_brain` dataset
- BigQuery stored procedures deployed

### Step 1: Install Dependencies

```bash
# Using pip
pip install google-cloud-bigquery pandas

# Or using requirements.txt
pip install -r requirements.txt
```

### Step 2: Authentication

```bash
# Set up Google Cloud authentication
gcloud auth application-default login

# Or use a service account
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

### Step 3: Verify Installation

```bash
# Test import
python -c "from schedule_builder import ScheduleBuilder; print('✓ Installation successful')"

# Run tests (no BigQuery connection required)
python test_schedule_builder.py
```

---

## Quick Start

### Command Line Usage

```bash
# Basic usage
python schedule_builder.py \
    --page-name jadebri \
    --start-date 2025-11-04 \
    --output jadebri_schedule.csv

# Full options
python schedule_builder.py \
    --page-name jadebri \
    --start-date 2025-11-04 \
    --project-id of-scheduler-proj \
    --dataset eros_scheduling_brain \
    --output ./schedules/jadebri_2025_11_04.csv
```

### Python API

```python
from schedule_builder import ScheduleBuilder
from datetime import datetime

# Initialize
builder = ScheduleBuilder(
    project_id="of-scheduler-proj",
    dataset="eros_scheduling_brain"
)

# Generate schedule
schedule_id, df = builder.build_schedule(
    page_name="jadebri",
    start_date="2025-11-04"
)

# Export
builder.export_csv(df, f"{schedule_id}.csv")

# Print summary
print(f"Schedule ID: {schedule_id}")
print(f"Total Messages: {len(df)}")
print(f"PPVs: {len(df[df['message_type'] == 'PPV'])}")
print(f"Bumps: {len(df[df['message_type'] == 'Bump'])}")

# Inspect schedule
print("\nFirst day breakdown:")
monday = df[df['day_of_week'] == 'Monday']
for _, row in monday.iterrows():
    print(f"{row['scheduled_send_time']} - {row['message_type']}: {row['caption_text'][:50]}")
```

### Expected Output

```
2025-10-31 13:30:15,123 - schedule_builder - INFO - Initialized ScheduleBuilder for of-scheduler-proj.eros_scheduling_brain
2025-10-31 13:30:15,456 - schedule_builder - INFO - Analyzing creator performance for jadebri
2025-10-31 13:30:18,789 - schedule_builder - INFO - Creator analysis complete: MEDIUM tier
2025-10-31 13:30:18,790 - schedule_builder - INFO - Volume targets: 9 PPVs, 9 Bumps (zone=YELLOW, base=12/8, multiplier=0.75)
2025-10-31 13:30:18,791 - schedule_builder - INFO - Selecting captions for jadebri: budget=2, mid=4, premium=3, bump=9
2025-10-31 13:30:21,234 - schedule_builder - INFO - Selected 18 captions
2025-10-31 13:30:21,567 - schedule_builder - INFO - Persisting schedule sched_20251031_133021_jadebri to BigQuery
2025-10-31 13:30:22,890 - schedule_builder - INFO - Schedule sched_20251031_133021_jadebri persisted successfully
2025-10-31 13:30:23,456 - schedule_builder - INFO - Locking 9 caption assignments for sched_20251031_133021_jadebri
2025-10-31 13:30:24,123 - schedule_builder - INFO - Locked 9 caption assignments
2025-10-31 13:30:24,456 - schedule_builder - INFO - Schedule sched_20251031_133021_jadebri built successfully in 9.33s: 18 messages, 9 PPVs, 9 Bumps

============================================================
Schedule sched_20251031_133021_jadebri created successfully!
============================================================
Page: jadebri
Start Date: 2025-11-04
Total Messages: 18
PPVs: 9
Bumps: 9
CSV: sched_20251031_133021_jadebri.csv
============================================================
```

---

## Account Size Framework

The Schedule Builder automatically classifies creators into 5 tiers based on revenue and adjusts message volumes accordingly.

### Tier Definitions

| Tier | Revenue Range | Weekly PPVs | Weekly Bumps | Min Gap | Max Msgs/Day | Strategy |
|------|---------------|-------------|--------------|---------|--------------|----------|
| **MICRO** | < $5K | 5-7 | 3-5 | 3.0 hrs | 8 | Conservative, relationship-building |
| **SMALL** | $5K-$25K | 7-10 | 5-7 | 2.5 hrs | 10 | Balanced growth |
| **MEDIUM** | $25K-$100K | 10-14 | 7-10 | 2.0 hrs | 15 | Optimized for scale |
| **LARGE** | $100K-$500K | 14-18 | 10-14 | 1.5 hrs | 20 | High-volume efficiency |
| **MEGA** | > $500K | 18-25 | 14-18 | 1.25 hrs | 25 | Maximum throughput |

### Volume Calculation Example

```python
# MEDIUM account in GREEN zone
base_ppv = (10 + 14) // 2 = 12
base_bump = (7 + 10) // 2 = 8
saturation_multiplier = 1.0 (GREEN)
adjusted_ppv = 12 * 1.0 = 12
adjusted_bump = 8 * 1.0 = 8

# MEDIUM account in YELLOW zone
saturation_multiplier = 0.75 (YELLOW)
bump_increase = 1.20 (YELLOW)
adjusted_ppv = 12 * 0.75 = 9
adjusted_bump = 8 * 1.20 = 9

# MEDIUM account in RED zone
saturation_multiplier = 0.5 (RED)
bump_increase = 2.0 (RED)
cooling_days = 2
adjusted_ppv = 12 * 0.5 = 6 (after cooling)
adjusted_bump = 8 * 2.0 = 16
```

### Daily Distribution

PPVs and Bumps are distributed across 7 days:
- **Cooling days** (if RED zone): Only bumps, no PPVs
- **Normal days**: PPVs + Bumps distributed evenly
- **Peak days** (Fri/Sat): Slightly more PPVs (10% boost)

---

## Saturation Response System

The builder uses a 3-zone system to prevent audience fatigue while maximizing revenue.

### Zone Definitions

#### GREEN Zone (Score < 0.30)
**Status**: Healthy engagement, room to grow

**Actions**:
- 100% normal volume
- No adjustments needed
- Consider gradual volume increase

**Example**:
```
MEDIUM account, saturation_score = 0.25
→ 12 PPVs, 8 Bumps per week
→ Standard 2-hour gaps
→ No cooling days
```

#### YELLOW Zone (Score 0.30-0.60)
**Status**: Early saturation signals detected

**Actions**:
- Reduce PPV volume by 25%
- Increase bumps by 20% (more free content)
- Extend gaps by 30 minutes

**Example**:
```
MEDIUM account, saturation_score = 0.45
→ 9 PPVs (-25%), 9 Bumps (+20%)
→ 2.5-hour gaps (extended)
→ No cooling days
→ More budget-tier content
```

#### RED Zone (Score > 0.60)
**Status**: Critical saturation, risk of unsubscribes

**Actions**:
- **MANDATORY**: 2 cooling days (no PPVs)
- Reduce PPV volume by 50% after cooling
- Double bump frequency (engagement recovery)
- Extend gaps by 1 hour
- Progressive ramp: +10% volume per day until YELLOW

**Example**:
```
MEDIUM account, saturation_score = 0.78
→ Day 1-2: 6 Bumps only (cooling)
→ Day 3-7: 6 PPVs, 10 Bumps
→ 3-hour gaps (doubled)
→ Progressive ramp: Day 3=6 PPVs, Day 4=7 PPVs, Day 5=8 PPVs...
```

### Saturation Score Calculation

The saturation score (0.0-1.0) is calculated by `analyze_creator_performance` based on:
- Unlock rate deviation from baseline (-20% = saturation)
- EMV deviation from expected (declining = saturation)
- Consecutive underperforming days (3+ days = warning)
- Message frequency trends (increasing = risk)

---

## API Reference

### ScheduleBuilder Class

#### Constructor
```python
ScheduleBuilder(project_id: str, dataset: str)
```
Initialize the schedule builder with BigQuery credentials.

**Parameters**:
- `project_id` (str): GCP project ID (e.g., "of-scheduler-proj")
- `dataset` (str): BigQuery dataset name (e.g., "eros_scheduling_brain")

**Returns**: ScheduleBuilder instance

**Example**:
```python
builder = ScheduleBuilder("of-scheduler-proj", "eros_scheduling_brain")
```

---

#### analyze_creator()
```python
analyze_creator(page_name: str) -> Dict[str, Any]
```
Analyze creator performance and return comprehensive metrics.

**Parameters**:
- `page_name` (str): Creator's page name

**Returns**: Dict containing:
- `account_classification`: Size tier, volume targets, saturation tolerance
- `behavioral_segment`: Segment label (BUDGET/STANDARD/PREMIUM/LUXURY), RPR metrics
- `saturation`: Score, risk level, recommended actions
- `psychological_trigger_analysis`: Top performing triggers
- `content_category_performance`: Category-level metrics
- `time_window_optimization`: Peak hours by day type

**Raises**:
- `Exception`: If BigQuery query fails

**Example**:
```python
analysis = builder.analyze_creator("jadebri")
print(f"Tier: {analysis['account_classification']['size_tier']}")
print(f"Saturation: {analysis['saturation']['saturation_score']:.2f}")
```

---

#### calculate_volume_targets()
```python
calculate_volume_targets(
    account_size: str,
    saturation_score: float,
    saturation_tolerance: float = 0.5
) -> Tuple[int, int, str]
```
Calculate PPV and Bump counts based on account size and saturation.

**Parameters**:
- `account_size` (str): MICRO, SMALL, MEDIUM, LARGE, or MEGA
- `saturation_score` (float): 0.0 to 1.0
- `saturation_tolerance` (float): Threshold for zone calculation (default: 0.5)

**Returns**: Tuple of (ppv_count, bump_count, saturation_zone)

**Example**:
```python
ppv, bump, zone = builder.calculate_volume_targets("MEDIUM", 0.45, 0.5)
# Returns: (9, 9, "YELLOW")
```

---

#### select_captions()
```python
select_captions(
    page_name: str,
    behavioral_segment: str,
    num_budget: int,
    num_mid: int,
    num_premium: int,
    num_bump: int
) -> List[Dict[str, Any]]
```
Select optimized captions using Thompson Sampling stored procedure.

**Parameters**:
- `page_name` (str): Creator's page name
- `behavioral_segment` (str): BUDGET, STANDARD, PREMIUM, or LUXURY
- `num_budget` (int): Number of budget-tier captions needed
- `num_mid` (int): Number of mid-tier captions needed
- `num_premium` (int): Number of premium-tier captions needed
- `num_bump` (int): Number of bump captions needed

**Returns**: List of caption dicts with:
- `caption_id`: Database ID
- `caption_text`: Full text
- `price_tier`: Budget/Mid/Premium/Bump
- `content_category`: Category classification
- `has_urgency`: Boolean urgency flag
- `performance_score`: Historical score

**Raises**:
- `Exception`: If stored procedure call fails

**Example**:
```python
captions = builder.select_captions(
    page_name="jadebri",
    behavioral_segment="STANDARD",
    num_budget=3,
    num_mid=5,
    num_premium=2,
    num_bump=8
)
print(f"Selected {len(captions)} captions")
```

---

#### build_schedule()
```python
build_schedule(
    page_name: str,
    start_date: str,
    override_params: Optional[Dict[str, Any]] = None
) -> Tuple[str, pd.DataFrame]
```
Build complete 7-day schedule with BigQuery persistence.

**Parameters**:
- `page_name` (str): Creator's page name
- `start_date` (str): Schedule start date in YYYY-MM-DD format
- `override_params` (dict, optional): Override volume calculations with custom values

**Returns**: Tuple of (schedule_id, schedule_dataframe)

**Raises**:
- `ValueError`: If no captions selected
- `Exception`: If BigQuery operations fail

**Example**:
```python
# Normal usage
schedule_id, df = builder.build_schedule("jadebri", "2025-11-04")

# With overrides (for testing)
schedule_id, df = builder.build_schedule(
    "jadebri",
    "2025-11-04",
    override_params={'ppv_count': 10, 'bump_count': 5, 'zone': 'GREEN'}
)
```

---

#### export_csv()
```python
export_csv(schedule_df: pd.DataFrame, output_path: str)
```
Export schedule DataFrame to CSV file.

**Parameters**:
- `schedule_df` (pd.DataFrame): Schedule dataframe from build_schedule()
- `output_path` (str): File path for CSV output

**Returns**: None

**Example**:
```python
builder.export_csv(df, "jadebri_schedule.csv")
```

---

## CSV Output Format

### Column Specifications

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| schedule_id | STRING | Unique schedule identifier | sched_20251031_133021_jadebri |
| page_name | STRING | Creator's page name | jadebri |
| day_of_week | STRING | Day name | Monday |
| scheduled_send_time | TIMESTAMP | Full send timestamp | 2025-11-04 10:00:00 |
| message_type | STRING | PPV or Bump | PPV |
| caption_id | INTEGER | Caption database ID | 12345 |
| caption_text | STRING | Full caption text | Check your DMs 💌 |
| price_tier | STRING | Budget, Mid, Premium, Free | Premium |
| content_category | STRING | Content classification | Tease/Preview |
| has_urgency | BOOLEAN | Urgency flag | TRUE |
| performance_score | FLOAT | Historical score (0-1) | 0.87 |

### Sample CSV

```csv
schedule_id,page_name,day_of_week,scheduled_send_time,message_type,caption_id,caption_text,price_tier,content_category,has_urgency,performance_score
sched_20251031_133021_jadebri,jadebri,Monday,2025-11-04 10:00:00,PPV,12345,"Check your DMs 💌",Premium,Tease/Preview,TRUE,0.87
sched_20251031_133021_jadebri,jadebri,Monday,2025-11-04 13:30:00,Bump,12346,"Good afternoon babe 💕",Free,Engagement,FALSE,0.0
sched_20251031_133021_jadebri,jadebri,Monday,2025-11-04 17:15:00,PPV,12347,"Just posted something special... 🔥",Mid,Full Explicit,FALSE,0.72
sched_20251031_133021_jadebri,jadebri,Tuesday,2025-11-05 09:45:00,Bump,12348,"Rise and shine 🌅",Free,Engagement,FALSE,0.0
sched_20251031_133021_jadebri,jadebri,Tuesday,2025-11-05 14:20:00,PPV,12349,"You don't want to miss this...",Budget,Tease/Preview,TRUE,0.65
```

---

## BigQuery Integration

### Tables Created

#### schedule_recommendations
Stores schedule JSON for persistence and audit.

**Schema**:
```sql
CREATE TABLE schedule_recommendations (
    schedule_id STRING NOT NULL,
    page_name STRING NOT NULL,
    created_at TIMESTAMP NOT NULL,
    schedule_json STRING NOT NULL,  -- Full schedule as JSON
    total_messages INTEGER,
    saturation_zone STRING
);
```

**Query Example**:
```sql
SELECT
    schedule_id,
    page_name,
    created_at,
    total_messages,
    saturation_zone,
    JSON_EXTRACT_SCALAR(schedule_json, '$.account_tier') AS account_tier
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
WHERE page_name = 'jadebri'
ORDER BY created_at DESC
LIMIT 5;
```

---

#### schedule_export_log
Tracks all schedule generation attempts with execution metrics.

**Schema**:
```sql
CREATE TABLE schedule_export_log (
    schedule_id STRING NOT NULL,
    page_name STRING NOT NULL,
    export_timestamp TIMESTAMP NOT NULL,
    message_count INTEGER,
    execution_time_seconds FLOAT64,
    error_message STRING,
    status STRING  -- SUCCESS or FAILED
);
```

**Query Example**:
```sql
SELECT
    page_name,
    COUNT(*) AS total_runs,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful,
    AVG(execution_time_seconds) AS avg_duration,
    AVG(message_count) AS avg_messages
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY page_name
ORDER BY total_runs DESC;
```

---

### Stored Procedures Used

#### analyze_creator_performance
Analyzes creator metrics using 5 table-valued functions.

**Call**:
```sql
DECLARE performance_report STRING;
CALL `of-scheduler-proj.eros_scheduling_brain.analyze_creator_performance`(
    'jadebri',
    performance_report
);
SELECT performance_report;
```

**Returns**: JSON string with complete performance analysis

---

#### select_captions_for_creator
Selects captions using Thompson Sampling with Wilson Score.

**Call**:
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.select_captions_for_creator`(
    'jadebri',      -- page_name
    'STANDARD',     -- behavioral_segment
    3,              -- num_budget_needed
    5,              -- num_mid_needed
    2,              -- num_premium_needed
    8               -- num_bump_needed
);

SELECT * FROM caption_selection_results;
```

**Returns**: Temporary table with selected captions

---

#### lock_caption_assignments
Atomically locks caption assignments with conflict prevention.

**Call**:
```sql
CALL `of-scheduler-proj.eros_scheduling_brain.lock_caption_assignments`(
    'sched_20251031_133021_jadebri',  -- schedule_id
    'jadebri',                         -- page_name
    [                                  -- caption_assignments
        STRUCT(12345 AS caption_id, DATE('2025-11-04') AS scheduled_send_date, 10 AS scheduled_send_hour),
        STRUCT(12347 AS caption_id, DATE('2025-11-04') AS scheduled_send_date, 17 AS scheduled_send_hour)
    ]
);
```

**Effects**:
- Inserts rows into `active_caption_assignments`
- Checks for conflicts (7-day window)
- Raises error if conflicts detected

---

## Error Handling

### Automatic Recovery

The builder includes automatic error recovery for common issues:

#### Missing Tables
```python
# If schedule_recommendations doesn't exist
try:
    query_job = self.client.query(insert_query)
    query_job.result()
except Exception as e:
    if 'Not found: Table' in str(e):
        self._create_schedule_table()  # Auto-create
        query_job = self.client.query(insert_query)  # Retry
        query_job.result()
```

#### Transient BigQuery Errors
```python
# Automatic retry with exponential backoff
from google.api_core import retry

@retry.Retry(predicate=retry.if_transient_error)
def query_with_retry():
    return self.client.query(query).result()
```

#### Missing Caption Data
```python
if not captions:
    raise ValueError(f"No captions selected for {page_name}")
```

### Error Logging

All errors are logged with context:
```
2025-10-31 13:30:24,567 - schedule_builder - ERROR - Failed to select captions for jadebri: 400 Procedure `select_captions_for_creator` not found
```

### Exception Hierarchy

```
Exception (base)
├─ ValueError: Invalid input parameters
│   ├─ No captions selected
│   ├─ Invalid date format
│   └─ Invalid account size
├─ google.api_core.exceptions.GoogleAPIError: BigQuery errors
│   ├─ NotFound: Table/procedure missing
│   ├─ BadRequest: Invalid query
│   ├─ Forbidden: Permission denied
│   └─ DeadlineExceeded: Timeout
└─ RuntimeError: Unexpected system errors
```

---

## Testing

### Unit Tests (No BigQuery Required)

```bash
# Run volume calculation tests
python test_schedule_builder.py
```

**Output**:
```
================================================================================
VOLUME CALCULATION TESTS
================================================================================

Account    Saturation Zone            PPVs       Bumps
--------------------------------------------------------------------------------
MICRO            0.20 GREEN                    6          4 ✓
SMALL            0.20 GREEN                    8          6 ✓
MEDIUM           0.40 YELLOW                   9          9 ✓
LARGE            0.70 RED                      8         24 ✓
MEGA             0.80 RED                     10         32 ✓
```

### Integration Tests (Requires BigQuery)

```python
from schedule_builder import ScheduleBuilder

def test_full_integration():
    builder = ScheduleBuilder("of-scheduler-proj", "eros_scheduling_brain")

    # Test with real data
    schedule_id, df = builder.build_schedule("jadebri", "2025-11-04")

    # Assertions
    assert len(df) > 0, "Schedule should have messages"
    assert len(df[df['message_type'] == 'PPV']) > 0, "Should have PPVs"
    assert len(df[df['message_type'] == 'Bump']) > 0, "Should have Bumps"
    assert df['schedule_id'].nunique() == 1, "All rows should have same schedule_id"

    print("✓ Integration test passed")

test_full_integration()
```

### Sample Data Generation

```python
# Generate sample CSV for testing
python test_schedule_builder.py
# Creates: sample_schedule_output.csv
```

---

## Monitoring

### Health Check Query

```sql
-- Schedule Builder Health Check
WITH recent_runs AS (
    SELECT
        page_name,
        COUNT(*) AS total_runs,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful_runs,
        AVG(execution_time_seconds) AS avg_duration,
        AVG(message_count) AS avg_messages,
        MAX(export_timestamp) AS last_run
    FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
    WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    GROUP BY page_name
)
SELECT
    page_name,
    total_runs,
    successful_runs,
    ROUND(successful_runs / total_runs * 100, 1) AS success_rate_pct,
    ROUND(avg_duration, 2) AS avg_duration_sec,
    ROUND(avg_messages, 0) AS avg_messages,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_run, HOUR) AS hours_since_last_run,
    CASE
        WHEN successful_runs / total_runs >= 0.95 THEN '✓ HEALTHY'
        WHEN successful_runs / total_runs >= 0.80 THEN '⚠ WARNING'
        ELSE '✗ CRITICAL'
    END AS health_status
FROM recent_runs
ORDER BY total_runs DESC;
```

### Performance Metrics

```sql
-- Schedule Builder Performance Trends
SELECT
    DATE(export_timestamp) AS export_date,
    COUNT(*) AS runs,
    AVG(execution_time_seconds) AS avg_duration,
    MIN(execution_time_seconds) AS min_duration,
    MAX(execution_time_seconds) AS max_duration,
    APPROX_QUANTILES(execution_time_seconds, 100)[OFFSET(50)] AS median_duration,
    AVG(message_count) AS avg_messages
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_export_log`
WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND status = 'SUCCESS'
GROUP BY export_date
ORDER BY export_date DESC;
```

### Alert Conditions

Set up alerts for:
- Success rate < 90% (7-day window)
- Average duration > 30 seconds
- No successful runs in last 24 hours
- Error rate spike (>2 errors/hour)

---

## Troubleshooting

### Common Issues

#### 1. "Procedure not found"

**Error**:
```
google.api_core.exceptions.NotFound: 400 Procedure `analyze_creator_performance` not found
```

**Solution**:
```bash
# Deploy stored procedures first
cd deployment
bq query --use_legacy_sql=false < stored_procedures.sql
bq query --use_legacy_sql=false < analyze_creator_performance_complete.sql
```

---

#### 2. "Permission denied"

**Error**:
```
google.api_core.exceptions.Forbidden: 403 Access Denied: Project of-scheduler-proj: User does not have permission
```

**Solution**:
```bash
# Authenticate with proper credentials
gcloud auth application-default login

# Or set service account
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"

# Verify access
bq ls of-scheduler-proj:eros_scheduling_brain
```

---

#### 3. "No captions selected"

**Error**:
```
ValueError: No captions selected for jadebri
```

**Causes**:
- Caption bank is empty
- All captions already locked
- Behavioral segment has no matching captions

**Solution**:
```sql
-- Check caption availability
SELECT
    price_tier,
    COUNT(*) AS total_captions,
    SUM(CASE WHEN caption_id IN (
        SELECT caption_id FROM active_caption_assignments WHERE is_active = TRUE
    ) THEN 1 ELSE 0 END) AS locked_captions
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
GROUP BY price_tier;

-- Unlock old assignments
UPDATE `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
SET is_active = FALSE
WHERE scheduled_send_date < DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY);
```

---

#### 4. Slow Performance

**Symptom**: Schedule generation takes > 30 seconds

**Diagnosis**:
```sql
-- Check query performance
SELECT
    job_id,
    creation_time,
    total_bytes_processed / 1024 / 1024 / 1024 AS gb_processed,
    total_slot_ms / 1000 AS slot_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_sec
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE query LIKE '%schedule_builder%'
    AND creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY creation_time DESC
LIMIT 10;
```

**Solutions**:
- Check if stored procedures need optimization
- Verify table clustering is in place
- Consider caching creator analysis results

---

#### 5. Duplicate Schedule IDs

**Symptom**: Multiple schedules with same ID

**Cause**: Concurrent execution without locking

**Prevention**:
```python
# Use unique timestamp in ID
schedule_id = f"sched_{datetime.now(LA_TZ).strftime('%Y%m%d_%H%M%S_%f')}_{page_name}"
```

---

### Debug Mode

Enable verbose logging:
```python
import logging
logging.basicConfig(level=logging.DEBUG)

from schedule_builder import ScheduleBuilder
builder = ScheduleBuilder("of-scheduler-proj", "eros_scheduling_brain")
```

---

## Advanced Usage

### Custom Volume Overrides

```python
# Override volume calculations for testing
schedule_id, df = builder.build_schedule(
    page_name="jadebri",
    start_date="2025-11-04",
    override_params={
        'ppv_count': 15,
        'bump_count': 10,
        'zone': 'GREEN'
    }
)
```

### Batch Processing

```python
creators = ['jadebri', 'creator2', 'creator3']
start_date = "2025-11-04"

for creator in creators:
    try:
        schedule_id, df = builder.build_schedule(creator, start_date)
        builder.export_csv(df, f"schedules/{schedule_id}.csv")
        print(f"✓ {creator}: {len(df)} messages")
    except Exception as e:
        print(f"✗ {creator}: {e}")
```

### Schedule Analysis

```python
# Analyze generated schedule
def analyze_schedule(df):
    return {
        'total_messages': len(df),
        'ppv_count': len(df[df['message_type'] == 'PPV']),
        'bump_count': len(df[df['message_type'] == 'Bump']),
        'avg_performance_score': df['performance_score'].mean(),
        'urgency_rate': df['has_urgency'].mean(),
        'tier_distribution': df['price_tier'].value_counts().to_dict(),
        'messages_by_day': df.groupby('day_of_week').size().to_dict()
    }

schedule_id, df = builder.build_schedule("jadebri", "2025-11-04")
stats = analyze_schedule(df)
print(json.dumps(stats, indent=2))
```

---

## Version History

- **v1.0.0** (2025-10-31): Initial production release
  - Account size framework (MICRO-MEGA)
  - RED/YELLOW/GREEN saturation response
  - BigQuery integration with stored procedures
  - CSV export with 11 columns
  - Comprehensive error handling and logging

---

## License

Proprietary - EROS Scheduling System

---

## Support

For issues or questions:
1. Check this documentation
2. Review test output: `python test_schedule_builder.py`
3. Check BigQuery logs for stored procedure errors
4. Review `schedule_export_log` table for execution history

---

**Generated**: 2025-10-31
**Status**: Production Ready
**Version**: 1.0.0
