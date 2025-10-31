# Apps Script Prerequisites Checklist for Caption Restrictions Feature

## Overview
This checklist ensures Google Apps Script has the necessary configuration, API access, and OAuth scopes to interact with BigQuery for the caption restrictions feature.

---

## Prerequisites Checklist

### Phase 1: GCP Project Configuration

- [ ] **GCP Project Exists**
  - Project ID: `of-scheduler-proj`
  - Project has billing enabled
  - Verify: `gcloud projects describe of-scheduler-proj`

- [ ] **BigQuery API Enabled**
  ```bash
  # Enable BigQuery API
  gcloud services enable bigquery.googleapis.com --project=of-scheduler-proj

  # Verify API is enabled
  gcloud services list --enabled --project=of-scheduler-proj | grep bigquery
  ```
  Expected output: `bigquery.googleapis.com  BigQuery API`

- [ ] **BigQuery Dataset Exists**
  ```bash
  # Verify dataset exists
  bq show of-scheduler-proj:eros_scheduling_brain
  ```
  Expected: Dataset metadata displayed without errors

- [ ] **Required Tables and Views Exist**
  ```bash
  # Check tables
  bq ls --max_results=100 of-scheduler-proj:eros_scheduling_brain | grep -E "(creator_caption_restrictions|creator_allowed_profile|feature_flags)"

  # Check views
  bq ls --max_results=100 of-scheduler-proj:eros_scheduling_brain | grep -E "(active_creator_caption_restrictions_v|creator_allowed_profile_v)"
  ```

---

### Phase 2: Apps Script Project Setup

- [ ] **Apps Script Project Created**
  - Navigate to: https://script.google.com
  - Create new project or use existing
  - Project name: "OnlyFans Schedule Import" (or your preferred name)

- [ ] **Apps Script Project Linked to GCP Project**
  1. In Apps Script, click **Project Settings** (gear icon)
  2. Scroll to "Google Cloud Platform (GCP) Project"
  3. Click "Change project"
  4. Enter GCP project number (NOT project ID)
  5. Click "Set project"

  **Get GCP Project Number:**
  ```bash
  gcloud projects describe of-scheduler-proj --format="value(projectNumber)"
  ```
  Example output: `123456789012`

- [ ] **Advanced BigQuery Service Enabled in Apps Script**
  1. In Apps Script, click **Editor** (< > icon)
  2. Click **Services** (+ icon next to "Services" in left sidebar)
  3. Search for "BigQuery API"
  4. Select "BigQuery API" from list
  5. Click "Add"
  6. Verify: "BigQuery" appears under "Services" in left sidebar

  **Alternative via Code:**
  ```javascript
  // In Code.gs, verify BigQuery service is accessible
  function testBigQueryService() {
    try {
      const projectId = 'of-scheduler-proj';
      const datasetId = 'eros_scheduling_brain';
      const dataset = BigQuery.Datasets.get(projectId, datasetId);
      Logger.log('BigQuery service accessible: ' + dataset.id);
      return true;
    } catch (e) {
      Logger.log('BigQuery service ERROR: ' + e.toString());
      return false;
    }
  }
  ```

---

### Phase 3: OAuth Scopes Configuration

- [ ] **BigQuery OAuth Scope Added to Manifest**
  1. In Apps Script, click **Project Settings** (gear icon)
  2. Check "Show 'appsscript.json' manifest file in editor"
  3. In Editor, open `appsscript.json`
  4. Add BigQuery scope to `oauthScopes` array:

  ```json
  {
    "timeZone": "America/Los_Angeles",
    "dependencies": {
      "enabledAdvancedServices": [
        {
          "userSymbol": "BigQuery",
          "version": "v2",
          "serviceId": "bigquery"
        }
      ]
    },
    "oauthScopes": [
      "https://www.googleapis.com/auth/spreadsheets",
      "https://www.googleapis.com/auth/script.container.ui",
      "https://www.googleapis.com/auth/bigquery",
      "https://www.googleapis.com/auth/bigquery.readonly"
    ],
    "exceptionLogging": "STACKDRIVER",
    "runtimeVersion": "V8"
  }
  ```

- [ ] **OAuth Scopes Verified**
  Run this test function to trigger OAuth consent:
  ```javascript
  function testOAuthScopes() {
    // Test spreadsheet access
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    Logger.log('Spreadsheet access: OK');

    // Test BigQuery access
    const projectId = 'of-scheduler-proj';
    const query = 'SELECT 1 AS test';
    const request = {
      query: query,
      useLegacySql: false
    };
    const queryResults = BigQuery.Jobs.query(request, projectId);
    Logger.log('BigQuery access: OK');

    return 'All OAuth scopes verified';
  }
  ```

  Expected: OAuth consent dialog appears on first run, then function completes successfully.

---

### Phase 4: Service Account & IAM

- [ ] **Service Account Identified**
  Apps Script uses a default service account with format:
  `project-name@appspot.gserviceaccount.com` or
  `PROJECT_NUMBER@cloudservices.gserviceaccount.com`

  **Find Service Account Email:**
  1. Run a BigQuery query from Apps Script
  2. In GCP Console, go to BigQuery > Job History
  3. Find recent job from Apps Script
  4. Click job > View Job Details > "User" field shows service account

  **Or programmatically:**
  ```javascript
  function getServiceAccountEmail() {
    const projectId = 'of-scheduler-proj';
    const query = 'SELECT SESSION_USER() AS service_account';
    const request = { query: query, useLegacySql: false };
    const queryResults = BigQuery.Jobs.query(request, projectId);
    const rows = queryResults.rows;
    if (rows && rows.length > 0) {
      Logger.log('Service Account: ' + rows[0].f[0].v);
      return rows[0].f[0].v;
    }
    return 'Unable to determine';
  }
  ```

- [ ] **IAM Roles Granted**
  Use service account email from previous step:

  ```bash
  # Set service account email
  export APPS_SCRIPT_SA="your-apps-script-sa@appspot.gserviceaccount.com"

  # Grant bigquery.jobUser (project-level)
  gcloud projects add-iam-policy-binding of-scheduler-proj \
    --member="serviceAccount:${APPS_SCRIPT_SA}" \
    --role="roles/bigquery.jobUser"

  # Grant bigquery.dataEditor (dataset-level)
  bq add-iam-policy-binding \
    --member="serviceAccount:${APPS_SCRIPT_SA}" \
    --role="roles/bigquery.dataEditor" \
    of-scheduler-proj:eros_scheduling_brain
  ```

- [ ] **IAM Permissions Validated**
  Run validation script:
  ```bash
  export APPS_SCRIPT_SA="your-apps-script-sa@appspot.gserviceaccount.com"
  ./scripts/validate_iam.sh
  ```
  Expected: All checks pass with checkmarks

---

### Phase 5: Apps Script Code Integration

- [ ] **BigQuery Query Pattern Implemented**
  Example function using parameterized queries:
  ```javascript
  /**
   * Query active caption restrictions for a creator
   * @param {string} pageName - Creator page name (lowercase)
   * @returns {object} Restriction configuration or null
   */
  function getCreatorRestrictions(pageName) {
    const projectId = CONFIG.bigquery.projectId;
    const query = `
      SELECT
        page_name,
        applies_to_scope,
        min_ppv_pool,
        min_bump_pool,
        hard_patterns,
        soft_patterns,
        restricted_categories,
        restricted_price_tiers
      FROM \`${projectId}.eros_scheduling_brain.active_creator_caption_restrictions_v\`
      WHERE page_name = @pageName
      LIMIT 1
    `;

    const request = {
      query: query,
      useLegacySql: false,
      parameterMode: 'NAMED',
      queryParameters: [
        {
          name: 'pageName',
          parameterType: { type: 'STRING' },
          parameterValue: { value: pageName }
        }
      ]
    };

    try {
      const queryResults = BigQuery.Jobs.query(request, projectId);
      const rows = queryResults.rows;

      if (!rows || rows.length === 0) {
        Logger.log('No restrictions found for: ' + pageName);
        return null;
      }

      // Parse results
      const row = rows[0];
      return {
        page_name: row.f[0].v,
        applies_to_scope: row.f[1].v,
        min_ppv_pool: parseInt(row.f[2].v),
        min_bump_pool: parseInt(row.f[3].v),
        hard_patterns: row.f[4].v ? row.f[4].v.map(item => item.v) : [],
        soft_patterns: row.f[5].v ? row.f[5].v.map(item => item.v) : [],
        restricted_categories: row.f[6].v ? row.f[6].v.map(item => item.v) : [],
        restricted_price_tiers: row.f[7].v ? row.f[7].v.map(item => item.v) : []
      };
    } catch (e) {
      Logger.log('ERROR querying restrictions: ' + e.toString());
      throw e;
    }
  }
  ```

- [ ] **MERGE Pattern Implemented**
  Example function for syncing restrictions from Sheets to BigQuery:
  ```javascript
  /**
   * Sync creator restrictions from Google Sheets to BigQuery
   * @param {Array<object>} restrictions - Array of restriction objects
   */
  function syncRestrictionsToBigQuery(restrictions) {
    const projectId = CONFIG.bigquery.projectId;
    const datasetId = CONFIG.bigquery.datasetId;
    const tableId = 'creator_caption_restrictions';

    // Build MERGE statement
    const sourceRows = restrictions.map(r => {
      return `
        SELECT
          '${r.page_name}' AS page_name,
          '${r.restriction_text || ''}' AS restriction_text,
          ${formatArrayForSQL(r.hard_patterns)} AS hard_patterns,
          ${formatArrayForSQL(r.soft_patterns)} AS soft_patterns,
          ${formatArrayForSQL(r.restricted_categories)} AS restricted_categories,
          ${formatArrayForSQL(r.restricted_price_tiers)} AS restricted_price_tiers,
          '${r.applies_to_scope || 'ALL'}' AS applies_to_scope,
          ${r.min_ppv_pool || 200} AS min_ppv_pool,
          ${r.min_bump_pool || 50} AS min_bump_pool,
          ${r.is_active !== false} AS is_active,
          CURRENT_TIMESTAMP() AS updated_at,
          'apps_script_sync' AS updated_by,
          1 AS version
      `;
    }).join(' UNION ALL ');

    const query = `
      MERGE \`${projectId}.${datasetId}.${tableId}\` AS target
      USING (${sourceRows}) AS source
      ON target.page_name = source.page_name

      WHEN MATCHED THEN
        UPDATE SET
          restriction_text = source.restriction_text,
          hard_patterns = source.hard_patterns,
          soft_patterns = source.soft_patterns,
          restricted_categories = source.restricted_categories,
          restricted_price_tiers = source.restricted_price_tiers,
          applies_to_scope = source.applies_to_scope,
          min_ppv_pool = source.min_ppv_pool,
          min_bump_pool = source.min_bump_pool,
          is_active = source.is_active,
          updated_at = source.updated_at,
          updated_by = source.updated_by,
          version = target.version + 1

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
        )
    `;

    const request = { query: query, useLegacySql: false };

    try {
      const queryResults = BigQuery.Jobs.query(request, projectId);
      Logger.log('MERGE completed. Rows modified: ' + queryResults.totalRows);
      return { success: true, rowsModified: queryResults.totalRows };
    } catch (e) {
      Logger.log('ERROR syncing restrictions: ' + e.toString());
      throw e;
    }
  }

  /**
   * Helper function to format JavaScript array for SQL ARRAY syntax
   */
  function formatArrayForSQL(arr) {
    if (!arr || arr.length === 0) {
      return '[]';
    }
    const escapedItems = arr.map(item => `'${item.replace(/'/g, "\\'")}'`);
    return `[${escapedItems.join(', ')}]`;
  }
  ```

- [ ] **Error Handling Implemented**
  ```javascript
  /**
   * Wrapper for BigQuery queries with retry logic
   */
  function executeBigQueryWithRetry(request, projectId, maxRetries = 3) {
    let attempt = 0;
    let lastError = null;

    while (attempt < maxRetries) {
      try {
        const result = BigQuery.Jobs.query(request, projectId);
        return { success: true, data: result };
      } catch (e) {
        lastError = e;
        attempt++;

        // Check if error is retryable
        const errorMsg = e.toString();
        if (errorMsg.includes('PERMISSION_DENIED') ||
            errorMsg.includes('NOT_FOUND')) {
          // Non-retryable errors
          throw e;
        }

        // Exponential backoff
        const waitTime = Math.pow(2, attempt) * 1000;
        Logger.log(`Retry attempt ${attempt}/${maxRetries} after ${waitTime}ms`);
        Utilities.sleep(waitTime);
      }
    }

    throw new Error('BigQuery query failed after ' + maxRetries + ' attempts: ' + lastError);
  }
  ```

---

### Phase 6: Testing & Validation

- [ ] **Unit Tests Pass**
  ```javascript
  function runAllTests() {
    const tests = [
      testBigQueryService,
      testOAuthScopes,
      testGetCreatorRestrictions,
      testSyncRestrictionsToBigQuery
    ];

    const results = tests.map(test => {
      try {
        test();
        return { test: test.name, status: 'PASS' };
      } catch (e) {
        return { test: test.name, status: 'FAIL', error: e.toString() };
      }
    });

    Logger.log('Test Results:');
    results.forEach(r => {
      Logger.log(`${r.status}: ${r.test}${r.error ? ' - ' + r.error : ''}`);
    });

    return results;
  }

  function testGetCreatorRestrictions() {
    // Test with a known creator (adjust as needed)
    const restrictions = getCreatorRestrictions('test_creator');
    // Should not throw error, may return null if no restrictions exist
    Logger.log('Get restrictions test: OK');
  }

  function testSyncRestrictionsToBigQuery() {
    // Test with minimal data
    const testRestrictions = [{
      page_name: 'test_creator_apps_script',
      restriction_text: 'Test restriction',
      hard_patterns: ['test_pattern'],
      soft_patterns: [],
      restricted_categories: [],
      restricted_price_tiers: [],
      applies_to_scope: 'ALL',
      min_ppv_pool: 200,
      min_bump_pool: 50,
      is_active: false  // Inactive to avoid affecting production
    }];

    const result = syncRestrictionsToBigQuery(testRestrictions);

    if (!result.success) {
      throw new Error('MERGE failed');
    }

    Logger.log('Sync test: OK');
  }
  ```

- [ ] **Integration Test with Real Data**
  1. Create test creator in Sheets
  2. Add test restrictions
  3. Run sync function
  4. Verify data in BigQuery:
     ```sql
     SELECT * FROM `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`
     WHERE page_name = 'test_creator_apps_script'
     ORDER BY updated_at DESC
     LIMIT 1;
     ```
  5. Clean up test data:
     ```sql
     DELETE FROM `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`
     WHERE page_name = 'test_creator_apps_script' AND is_active = FALSE;
     ```

---

## Troubleshooting Guide

### Issue: "BigQuery is not defined"

**Cause**: Advanced BigQuery service not enabled in Apps Script.

**Fix**:
1. Go to Apps Script Editor
2. Click Services (+ icon)
3. Add "BigQuery API"
4. Verify "BigQuery" appears under Services

---

### Issue: "Exception: Request failed... insufficient authentication scopes"

**Cause**: Missing OAuth scope `https://www.googleapis.com/auth/bigquery` in manifest.

**Fix**:
1. Open `appsscript.json`
2. Add BigQuery scope to `oauthScopes` array
3. Save and re-authorize script

---

### Issue: "Access Denied: BigQuery BigQuery: Permission bigquery.jobs.create denied"

**Cause**: Service account lacks `bigquery.jobUser` role.

**Fix**: See IAM configuration in `/Users/kylemerriman/Desktop/active_creators_scheduler/docs/IAM_CONFIGURATION.md`

---

### Issue: "Table not found: of-scheduler-proj:eros_scheduling_brain.creator_caption_restrictions"

**Cause**: Tables not deployed to BigQuery.

**Fix**:
```bash
cd /Users/kylemerriman/Desktop/active_creators_scheduler
./scripts/bq_deploy.sh
```

---

## Success Criteria

All items checked off in checklist above, and:

- [ ] Apps Script can query `active_creator_caption_restrictions_v` without errors
- [ ] Apps Script can MERGE data to `creator_caption_restrictions` table
- [ ] Apps Script can MERGE data to `creator_allowed_profile` table
- [ ] Apps Script can query `feature_flags` table
- [ ] Error handling gracefully catches and logs BigQuery exceptions
- [ ] OAuth consent flow completes successfully for all users
- [ ] Service account has minimal required permissions (principle of least privilege)

---

## References

- [Apps Script BigQuery Quickstart](https://developers.google.com/apps-script/advanced/bigquery)
- [Apps Script OAuth Scopes](https://developers.google.com/apps-script/guides/services/authorization)
- [BigQuery API Reference](https://developers.google.com/apps-script/advanced/bigquery#query)
- [IAM Configuration Guide](/Users/kylemerriman/Desktop/active_creators_scheduler/docs/IAM_CONFIGURATION.md)
