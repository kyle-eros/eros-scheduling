# Caption Restrictions Feature - Cloud Infrastructure Playbook

**Project**: OnlyFans Scheduling System
**Dataset**: `of-scheduler-proj.eros_scheduling_brain`
**Region**: US (multi-region)
**Document Version**: 1.0
**Last Updated**: 2025-10-29

---

## Table of Contents

1. [IAM & Security Configuration](#1-iam--security-configuration)
2. [Infrastructure Validation](#2-infrastructure-validation)
3. [Cost Analysis](#3-cost-analysis)
4. [Emergency Procedures](#4-emergency-procedures)
5. [Monitoring & Observability](#5-monitoring--observability)

---

## 1. IAM & Security Configuration

### 1.1 Required BigQuery IAM Roles

#### Service Account: Claude Code Agents

**Identity**: `claude-scheduler-agent@of-scheduler-proj.iam.gserviceaccount.com` (or equivalent)

**Required Roles**:
- `roles/bigquery.dataEditor` - Full read/write to tables
- `roles/bigquery.jobUser` - Execute queries and jobs

**Granular Permissions Required**:
```
bigquery.tables.get
bigquery.tables.getData
bigquery.tables.list
bigquery.tables.update
bigquery.tables.updateData
bigquery.datasets.get
bigquery.jobs.create
bigquery.jobs.get
bigquery.jobs.list
```

**Grant Command**:
```bash
# Set project
gcloud config set project of-scheduler-proj

# Grant roles to service account
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:claude-scheduler-agent@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:claude-scheduler-agent@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

**Least-Privilege Alternative** (Dataset-Scoped):
```bash
# Grant access only to eros_scheduling_brain dataset
bq add-iam-policy-binding \
  --member="serviceAccount:claude-scheduler-agent@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" \
  of-scheduler-proj:eros_scheduling_brain
```

#### Service Account: Google Apps Script

**Identity**: Apps Script runs under end-user OAuth credentials OR project service account

**Required OAuth Scopes** (if using user OAuth):
```javascript
// In appsscript.json
{
  "oauthScopes": [
    "https://www.googleapis.com/auth/bigquery",
    "https://www.googleapis.com/auth/bigquery.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/script.external_request"
  ]
}
```

**Required Roles** (if using service account):
- `roles/bigquery.dataViewer` - Read-only access to tables
- `roles/bigquery.jobUser` - Execute queries

**Grant Command** (Service Account Pattern):
```bash
# Assuming Apps Script service account
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:apps-script-scheduler@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:apps-script-scheduler@of-scheduler-proj.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"
```

### 1.2 Table-Level Security

#### Row-Level Security (Not Required)
Caption restrictions are designed for global/creator-scoped filtering. No row-level security needed.

#### Column-Level Security (Optional)
If storing PII in `restriction_notes`:
```sql
-- Create policy tag taxonomy (one-time setup)
CREATE TAG TEMPLATE restricted_data
  LOCATION = 'us'
  WITH (
    display_name = 'Restricted Data',
    fields = [
      'pii' (display_name = 'Personally Identifiable Information')
    ]
  );

-- Apply to sensitive columns
ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
ALTER COLUMN restriction_notes
SET OPTIONS (policy_tags = ('projects/of-scheduler-proj/locations/us/taxonomies/TAXONOMY_ID/policyTags/PII_TAG_ID'));
```

### 1.3 Audit Logging

**Enabled by Default**: BigQuery Admin Activity logs are automatically enabled.

**Data Access Logs** (Optional, increases costs):
```bash
# Enable Data Access audit logs for BigQuery
gcloud projects set-iam-policy of-scheduler-proj policy.yaml
```

**policy.yaml**:
```yaml
auditConfigs:
- service: bigquery.googleapis.com
  auditLogConfigs:
  - logType: DATA_READ
  - logType: DATA_WRITE
  - logType: ADMIN_READ
```

**View Audit Logs**:
```bash
# View recent BigQuery operations
gcloud logging read "protoPayload.serviceName=\"bigquery.googleapis.com\"" \
  --project=of-scheduler-proj \
  --limit=50 \
  --format=json
```

### 1.4 Security Best Practices

#### Data Classification
- **caption_text**: PUBLIC - No sensitive data
- **restriction_patterns**: INTERNAL - Business logic
- **creator_name**: INTERNAL - Creator identifiers
- **restriction_notes**: CONFIDENTIAL - May contain reasons

#### Encryption
- **At Rest**: All BigQuery tables automatically encrypted with Google-managed keys
- **In Transit**: All API calls use TLS 1.2+
- **Customer-Managed Keys** (Optional):
```bash
# Create KMS key
gcloud kms keys create bigquery-encryption-key \
  --location=us \
  --keyring=scheduler-keyring \
  --purpose=encryption

# Set default encryption key for dataset
bq update --default_kms_key \
  projects/of-scheduler-proj/locations/us/keyRings/scheduler-keyring/cryptoKeys/bigquery-encryption-key \
  of-scheduler-proj:eros_scheduling_brain
```

#### Sensitive Data Handling
**CRITICAL**: Do NOT store PII in restriction patterns
- ❌ BAD: `"user_email": "creator@example.com"`
- ✅ GOOD: `"page_name": "jadebri"` (normalized identifier)

**Pattern Validation**:
```sql
-- Check for email-like patterns in restriction_notes
SELECT restriction_id, restriction_notes
FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
WHERE REGEXP_CONTAINS(restriction_notes, r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
LIMIT 10;
```

### 1.5 Access Control Matrix

| Identity Type | Tables | Operations | Use Case |
|--------------|--------|------------|----------|
| Claude Code Agent | All tables in dataset | SELECT, INSERT, UPDATE, MERGE | Schedule generation, caption selection |
| Apps Script (User OAuth) | `schedule_recommendations`, `latest_recommendations` view | SELECT | Import schedules to Google Sheets |
| Admin User | All tables | SELECT, INSERT, UPDATE, DELETE, ALTER | Emergency operations, schema changes |
| BigQuery Data Studio | All tables | SELECT | Monitoring dashboards |
| CI/CD Pipeline (GitHub Actions) | All tables | SELECT (validation queries) | Database integrity checks |

---

## 2. Infrastructure Validation

### 2.1 Dataset Location Validation

**Current Configuration**:
```bash
# Verify dataset location
bq show --format=prettyjson of-scheduler-proj:eros_scheduling_brain | grep location

# Expected Output: "location": "US"
```

**Critical Requirement**: All new tables MUST be created in `US` region to match existing tables.

**Table Location Check**:
```sql
-- Verify all tables are in US region
SELECT
  table_name,
  IFNULL(ddl, 'N/A') AS ddl_location_clause
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_type = 'BASE TABLE'
ORDER BY table_name;
```

### 2.2 Partitioning Strategy

#### Recommended Partitioning: `DATE(effective_date)`

**Rationale**:
1. **Query Pattern**: Most queries filter by current date (`WHERE effective_date <= CURRENT_DATE()`)
2. **Partition Pruning**: Reduces bytes scanned by 70-90% for time-range queries
3. **Cost Optimization**: Only scans relevant date partitions
4. **Data Lifecycle**: Easy to implement expiration (e.g., auto-delete partitions > 2 years old)

**Partition vs Clustering Decision Matrix**:

| Factor | Partition by `effective_date` | Cluster by `effective_date` |
|--------|------------------------------|----------------------------|
| Query performance on date range | ✅ Excellent (partition pruning) | ⚠️ Good (block pruning) |
| Small table overhead | ⚠️ Higher (partition metadata) | ✅ Lower |
| Automatic data expiration | ✅ Native support | ❌ Manual deletion |
| Max partitions limit | ⚠️ 4,000 partitions (11 years daily) | ✅ No limit |

**Implementation**:
```sql
CREATE TABLE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions` (
  restriction_id STRING NOT NULL,
  restriction_type STRING NOT NULL,
  target_scope STRING NOT NULL,
  target_value STRING NOT NULL,
  restriction_patterns JSON,
  effective_date DATE NOT NULL,
  expiration_date DATE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created_by STRING,
  restriction_notes STRING
)
PARTITION BY effective_date
CLUSTER BY target_scope, target_value, is_active
OPTIONS(
  description = "Caption restriction rules for caption-selector filtering",
  require_partition_filter = true,
  partition_expiration_days = 730  -- 2 years retention
);
```

**Partition Pruning Validation**:
```sql
-- This query scans ONLY today's partition (estimated ~0.001 GB)
SELECT COUNT(*) AS active_restrictions
FROM `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
WHERE effective_date = CURRENT_DATE()
  AND is_active = TRUE;

-- Verify partition pruning in query plan
-- Run with --dry_run to see bytes scanned
```

### 2.3 Clustering Strategy

**Recommended Clustering**: `target_scope, target_value, is_active`

**Rationale**:
1. **Cardinality Analysis**:
   - `target_scope`: LOW (4 values: global, creator, tier, category)
   - `target_value`: MEDIUM (100-500 unique creators/tiers/categories)
   - `is_active`: LOW (2 values: TRUE, FALSE)
2. **Query Patterns**:
   - `WHERE target_scope = 'creator' AND target_value = 'jadebri'` → Direct block skip
   - `WHERE is_active = TRUE` → Filter at storage level
3. **Clustering Order**: Most selective first (scope → value → active)

**Performance Impact**:
- **Without Clustering**: Scans ~100% of partition
- **With Clustering**: Scans ~10-20% of partition (depending on selectivity)

---

## 3. Cost Analysis

### 3.1 New Tables Cost Breakdown

**Storage**: <$0.01/month (negligible)
**Queries**: <$0.01/month (within free tier)
**Total**: **$0.00/month**

### 3.2 Cost Optimization Recommendations

#### 1. Partition Expiration
```sql
ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET OPTIONS (partition_expiration_days = 730);
```

#### 2. Require Partition Filters
```sql
ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET OPTIONS (require_partition_filter = true);
```

---

## 4. Emergency Procedures

### 4.1 Feature Flag Emergency Toggle

#### Scenario: Caption restrictions causing issues

**Emergency Disable Command** (Disable ALL restrictions):
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET is_active = FALSE
WHERE is_active = TRUE;
```

**Emergency Enable Command**:
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET is_active = TRUE
WHERE is_active = FALSE;
```

---

## 5. Monitoring & Observability

### 5.1 Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| **active_restrictions** | Total enabled rules | > 200 |
| **caption_pool_blocked** | % captions filtered | > 30% |

---

**End of Playbook**
