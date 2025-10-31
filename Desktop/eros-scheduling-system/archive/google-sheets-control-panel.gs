/**
 * ═══════════════════════════════════════════════════════════════════════════
 * MASTER CONTROL PANEL - SCHEDULE IMPORT SYSTEM v2.5 (Mass Messages Only)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * PURPOSE
 * Import AI-generated schedule templates from BigQuery into each creator’s
 * Google Sheet, using a JSON-envelope storage model in BigQuery:
 *   schedule_recommendations.recommendation_data -> { "messages": [...] }
 *
 * WHAT THIS SCRIPT DOES
 * • Preview schedule (read-only)
 * • Import schedule (single or batch)
 * • Validate data, back up sheet, write messages, verify, and update status
 * • Log operations to a “Import Logs” sheet (JSON)
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
 * • Master Control panel sheet: “Active creators”
 *   - Column A: Creator Name (display)
 *   - Column B: Sheet URL
 *   - Column C: Status (auto updated)
 * • Per-creator target sheet tab name: “Schedule #1A” (by default)
 * • Optional config sheet: “⚙️ Configuration”
 *
 * VERSION: 2.5
 * LAST UPDATED: 2025-10-29
 * ═══════════════════════════════════════════════════════════════════════════
 */

/* =============================================================================
 * CONFIGURATION
 * ========================================================================== */
const CONFIG = {
  bigquery: {
    projectId: 'of-scheduler-proj',
    datasetId: 'eros_scheduling_brain',
    tableId:   'schedule_recommendations',  // JSON envelope table
    viewId:    'latest_recommendations'     // analytics view (read-only)
  },

  schedule: {
    defaultTemplateId: '1A',  // forms "#1A"
    maxMessages: 20
  },

  sheets: {
    controlPanel: 'Active creators',
    config:       '⚙️ Configuration',
    logging:      'Import Logs'
  },

  sheetRows: {
    // First row where message grid begins: B3:H (7 cols) = message_type..recommended_price
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
 * UTILITY CLASSES
 * ========================================================================== */

/** Lightweight structured logger that can persist logs to a sheet. */
class ImportLogger {
  constructor(operation) {
    this.operation = operation;
    this.logs = [];
    this.startTime = new Date();
  }
  log(level, message, data = {}) {
    const entry = {
      ts: new Date().toISOString(),
      level: (level || 'INFO').toUpperCase(),
      message: String(message || ''),
      data
    };
    this.logs.push(entry);
    try {
      const inline = Object.keys(data).length ? ` | data=${JSON.stringify(data)}` : '';
      Logger.log(`[${this.operation}] [${entry.level}] ${entry.message}${inline}`);
    } catch (_) {}
  }
  getSummary() {
    return {
      operation: this.operation,
      durationMs: Date.now() - this.startTime.getTime(),
      errors: this.logs.filter(l => l.level === 'ERROR').length,
      warnings: this.logs.filter(l => l.level === 'WARNING').length,
      total: this.logs.length
    };
  }
  persist() {
    try {
      const ss = SpreadsheetApp.getActiveSpreadsheet();
      let sheet = ss.getSheetByName(CONFIG.sheets.logging);
      if (!sheet) {
        sheet = ss.insertSheet(CONFIG.sheets.logging);
        sheet.appendRow(['Operation', 'When', 'Duration (ms)', 'Errors', 'Warnings', 'Log JSON']);
        sheet.setColumnWidth(6, 600);
      }
      const s = this.getSummary();
      sheet.appendRow([
        s.operation,
        new Date().toISOString(),
        s.durationMs,
        s.errors,
        s.warnings,
        JSON.stringify(this.logs, null, 2)
      ]);
    } catch (e) {
      Logger.log(`Log persist error: ${e.message}`);
    }
  }
}

/** Simple script cache wrapper for preview/existence checks. */
class CacheManager {
  static get(key) {
    const raw = CacheService.getScriptCache().get(key);
    return raw ? JSON.parse(raw) : null;
  }
  static set(key, val, seconds = 600) {
    CacheService.getScriptCache().put(key, JSON.stringify(val), seconds);
  }
  static remove(key) {
    CacheService.getScriptCache().remove(key);
  }
}

/* =============================================================================
 * HELPERS: normalization, time, validation
 * ========================================================================== */

/** Normalize display name "Jade Bri" → "jadebri" (lowercase alnum only). */
function normalizePageName(name) {
  return (name || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
}

/** Convert ISO timestamp → "h:mm a" in America/Los_Angeles (or return ''). */
function toTimePST(isoStr) {
  if (!isoStr) return '';
  try {
    const d = new Date(isoStr);
    if (isNaN(d.getTime())) return '';
    return Utilities.formatDate(d, 'America/Los_Angeles', 'h:mm a');
  } catch (e) {
    Logger.log(`toTimePST error: ${e.message}`);
    return '';
  }
}

/** Validate message array; return {errors, warnings, isValid}. */
function validateScheduleData(messages) {
  const errors = [];
  const warnings = [];
  const validTypes = ['Unlock', 'Follow up', 'Photo bump'];
  (messages || []).forEach((m, i) => {
    if (!m.message_type) errors.push(`Message ${i + 1}: missing message_type`);
    if (!m.send_at && !m.time_pst) errors.push(`Message ${i + 1}: missing time (send_at/time_pst)`);
    if (m.message_type && !validTypes.includes(m.message_type)) {
      warnings.push(`Message ${i + 1}: unexpected type "${m.message_type}"`);
    }
  });
  return { errors, warnings, isValid: errors.length === 0 };
}

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
 * CONTROL-PANEL HELPERS
 * ========================================================================== */

/**
 * Read the selected row from “Active creators”, validate inputs.
 * Returns {creatorName, sheetUrl, activeRow, activeSheet} or null.
 */
function getActiveCreatorRow() {
  const ui = SpreadsheetApp.getUi();
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getActiveSheet();
  if (sheet.getName() !== CONFIG.sheets.controlPanel) {
    ui.alert('⚠️ Wrong Sheet', `Please switch to "${CONFIG.sheets.controlPanel}" and select a row.`, ui.ButtonSet.OK);
    return null;
  }
  const r = sheet.getActiveRange().getRow();
  if (r < 2) {
    ui.alert('⚠️ Invalid Selection', 'Please select a creator row (not the header).', ui.ButtonSet.OK);
    return null;
  }
  const creatorName = sheet.getRange(r, 1).getValue();
  const sheetUrl    = sheet.getRange(r, 2).getValue();
  if (!creatorName || !sheetUrl) {
    ui.alert('⚠️ Missing Data', 'Column A must have Creator Name; Column B must have Sheet URL.', ui.ButtonSet.OK);
    return null;
  }
  if (!String(sheetUrl).includes('docs.google.com/spreadsheets')) {
    ui.alert('⚠️ Invalid URL', 'The Sheet URL in Column B appears invalid.', ui.ButtonSet.OK);
    return null;
  }
  return { creatorName, sheetUrl, activeRow: r, activeSheet: sheet };
}

/* =============================================================================
 * SINGLE IMPORT
 * ========================================================================== */

function importSingleCreatorSchedule() {
  const logger = new ImportLogger('importSingleCreatorSchedule');
  const ui = SpreadsheetApp.getUi();
  const ctx = getActiveCreatorRow();
  if (!ctx) return;

  const { creatorName, sheetUrl, activeRow, activeSheet } = ctx;
  const scheduleId = `#${CONFIG.schedule.defaultTemplateId}`;

  try {
    // Check availability
    const exists = checkRecommendationExists(creatorName, scheduleId);
    if (!exists.exists) {
      logger.log('WARNING', 'No pending schedule found.', { creatorName, scheduleId });
      ui.alert('❌ No Schedule Found',
        `No pending AI schedule found for "${creatorName}" (ID ${scheduleId}).`,
        ui.ButtonSet.OK);
      return;
    }

    // Confirm
    const resp = ui.alert(
      '📋 Import Confirmation',
      `Import AI schedule for "${creatorName}"?\n\n` +
      `Schedule: ${scheduleId}\n` +
      `Confidence: ${Math.round(exists.confidence * 100)}%\n` +
      `Messages: ${exists.messageCount}\n` +
      `Generated: ${exists.generatedDate}\n\n` +
      `This will update their "Schedule ${scheduleId}" tab.`,
      ui.ButtonSet.YES_NO
    );
    if (resp !== ui.Button.YES) return;

    // Mark importing
    activeSheet.getRange(activeRow, 3).setValue('⏳ Importing...');
    SpreadsheetApp.flush();

    const result = performScheduleImport(creatorName, sheetUrl, scheduleId, logger);

    if (result.success) {
      const ts = Utilities.formatDate(new Date(), 'America/Los_Angeles', 'MM/dd/yyyy HH:mm');
      activeSheet.getRange(activeRow, 3).setValue(`✅ Imported ${ts}`);

      ui.alert('✅ Import Successful!',
        `Schedule imported for ${creatorName}\n\n` +
        `Messages: ${result.messagesImported}\n` +
        `Confidence: ${Math.round(result.confidence * 100)}%`,
        ui.ButtonSet.OK);

      updateScheduleStatus(creatorName, scheduleId, CONFIG.status.imported,
        `Imported successfully: ${result.messagesImported} messages`);
    } else {
      activeSheet.getRange(activeRow, 3).setValue(`❌ Failed: ${result.error}`);
      ui.alert('❌ Import Failed',
        `Could not import schedule for ${creatorName}\n\nError: ${result.error}\n` +
        `${result.troubleshooting || 'Check logs for details.'}`,
        ui.ButtonSet.OK);
      updateScheduleStatus(creatorName, scheduleId, CONFIG.status.failed, result.error);
    }
  } catch (e) {
    activeSheet.getRange(activeRow, 3).setValue(`❌ Error: ${e.message}`);
    logger.log('ERROR', 'Unexpected error', { creatorName, error: e.message, stack: e.stack });
    ui.alert('❌ Unexpected Error', `${e.message}`, ui.ButtonSet.OK);
  } finally {
    logger.persist();
  }
}

/* =============================================================================
 * PREVIEW
 * ========================================================================== */

function previewSchedule() {
  const logger = new ImportLogger('previewSchedule');
  const ui = SpreadsheetApp.getUi();
  const ctx = getActiveCreatorRow();
  if (!ctx) return;

  const { creatorName } = ctx;
  const scheduleId = `#${CONFIG.schedule.defaultTemplateId}`;

  try {
    const p = getSchedulePreview(creatorName, scheduleId);
    if (!p.success) {
      logger.log('WARNING', 'Preview not available', { creatorName, error: p.error });
      ui.alert('❌ Preview Not Available', p.error || 'Could not load preview.', ui.ButtonSet.OK);
      return;
    }

    let msg = `📋 Schedule Preview for ${creatorName}\n\n` +
              `Schedule: ${scheduleId}\n` +
              `Generated: ${p.generatedDate}\n` +
              `Confidence: ${Math.round(p.confidence * 100)}%\n` +
              `Status: ${p.status}\n\n` +
              `📊 Summary:\n` +
              `• Total Messages: ${p.messageCount}\n` +
              `• First Message: ${p.firstMessageTime}\n\n`;

    if (p.messages && p.messages.length) {
      msg += `📝 First 3 Messages:\n`;
      p.messages.slice(0, 3).forEach((m, i) => {
        const cap = String(m.caption || '');
        msg += `\n${i + 1}. ${m.message_type || ''} at ${m.time_pst || ''}\n` +
               `   Caption: ${cap.substring(0, 50)}${cap.length > 50 ? '...' : ''}\n`;
      });
    }

    ui.alert('👁️ Schedule Preview', msg, ui.ButtonSet.OK);
  } catch (e) {
    logger.log('ERROR', 'Preview failed', { creatorName, error: e.message, stack: e.stack });
    ui.alert('❌ Error', `Could not preview: ${e.message}`, ui.ButtonSet.OK);
  } finally {
    logger.persist();
  }
}

/* =============================================================================
 * BATCH IMPORT
 * ========================================================================== */

function importAllCreatorSchedules() {
  const logger = new ImportLogger('importAllCreatorSchedules');
  const ui = SpreadsheetApp.getUi();
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const control = ss.getSheetByName(CONFIG.sheets.controlPanel);
  if (!control) {
    ui.alert('❌ Error', `"${CONFIG.sheets.controlPanel}" sheet not found.`, ui.ButtonSet.OK);
    return;
  }

  const rows = control.getRange('A2:C').getValues().filter(r => r[0] && r[1]);
  if (!rows.length) {
    ui.alert('❌ Error', `No creators found in "${CONFIG.sheets.controlPanel}".`, ui.ButtonSet.OK);
    return;
  }

  const ans = ui.alert('📦 Batch Import',
    `Import AI schedules for all ${rows.length} creators?\n\n` +
    `This will check each creator for a pending schedule and import it.`,
    ui.ButtonSet.YES_NO);
  if (ans !== ui.Button.YES) return;

  const scheduleId = `#${CONFIG.schedule.defaultTemplateId}`;
  let ok = 0, fail = 0, skip = 0;

  for (let i = 0; i < rows.length; i++) {
    const creatorName = rows[i][0];
    const sheetUrl    = rows[i][1];
    const rowIndex    = i + 2; // sheet row

    try {
      control.getRange(rowIndex, 3).setValue('🔍 Checking...');
      if (i % 5 === 0) SpreadsheetApp.flush();

      const exists = checkRecommendationExists(creatorName, scheduleId);
      if (!exists.exists) {
        control.getRange(rowIndex, 3).setValue('⏭️ No recommendation');
        skip++;
        continue;
      }

      control.getRange(rowIndex, 3).setValue('⏳ Importing...');
      SpreadsheetApp.flush();

      const result = performScheduleImport(creatorName, sheetUrl, scheduleId, logger);
      if (result.success) {
        const ts = Utilities.formatDate(new Date(), 'America/Los_Angeles', 'MM/dd HH:mm');
        control.getRange(rowIndex, 3).setValue(`✅ Imported ${ts}`);
        ok++;
        updateScheduleStatus(creatorName, scheduleId, CONFIG.status.imported,
          `Batch import: ${result.messagesImported} messages`);
      } else {
        control.getRange(rowIndex, 3).setValue('❌ Failed');
        fail++;
        updateScheduleStatus(creatorName, scheduleId, CONFIG.status.failed, result.error || 'Import failed');
      }
      Utilities.sleep(CONFIG.import.batchDelayMs);
    } catch (e) {
      control.getRange(rowIndex, 3).setValue(`❌ Error: ${e.message}`);
      fail++;
    }
  }

  ui.alert('📦 Batch Import Complete',
    `✅ Imported: ${ok}\n⏭️ Skipped: ${skip}\n❌ Failed: ${fail}\nTotal: ${rows.length}`,
    ui.ButtonSet.OK);

  logger.log('INFO', 'Batch done', { imported: ok, skipped: skip, failed: fail, total: rows.length });
  logger.persist();
}

/* =============================================================================
 * CORE IMPORT LOGIC
 * ========================================================================== */

function performScheduleImport(creatorName, sheetUrl, scheduleId, logger) {
  logger = logger || new ImportLogger('performScheduleImport');
  let backup = null, scheduleSheet = null;

  try {
    const rec = fetchRecommendation(creatorName, scheduleId);
    if (!rec) {
      return { success: false, error: 'No recommendation found in BigQuery', troubleshooting: 'Check status="pending" and schedule_id.' };
    }

    // Parse the JSON envelope { messages: [...] }
    let envelope;
    try {
      envelope = typeof rec.recommendation_data === 'string'
        ? JSON.parse(rec.recommendation_data)
        : rec.recommendation_data;
    } catch (e) {
      return { success: false, error: 'Invalid JSON in recommendation_data', troubleshooting: 'Data is corrupted.' };
    }

    const baseMsgs = Array.isArray(envelope.messages) ? envelope.messages : [];
    if (baseMsgs.length === 0) {
      return { success: false, error: 'No messages found in schedule', troubleshooting: 'Envelope has no "messages" array.' };
    }

    // Validation warnings/errors
    const val = validateScheduleData(baseMsgs);
    if (!val.isValid) {
      return { success: false, error: `Invalid schedule data: ${val.errors.join('; ')}` };
    }
    if (val.warnings.length) logger.log('WARNING', 'Schedule data warnings', { warnings: val.warnings });

    // Open target sheet & backup
    const ss = SpreadsheetApp.openByUrl(sheetUrl);
    scheduleSheet = ss.getSheetByName(`Schedule ${scheduleId}`);
    if (!scheduleSheet) {
      return { success: false, error: `Schedule ${scheduleId} tab not found`, troubleshooting: 'Create the tab or check naming.' };
    }
    backup = captureSheetBackup(scheduleSheet);

    // Normalize messages for sheet (derive time_pst etc.)
    const normalized = normalizeMMSchedule(baseMsgs);
    const imported = importMMScheduleToSheet(scheduleSheet, normalized);

    // Optional configuration
    const configSheet = ss.getSheetByName(CONFIG.sheets.config);
    if (configSheet && envelope.configuration_recommendations) {
      updateConfigurationSheet(configSheet, envelope.configuration_recommendations);
    }

    // Verify
    const verify = verifyImport(scheduleSheet, normalized.length);
    if (!verify.success) {
      restoreFromBackup(scheduleSheet, backup);
      return { success: false, error: verify.error || 'Verification failed; rolled back.' };
    }

    return {
      success: true,
      messagesImported: imported,
      confidence: rec.confidence_score || 0.85
    };

  } catch (e) {
    logger.log('ERROR', 'Unexpected import error', { error: e.message, stack: e.stack });
    if (scheduleSheet && backup) {
      restoreFromBackup(scheduleSheet, backup);
      logger.log('INFO', 'Rolled back changes due to error.');
    }
    return { success: false, error: e.message, troubleshooting: 'Unexpected error; see logs.' };
  }
}

/** Normalize Mass Message rows: derive time_pst, standardize fields. */
function normalizeMMSchedule(messages) {
  return (messages || []).map(m => {
    const out = Object.assign({}, m);
    out.time_pst = out.time_pst || toTimePST(out.send_at);
    if (!out.schedule_type) out.schedule_type = 'Mass Message';

    const type = String(out.message_type || '').toLowerCase();
    if (type === 'photo bump') {
      out.recommended_price = '.';
    } else if (type === 'follow up' || type === 'followup') {
      out.message_type = 'Follow up';
      out.recommended_price = '';
    } else if (type === 'unlock') {
      if (typeof out.recommended_price === 'string' && out.recommended_price && !out.recommended_price.startsWith('$')) {
        const digits = out.recommended_price.replace(/[^0-9.]/g, '');
        out.recommended_price = digits ? ('$' + digits) : '';
      }
    }
    out.caption         = (out.caption || '').toString();
    out.caption_guide   = (out.caption_guide == null ? '.' : out.caption_guide);
    out.content_preview = out.content_preview || '';
    out.paywall_content = out.paywall_content || '';
    out.tag             = out.tag || '';
    return out;
  });
}

/** Write messages grid into the sheet and decorate cells. */
function importMMScheduleToSheet(sheet, messages) {
  const startRow = CONFIG.sheetRows.mmScheduleStart;
  const maxRows  = CONFIG.schedule.maxMessages;
  const numCols  = 7; // message_type..recommended_price

  // Clear
  sheet.getRange(startRow, 2, maxRows, numCols).clearContent().clearFormat();

  const take = Math.min((messages || []).length, maxRows);
  const rows = [];
  for (let i = 0; i < take; i++) {
    const m = messages[i] || {};
    rows.push([
      m.message_type || '',
      m.time_pst || '',
      m.content_preview || '',
      m.paywall_content || '',
      m.caption || '',
      m.caption_guide || '.',
      m.recommended_price || ''
    ]);
  }

  if (rows.length) {
    sheet.getRange(startRow, 2, rows.length, numCols).setValues(rows);
  }

  // Simple color coding & caption notes
  for (let i = 0; i < take; i++) {
    const m = messages[i] || {};
    const r = startRow + i;
    let color = null;
    if (m.message_type === 'Unlock')      color = '#FFF9C4';
    else if (m.message_type === 'Follow up')  color = '#E1F5FE';
    else if (m.message_type === 'Photo bump') color = '#F1F8E9';
    if (color) sheet.getRange(r, 2, 1, numCols).setBackground(color);

    if (m.caption) {
      const note = `AI-Generated Caption\nConfidence: ${Math.round(100 * (m.confidence_score || 0.85))}%`;
      sheet.getRange(r, 6).setNote(note);
    }
  }

  return rows.length;
}

/** Update optional config sheet with knobs from envelope. */
function updateConfigurationSheet(configSheet, rec) {
  try {
    if (!rec) return;
    if (rec.flyer_drop_down)      configSheet.getRange('C6').setValue(rec.flyer_drop_down);
    if (rec.mm_sext_reference)    configSheet.getRange('C7').setValue(rec.mm_sext_reference);
    if (rec.pricing_drop_down)    configSheet.getRange('C10').setValue(rec.pricing_drop_down);
    const ts = Utilities.formatDate(new Date(), 'America/Los_Angeles', 'yyyy-MM-dd HH:mm:ss');
    configSheet.getRange('C12').setValue(`Last AI Import: ${ts}`);
  } catch (e) {
    Logger.log(`Config update warning: ${e.message}`);
  }
}

/** Capture a backup of the message grid. */
function captureSheetBackup(sheet) {
  try {
    const r = sheet.getRange(CONFIG.sheetRows.mmScheduleStart, 2, CONFIG.schedule.maxMessages, 7);
    return { values: r.getValues(), formats: r.getBackgrounds(), notes: r.getNotes() };
  } catch (e) {
    Logger.log(`Backup warning: ${e.message}`);
    return null;
  }
}

/** Restore a backup if verification fails. */
function restoreFromBackup(sheet, backup) {
  if (!backup) return;
  try {
    const r = sheet.getRange(CONFIG.sheetRows.mmScheduleStart, 2, CONFIG.schedule.maxMessages, 7);
    r.setValues(backup.values);
    r.setBackgrounds(backup.formats);
    r.setNotes(backup.notes);
  } catch (e) {
    Logger.log(`Restore warning: ${e.message}`);
  }
}

/** Verify that at least ~80% of expected rows landed. */
function verifyImport(sheet, expectedCount) {
  try {
    const r = sheet.getRange(CONFIG.sheetRows.mmScheduleStart, 2, CONFIG.schedule.maxMessages, 7).getValues();
    let actual = 0;
    for (let i = 0; i < r.length; i++) {
      // treat “has message” if column B or C filled (type or time)
      if (r[i][0] || r[i][1]) actual++;
      else break;
    }
    if (expectedCount > 0 && actual === 0) {
      return { success: false, error: 'No data was written to the sheet.' };
    }
    if (expectedCount > 0 && actual < Math.floor(0.8 * expectedCount)) {
      Logger.log(`Verify warning: only ${actual}/${expectedCount} messages imported`);
    }
    return { success: true };
  } catch (e) {
    return { success: false, error: `Verification failed: ${e.message}` };
  }
}

/* =============================================================================
 * BIGQUERY HELPERS
 * ========================================================================== */

/** Run a BigQuery query with retries & timeout. */
function executeQueryWithRetry(request, maxRetries) {
  const retries = (typeof maxRetries === 'number' ? maxRetries : CONFIG.import.maxBqRetries) || 3;
  const req = Object.assign({}, request);
  req.timeoutMs = (CONFIG.import.queryTimeoutSeconds || 30) * 1000;
  let lastErr;
  for (let i = 1; i <= retries; i++) {
    try {
      return BigQuery.Jobs.query(req, CONFIG.bigquery.projectId);
    } catch (e) {
      lastErr = e;
      Logger.log(`BQ query attempt ${i} failed: ${e.message}`);
      if (i < retries) Utilities.sleep(Math.pow(2, i - 1) * 1000); // 1s, 2s, 4s
    }
  }
  throw new Error(`BigQuery query failed after ${retries} attempts: ${lastErr && lastErr.message}`);
}

/** Fetch the newest pending recommendation for (page_name, schedule_id). */
function fetchRecommendation(creatorName, scheduleId) {
  const pageName = normalizePageName(creatorName);
  const fq = CONFIG.bigquery.projectId + '.' + CONFIG.bigquery.datasetId + '.' + CONFIG.bigquery.tableId;
  const query =
    'SELECT recommendation_data, confidence_score, generated_at, status ' +
    'FROM `' + fq + '` ' +
    'WHERE page_name = @pageName AND schedule_id = @scheduleId AND status = @status ' +
    'ORDER BY generated_at DESC LIMIT 1';

  const request = {
    query: query,
    useLegacySql: false,
    parameterMode: 'NAMED',
    queryParameters: [
      { name: 'pageName',   parameterType: { type: 'STRING' }, parameterValue: { value: pageName } },
      { name: 'scheduleId', parameterType: { type: 'STRING' }, parameterValue: { value: scheduleId } },
      { name: 'status',     parameterType: { type: 'STRING' }, parameterValue: { value: CONFIG.status.pending } }
    ]
  };

  const r = executeQueryWithRetry(request);
  if (!r.rows || !r.rows.length) return null;
  const f = r.rows[0].f;
  return {
    recommendation_data: f[0].v,
    confidence_score: parseFloat(f[1].v || '0'),
    generated_at: f[2].v,
    status: f[3].v
  };
}

/** Return {exists, confidence, messageCount, generatedDate}. Cached. */
function checkRecommendationExists(creatorName, scheduleId) {
  const pageName = normalizePageName(creatorName);
  const cacheKey = `${CONFIG.bigquery.projectId}_rec_exists_${pageName}_${scheduleId}`;
  const cached = CacheManager.get(cacheKey);
  if (cached) return cached;

  const fq = CONFIG.bigquery.projectId + '.' + CONFIG.bigquery.datasetId + '.' + CONFIG.bigquery.tableId;
  const query =
    'SELECT COUNT(*) AS c, MAX(confidence_score) AS conf, ' +
    "MAX(ARRAY_LENGTH(JSON_EXTRACT_ARRAY(recommendation_data, '$.messages'))) AS msgc, " +
    "FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(generated_at), 'America/Los_Angeles') AS gen " +
    'FROM `' + fq + '` ' +
    'WHERE page_name = @pageName AND schedule_id = @scheduleId AND status = @status';

  const request = {
    query: query, useLegacySql: false, parameterMode: 'NAMED',
    queryParameters: [
      { name: 'pageName',   parameterType: { type: 'STRING' }, parameterValue: { value: pageName } },
      { name: 'scheduleId', parameterType: { type: 'STRING' }, parameterValue: { value: scheduleId } },
      { name: 'status',     parameterType: { type: 'STRING' }, parameterValue: { value: CONFIG.status.pending } }
    ]
  };

  try {
    const r = executeQueryWithRetry(request);
    const row = r.rows && r.rows[0] && r.rows[0].f;
    const exists = row ? parseInt(row[0].v || '0', 10) > 0 : false;
    const result = {
      exists: exists,
      confidence: row && row[1].v ? parseFloat(row[1].v) : 0,
      messageCount: row && row[2].v ? parseInt(row[2].v, 10) : 0,
      generatedDate: (row && row[3].v) || 'Unknown'
    };
    CacheManager.set(cacheKey, result);
    return result;
  } catch (e) {
    Logger.log(`checkRecommendationExists error: ${e.message}`);
    return { exists: false, confidence: 0, messageCount: 0, generatedDate: 'Unknown' };
  }
}

/** Update status in schedule_recommendations (DML UPDATE in BQ). */
function updateScheduleStatus(creatorName, scheduleId, status, notes) {
  const pageName = normalizePageName(creatorName);
  const fq = CONFIG.bigquery.projectId + '.' + CONFIG.bigquery.datasetId + '.' + CONFIG.bigquery.tableId;
  const query =
    'UPDATE `' + fq + '` ' +
    'SET status = @status, import_result = @notes, imported_at = CURRENT_TIMESTAMP(), updated_at = CURRENT_TIMESTAMP() ' +
    'WHERE page_name = @pageName AND schedule_id = @scheduleId AND status = @oldStatus';

  const request = {
    query: query, useLegacySql: false, parameterMode: 'NAMED',
    queryParameters: [
      { name: 'status',     parameterType: { type: 'STRING' }, parameterValue: { value: status } },
      { name: 'notes',      parameterType: { type: 'STRING' }, parameterValue: { value: notes || '' } },
      { name: 'pageName',   parameterType: { type: 'STRING' }, parameterValue: { value: pageName } },
      { name: 'scheduleId', parameterType: { type: 'STRING' }, parameterValue: { value: scheduleId } },
      { name: 'oldStatus',  parameterType: { type: 'STRING' }, parameterValue: { value: CONFIG.status.pending } }
    ]
  };

  try {
    executeQueryWithRetry(request);
    CacheManager.remove(`${CONFIG.bigquery.projectId}_rec_exists_${pageName}_${scheduleId}`);
    CacheManager.remove(`${CONFIG.bigquery.projectId}_rec_preview_${pageName}_${scheduleId}`);
  } catch (e) {
    Logger.log(`Status update warning: ${e.message}`);
  }
}

/** Build preview object {success, messages[], messageCount,...}. Cached. */
function getSchedulePreview(creatorName, scheduleId) {
  const pageName = normalizePageName(creatorName);
  const cacheKey = `${CONFIG.bigquery.projectId}_rec_preview_${pageName}_${scheduleId}`;
  const cached = CacheManager.get(cacheKey);
  if (cached) return cached;

  try {
    const rec = fetchRecommendation(creatorName, scheduleId);
    if (!rec) return { success: false, error: `No pending schedule found for ${creatorName}` };

    const data = JSON.parse(rec.recommendation_data || '{}');
    let messages = Array.isArray(data.messages) ? data.messages : [];
    messages = messages.map(m => Object.assign({}, m, { time_pst: m.time_pst || toTimePST(m.send_at) }));

    const result = {
      success: true,
      messages: messages,
      messageCount: messages.length,
      firstMessageTime: messages.length ? (messages[0].time_pst || 'N/A') : 'N/A',
      confidence: rec.confidence_score,
      generatedDate: Utilities.formatDate(new Date(rec.generated_at), 'America/Los_Angeles', 'yyyy-MM-dd HH:mm'),
      status: rec.status
    };
    CacheManager.set(cacheKey, result);
    return result;
  } catch (e) {
    return { success: false, error: e.message };
  }
}

/* =============================================================================
 * STATUS & DIAGNOSTICS
 * ========================================================================== */

function checkAvailableRecommendations() {
  const ui = SpreadsheetApp.getUi();
  const fq = CONFIG.bigquery.projectId + '.' + CONFIG.bigquery.datasetId + '.' + CONFIG.bigquery.tableId;
  const query =
    'SELECT page_name, schedule_id, ' +
    "FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', generated_at, 'America/Los_Angeles') AS generated, " +
    'ROUND(confidence_score * 100) AS confidence, status, ' +
    "FORMAT_TIMESTAMP('%I:%M %p', TIMESTAMP(JSON_VALUE(recommendation_data, '$.messages[0].send_at')), 'America/Los_Angeles') AS first_message_time, " +
    "ARRAY_LENGTH(JSON_EXTRACT_ARRAY(recommendation_data, '$.messages')) AS message_count " +
    'FROM `' + fq + '` ' +
    "WHERE status IN ('pending','importing') " +
    'ORDER BY generated_at DESC LIMIT 20';

  try {
    const r = executeQueryWithRetry({ query: query, useLegacySql: false });
    if (!r.rows || !r.rows.length) {
      ui.alert('📭 No Pending Schedules', 'No AI schedules with status="pending" found in BigQuery.', ui.ButtonSet.OK);
      return;
    }
    let msg = `📋 Available AI Schedules (${r.rows.length}):\n\n`;
    r.rows.forEach(rowObj => {
      const f = rowObj.f;
      const page   = f[0].v;
      const sched  = f[1].v;
      const gen    = f[2].v;
      const conf   = f[3].v;
      const stat   = f[4].v;
      const first  = f[5].v || 'N/A';
      const count  = f[6].v || '0';
      msg += `• ${page}\n  Schedule: ${sched} | ${count} msgs | ${conf}%\n  Status: ${stat} | Generated: ${gen}\n  First msg: ${first}\n\n`;
    });
    ui.alert('📋 Available Recommendations', msg, ui.ButtonSet.OK);
  } catch (e) {
    ui.alert('❌ Query Error', `Failed to check recommendations:\n\n${e.message}`, ui.ButtonSet.OK);
  }
}

function viewImportStatus() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(CONFIG.sheets.controlPanel);
  if (!sheet) {
    SpreadsheetApp.getUi().alert('❌ Error', `"${CONFIG.sheets.controlPanel}" sheet not found.`, ui.ButtonSet.OK);
    return;
  }
  const rows = sheet.getRange('A2:C').getValues().filter(r => r[0]);
  let imported = 0, failed = 0, pending = 0;
  rows.forEach(r => {
    const s = String(r[2] || '').toLowerCase();
    if (s.includes('imported') || s.includes('✅')) imported++;
    else if (s.includes('failed') || s.includes('❌')) failed++;
    else pending++;
  });
  SpreadsheetApp.getUi().alert('📊 Import Status',
    `Total: ${rows.length}\n\n` +
    `✅ Imported: ${imported}\n` +
    `❌ Failed: ${failed}\n` +
    `⏳ Pending: ${pending}`, SpreadsheetApp.getUi().ButtonSet.OK);
}

function testBigQueryConnection() {
  const ui = SpreadsheetApp.getUi();
  try {
    const r = executeQueryWithRetry({ query: 'SELECT "ok" AS status, CURRENT_TIMESTAMP() AS ts', useLegacySql: false });
    if (r.rows && r.rows.length) {
      ui.alert('✅ Connection Successful',
        `BigQuery connection OK.\n\nProject: ${CONFIG.bigquery.projectId}\nDataset: ${CONFIG.bigquery.datasetId}\nTable: ${CONFIG.bigquery.tableId}`,
        ui.ButtonSet.OK);
    } else {
      ui.alert('⚠️ Unexpected', 'Query returned no rows.', ui.ButtonSet.OK);
    }
  } catch (e) {
    ui.alert('❌ Connection Failed', `Could not connect to BigQuery:\n\n${e.message}`, ui.ButtonSet.OK);
  }
}

function showHelp() {
  const msg =
`🤖 AI SCHEDULE IMPORT SYSTEM – HELP

PREREQUISITES
• Column A: Creator Name (display)
• Column B: Google Sheet URL
• Target tab exists: "Schedule #1A" (or your chosen ID)
• BigQuery API enabled (Advanced Services)

WORKFLOW
1) Select a creator row in "${CONFIG.sheets.controlPanel}"
2) Use "👁️ Preview Schedule" to inspect content
3) Use "📥 Import Schedule" to write to the sheet
4) Check Column C for status

COMMON ISSUES
• "No schedule found" → Not generated or not pending
• "Cannot access sheet" → URL/permissions problem
• "Tab not found" → Create "Schedule #1A" sheet
• "Invalid JSON" → Recommendation data corrupted

STATUS MEANINGS
• ✅ Imported   – Completed
• ❌ Failed     – Error occurred
• ⏳ Importing  – In progress
• ⏭️ No recommendation – Skipped`;
  SpreadsheetApp.getUi().alert('❓ Help & Troubleshooting', msg, SpreadsheetApp.getUi().ButtonSet.OK);
}
