# IAM Configuration for Caption Restrictions Feature

## Overview
This document provides IAM configuration for the allowed-aware caption restrictions feature, including required permissions for Apps Script service accounts, BigQuery roles, and validation queries.

---

## TASK 1: IAM Permissions Verification

### Required Permissions Matrix

| Resource | Permission Type | Apps Script Service Account | BigQuery Job User | Notes |
|----------|----------------|----------------------------|-------------------|-------|
| `creator_caption_restrictions` | MERGE | REQUIRED | N/A | Write restrictions from Sheets |
| `creator_allowed_profile` | MERGE | REQUIRED | N/A | Write allowed profiles from Sheets |
| `active_creator_caption_restrictions_v` | SELECT | REQUIRED | REQUIRED | Read active restrictions |
| `creator_allowed_profile_v` | SELECT | REQUIRED | REQUIRED | Read allowed profiles |
| `feature_flags` | SELECT | REQUIRED | REQUIRED | Check feature enablement |

---

## IAM Roles Configuration

### Apps Script Service Account Roles

The Apps Script service account requires two primary roles:

1. **bigquery.dataEditor** - For MERGE operations
   - Allows INSERT, UPDATE, DELETE on tables
   - Grants SELECT on tables and views
   - Required for `creator_caption_restrictions` and `creator_allowed_profile`

2. **bigquery.jobUser** - For query execution
   - Allows running BigQuery jobs
   - Required for all SELECT/MERGE queries
   - Project-level permission

### Grant Commands

```bash
# Replace with your actual Apps Script service account email
SERVICE_ACCOUNT="apps-script-sa@of-scheduler-proj.iam.gserviceaccount.com"
PROJECT_ID="of-scheduler-proj"
DATASET_ID="eros_scheduling_brain"

# Grant BigQuery Job User (project-level)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.jobUser" \
  --condition=None

# Grant BigQuery Data Editor (dataset-level)
bq add-iam-policy-binding \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.dataEditor" \
  "${PROJECT_ID}:${DATASET_ID}"
```

---

## Table-Level Permissions (Alternative Fine-Grained Approach)

If you prefer granular table-level permissions instead of dataset-level:

```bash
# Grant MERGE permissions on specific tables
TABLES=(
  "creator_caption_restrictions"
  "creator_allowed_profile"
)

for table in "${TABLES[@]}"; do
  bq update --iam-policy <(cat <<EOF
{
  "bindings": [
    {
      "role": "roles/bigquery.dataEditor",
      "members": [
        "serviceAccount:${SERVICE_ACCOUNT}"
      ]
    }
  ]
}
EOF
) "${PROJECT_ID}:${DATASET_ID}.${table}"
done

# Grant SELECT permissions on views
VIEWS=(
  "active_creator_caption_restrictions_v"
  "creator_allowed_profile_v"
  "feature_flags"
)

for view in "${VIEWS[@]}"; do
  bq update --iam-policy <(cat <<EOF
{
  "bindings": [
    {
      "role": "roles/bigquery.dataViewer",
      "members": [
        "serviceAccount:${SERVICE_ACCOUNT}"
      ]
    }
  ]
}
EOF
) "${PROJECT_ID}:${DATASET_ID}.${view}"
done
```

---

## Validation Queries

### 1. Verify Service Account Has Required Roles

```sql
-- Query IAM policy to verify roles (run as admin)
-- This requires resourcemanager.projects.getIamPolicy permission

-- Check project-level roles
SELECT
  'bigquery.jobUser' AS required_role,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM UNNEST(['roles/bigquery.jobUser']) AS granted_role
    ) THEN 'GRANTED'
    ELSE 'MISSING'
  END AS status;

-- Note: IAM policy queries require Cloud Asset API or manual verification via:
-- gcloud projects get-iam-policy of-scheduler-proj \
--   --flatten="bindings[].members" \
--   --filter="bindings.members:serviceAccount:apps-script-sa@of-scheduler-proj.iam.gserviceaccount.com" \
--   --format="table(bindings.role)"
```

### 2. Test MERGE Permission on creator_caption_restrictions

```sql
-- Run this query as the Apps Script service account to verify MERGE permission
MERGE `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions` AS target
USING (
  SELECT
    'test_creator_iam_check' AS page_name,
    'IAM verification test' AS restriction_text,
    [] AS hard_patterns,
    [] AS soft_patterns,
    [] AS restricted_categories,
    [] AS restricted_price_tiers,
    'ALL' AS applies_to_scope,
    200 AS min_ppv_pool,
    50 AS min_bump_pool,
    FALSE AS is_active,
    CURRENT_TIMESTAMP() AS updated_at,
    'iam_validation_script' AS updated_by,
    1 AS version
) AS source
ON target.page_name = source.page_name AND target.is_active = FALSE

WHEN MATCHED THEN
  UPDATE SET
    restriction_text = source.restriction_text,
    updated_at = source.updated_at

WHEN NOT MATCHED THEN
  INSERT (
    page_name, restriction_text, hard_patterns, soft_patterns,
    restricted_categories, restricted_price_tiers, applies_to_scope,
    min_ppv_pool, min_bump_pool, is_active, updated_at, updated_by, version
  )
  VALUES (
    source.page_name, source.restriction_text, source.hard_patterns, source.soft_patterns,
    source.restricted_categories, source.restricted_price_tiers, source.applies_to_scope,
    source.min_ppv_pool, source.min_bump_pool, source.is_active, source.updated_at,
    source.updated_by, source.version
  );

-- Clean up test data
DELETE FROM `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`
WHERE page_name = 'test_creator_iam_check' AND is_active = FALSE;
```

### 3. Test MERGE Permission on creator_allowed_profile

```sql
-- Run this query as the Apps Script service account to verify MERGE permission
MERGE `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile` AS target
USING (
  SELECT
    'test_creator_iam_check' AS page_name,
    ['solo'] AS ppv_allowed_categories,
    ['tier_1'] AS ppv_allowed_price_tiers,
    ['solo'] AS bump_allowed_categories,
    ['tier_1'] AS bump_allowed_price_tiers,
    FALSE AS is_active,
    TRUE AS feature_enabled,
    CURRENT_TIMESTAMP() AS created_at,
    CURRENT_TIMESTAMP() AS updated_at,
    'iam_validation_script' AS updated_by,
    'IAM verification test' AS notes
) AS source
ON target.page_name = source.page_name AND target.is_active = FALSE

WHEN MATCHED THEN
  UPDATE SET
    updated_at = source.updated_at,
    notes = source.notes

WHEN NOT MATCHED THEN
  INSERT (
    page_name, ppv_allowed_categories, ppv_allowed_price_tiers,
    bump_allowed_categories, bump_allowed_price_tiers,
    is_active, feature_enabled, created_at, updated_at, updated_by, notes
  )
  VALUES (
    source.page_name, source.ppv_allowed_categories, source.ppv_allowed_price_tiers,
    source.bump_allowed_categories, source.bump_allowed_price_tiers,
    source.is_active, source.feature_enabled, source.created_at, source.updated_at,
    source.updated_by, source.notes
  );

-- Clean up test data
DELETE FROM `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile`
WHERE page_name = 'test_creator_iam_check' AND is_active = FALSE;
```

### 4. Test SELECT Permission on Views

```sql
-- Test active_creator_caption_restrictions_v
SELECT COUNT(*) AS restriction_count
FROM `of-scheduler-proj.eros_scheduling_brain.active_creator_caption_restrictions_v`
LIMIT 1;

-- Test creator_allowed_profile_v
SELECT COUNT(*) AS profile_count
FROM `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile_v`
LIMIT 1;

-- Test feature_flags
SELECT flag, is_enabled
FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
WHERE flag = 'caption_restrictions_enabled'
LIMIT 1;
```

### 5. End-to-End IAM Validation Script

```bash
#!/bin/bash
# File: scripts/validate_iam.sh
# Purpose: Validate IAM permissions for Apps Script service account

set -euo pipefail

PROJECT_ID="of-scheduler-proj"
DATASET_ID="eros_scheduling_brain"
SERVICE_ACCOUNT="${APPS_SCRIPT_SA:-}"

if [[ -z "${SERVICE_ACCOUNT}" ]]; then
  echo "ERROR: APPS_SCRIPT_SA environment variable not set"
  echo "Usage: export APPS_SCRIPT_SA='your-sa@project.iam.gserviceaccount.com'"
  exit 1
fi

echo "Validating IAM permissions for: ${SERVICE_ACCOUNT}"
echo "=================================================="

# Test 1: Verify bigquery.jobUser role
echo "Test 1: Checking bigquery.jobUser role..."
if gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SERVICE_ACCOUNT}" \
  --format="value(bindings.role)" | grep -q "roles/bigquery.jobUser"; then
  echo "✓ bigquery.jobUser role granted"
else
  echo "✗ bigquery.jobUser role MISSING"
  exit 1
fi

# Test 2: Verify bigquery.dataEditor role
echo "Test 2: Checking bigquery.dataEditor role..."
if bq show --iam_policy "${PROJECT_ID}:${DATASET_ID}" | \
  grep -q "${SERVICE_ACCOUNT}"; then
  echo "✓ bigquery.dataEditor role granted (dataset-level)"
else
  echo "✗ bigquery.dataEditor role MISSING"
  exit 1
fi

# Test 3: Test SELECT on views
echo "Test 3: Testing SELECT permission on views..."
for view in "active_creator_caption_restrictions_v" "creator_allowed_profile_v" "feature_flags"; do
  if bq query --use_legacy_sql=false --format=none \
    "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_ID}.${view}\` LIMIT 1" &>/dev/null; then
    echo "✓ SELECT permission on ${view}"
  else
    echo "✗ SELECT permission MISSING on ${view}"
    exit 1
  fi
done

# Test 4: Test MERGE on tables (dry run)
echo "Test 4: Testing MERGE permission (dry run)..."
bq query --use_legacy_sql=false --dry_run \
  "MERGE \`${PROJECT_ID}.${DATASET_ID}.creator_caption_restrictions\` AS T
   USING (SELECT 'test' AS page_name) AS S
   ON T.page_name = S.page_name
   WHEN NOT MATCHED THEN INSERT (page_name) VALUES (S.page_name)" &>/dev/null

if [[ $? -eq 0 ]]; then
  echo "✓ MERGE permission on creator_caption_restrictions"
else
  echo "✗ MERGE permission MISSING on creator_caption_restrictions"
  exit 1
fi

echo ""
echo "=================================================="
echo "✓ All IAM permissions validated successfully!"
echo "=================================================="
```

---

## Troubleshooting

### Error: "Access Denied: BigQuery BigQuery: Permission bigquery.jobs.create denied"

**Cause**: Missing `bigquery.jobUser` role at project level.

**Fix**:
```bash
gcloud projects add-iam-policy-binding of-scheduler-proj \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.jobUser"
```

### Error: "Access Denied: Table [...]: PERMISSION_DENIED: Permission bigquery.tables.updateData denied"

**Cause**: Missing `bigquery.dataEditor` role at dataset level.

**Fix**:
```bash
bq add-iam-policy-binding \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.dataEditor" \
  "of-scheduler-proj:eros_scheduling_brain"
```

### Error: "Access Denied: View [...]: PERMISSION_DENIED: Permission bigquery.tables.getData denied"

**Cause**: Missing SELECT permission on underlying tables or views.

**Fix**: Grant `bigquery.dataViewer` role on dataset:
```bash
bq add-iam-policy-binding \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/bigquery.dataViewer" \
  "of-scheduler-proj:eros_scheduling_brain"
```

---

## Security Best Practices

1. **Principle of Least Privilege**: Only grant `dataEditor` on specific tables if possible
2. **Service Account Rotation**: Rotate service account keys every 90 days
3. **Audit Logging**: Enable BigQuery audit logs to track service account activity
4. **Monitoring**: Set up alerts for unexpected IAM changes
5. **Separation of Duties**: Use separate service accounts for read-only vs. write operations

---

## References

- [BigQuery IAM Roles](https://cloud.google.com/bigquery/docs/access-control)
- [Service Account Best Practices](https://cloud.google.com/iam/docs/best-practices-service-accounts)
- [Apps Script BigQuery Integration](https://developers.google.com/apps-script/advanced/bigquery)
