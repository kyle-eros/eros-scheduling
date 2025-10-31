/**
 * ═══════════════════════════════════════════════════════════════════════════
 * MASTER CONTROL PANEL - SCHEDULE IMPORT SYSTEM v2.5 (Mass Messages Only)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * PURPOSE
 * Import AI-generated schedule templates from BigQuery into each creator's
 * Google Sheet, using a JSON-envelope storage model in BigQuery:
 *   schedule_recommendations.recommendation_data -> { "messages": [...] }
 *
 * WHAT THIS SCRIPT DOES
 * • Preview schedule (read-only)
 * • Import schedule (single or batch)
 * • Validate data, back up sheet, write messages, verify, and update status
 * • Log operations to a "Import Logs" sheet (JSON)
 * • Cache preview/exists checks to reduce BQ calls
 * • Retry BQ queries with exponential backoff
 *
 * DATASET CONTRACT (CANONICAL)
 * • Project:  of-scheduler-proj
 * • Dataset:  eros_scheduling_brain
 * • Table:    schedule_recommendations  (JSON envelope)
 *   - Key scope for this workflow:   page_name + schedule_id
 *   - recommendation_data.messages:  array of message objects (send_at, message_type, caption, etc.)
 *
 * SHEETS CONTRACT
 * • Master Control panel sheet: "Active creators"
 *   - Column A: Creator Name (display)
 *   - Column B: Sheet URL
 *   - Column C: Status (auto updated)
 * • Per-creator target sheet tab name: "Schedule #1A" (by default)
 * • Optional config sheet: "⚙️ Configuration"
 *
 * VERSION: 2.5
 * LAST UPDATED: 2025-10-31
 * ═══════════════════════════════════════════════════════════════════════════
 */

/* =============================================================================
 * CONFIGURATION
 * ========================================================================== */
const CONFIG = {
  bigquery: {
    projectId: 'of-scheduler-proj',
    datasetId: 'eros_scheduling_brain',
    tableId:   'schedule_recommendations',
    viewId:    'latest_recommendations'
  },

  schedule: {
    defaultTemplateId: '1A',
    maxMessages: 20
  },

  sheets: {
    controlPanel: 'Active creators',
    config:       '⚙️ Configuration',
    logging:      'Import Logs'
  },

  sheetRows: {
    mmScheduleStart: 3
  },

  import: {
    batchDelayMs: 500,
    queryTimeoutSeconds: 30,
    maxBqRetries: 3
  },

  status: {
    pending:   'pending',
    importing: 'importing',
    imported:  'imported',
    failed:    'failed',
    archived:  'archived'
  }
};

/* =============================================================================
 * MENU
 * ========================================================================== */

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('🤖 AI Schedules')
    .addItem('📥 Import Schedule (Single Creator)', 'importSingleCreatorSchedule')
    .addItem('👁️ Preview Schedule (No Import)', 'previewSchedule')
    .addSeparator()
    .addItem('📦 Import All Available Schedules', 'importAllCreatorSchedules')
    .addSeparator()
    .addItem('🔍 Check Available Recommendations', 'checkAvailableRecommendations')
    .addItem('📊 View Import Status', 'viewImportStatus')
    .addItem('🧪 Test BigQuery Connection', 'testBigQueryConnection')
    .addSeparator()
    .addItem('❓ Help & Troubleshooting', 'showHelp')
    .addToUi();
}

/* =============================================================================
 * PLACEHOLDER FUNCTIONS
 * ========================================================================== */

function importSingleCreatorSchedule() {
  SpreadsheetApp.getUi().alert('Placeholder: importSingleCreatorSchedule');
}

function previewSchedule() {
  SpreadsheetApp.getUi().alert('Placeholder: previewSchedule');
}

function importAllCreatorSchedules() {
  SpreadsheetApp.getUi().alert('Placeholder: importAllCreatorSchedules');
}

function checkAvailableRecommendations() {
  SpreadsheetApp.getUi().alert('Placeholder: checkAvailableRecommendations');
}

function viewImportStatus() {
  SpreadsheetApp.getUi().alert('Placeholder: viewImportStatus');
}

function testBigQueryConnection() {
  SpreadsheetApp.getUi().alert('Placeholder: testBigQueryConnection');
}

function showHelp() {
  const msg =
`🤖 AI SCHEDULE IMPORT SYSTEM – HELP

PREREQUISITES
• Column A: Creator Name (display)
• Column B: Google Sheet URL
• Target tab exists: "Schedule #1A"
• BigQuery API enabled (Advanced Services)

WORKFLOW
1) Select a creator row in "Active creators"
2) Use "👁️ Preview Schedule" to inspect content
3) Use "📥 Import Schedule" to write to the sheet
4) Check Column C for status`;

  SpreadsheetApp.getUi().alert('❓ Help & Troubleshooting', msg, SpreadsheetApp.getUi().ButtonSet.OK);
}
