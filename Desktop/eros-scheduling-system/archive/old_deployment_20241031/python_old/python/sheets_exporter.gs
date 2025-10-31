/**
 * =============================================================================
 * EROS SHEETS EXPORTER - GOOGLE APPS SCRIPT
 * =============================================================================
 * Project: of-scheduler-proj
 * Dataset: eros_scheduling_brain
 * Purpose: Export BigQuery schedules to Google Sheets with duplicate prevention
 * Version: 1.0.0 (Production)
 * =============================================================================
 */

// =============================================================================
// CONFIGURATION
// =============================================================================

const CONFIG = {
  projectId: 'of-scheduler-proj',
  dataset: 'eros_scheduling_brain',
  viewName: 'schedule_recommendations_messages',
  logTable: 'schedule_export_log',

  // Column definitions (order matters!)
  columns: [
    'schedule_id',
    'page_name',
    'day_of_week',
    'scheduled_send_time',
    'message_type',
    'caption_id',
    'caption_text',
    'price_tier',
    'content_category',
    'has_urgency',
    'performance_score'
  ],

  // Header display names
  headers: [
    'Schedule ID',
    'Creator/Page',
    'Day of Week',
    'Send Time',
    'Type',
    'Caption ID',
    'Caption Text',
    'Price Tier',
    'Category',
    'Has Urgency',
    'Performance Score'
  ]
};

// =============================================================================
// MAIN EXPORT FUNCTION
// =============================================================================

/**
 * Export a schedule from BigQuery to Google Sheets
 * @param {string} scheduleId - The schedule ID to export
 * @param {string} sheetName - Optional: name of the sheet tab (defaults to page_name)
 * @return {Object} Export result with status and metadata
 */
function exportScheduleToSheet(scheduleId, sheetName) {
  const startTime = new Date();

  try {
    // Validate input
    if (!scheduleId || scheduleId.trim() === '') {
      throw new Error('Schedule ID is required');
    }

    scheduleId = scheduleId.trim();
    Logger.log(`Starting export for schedule: ${scheduleId}`);

    // Step 1: Check for duplicate export
    const duplicateCheck = checkDuplicateExport(scheduleId);
    if (duplicateCheck.isDuplicate) {
      Logger.log(`Duplicate export detected: ${duplicateCheck.message}`);
      return {
        status: 'skipped',
        reason: 'duplicate',
        schedule_id: scheduleId,
        previous_export: duplicateCheck.lastExport,
        message: duplicateCheck.message
      };
    }

    // Step 2: Query BigQuery view
    const scheduleData = queryBigQuery(scheduleId);

    if (!scheduleData || scheduleData.length === 0) {
      throw new Error(`No data found for schedule ID: ${scheduleId}`);
    }

    Logger.log(`Retrieved ${scheduleData.length} messages from BigQuery`);

    // Step 3: Determine sheet name
    const pageName = scheduleData[0].page_name;
    const targetSheetName = sheetName || pageName || scheduleId;

    // Step 4: Find or create sheet tab
    const sheet = getOrCreateSheet(targetSheetName);

    // Step 5: Clear existing data in this tab only
    clearSheetData(sheet);

    // Step 6: Write headers
    writeHeaders(sheet);

    // Step 7: Write schedule data
    const rowsWritten = writeScheduleData(sheet, scheduleData);

    // Step 8: Format sheet
    formatSheet(sheet);

    // Step 9: Log successful export
    const endTime = new Date();
    const durationSeconds = (endTime - startTime) / 1000;

    logExport(scheduleId, 'success', rowsWritten, durationSeconds, targetSheetName);

    Logger.log(`Export completed successfully: ${rowsWritten} rows written to ${targetSheetName}`);

    return {
      status: 'success',
      schedule_id: scheduleId,
      page_name: pageName,
      sheet_name: targetSheetName,
      rows_exported: rowsWritten,
      duration_seconds: durationSeconds,
      exported_at: endTime.toISOString()
    };

  } catch (error) {
    Logger.log(`Export failed: ${error.message}`);

    // Log failure
    logExport(scheduleId, 'error', 0, 0, sheetName, error.message);

    return {
      status: 'error',
      schedule_id: scheduleId,
      error: error.message,
      stack: error.stack
    };
  }
}

// =============================================================================
// BIGQUERY OPERATIONS
// =============================================================================

/**
 * Query BigQuery view for schedule data
 * @param {string} scheduleId - The schedule ID to query
 * @return {Array<Object>} Array of message objects
 */
function queryBigQuery(scheduleId) {
  const query = `
    SELECT
      schedule_id,
      page_name,
      day_of_week,
      FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', scheduled_send_time) AS scheduled_send_time,
      message_type,
      caption_id,
      caption_text,
      price_tier,
      content_category,
      has_urgency,
      ROUND(performance_score, 4) AS performance_score
    FROM \`${CONFIG.projectId}.${CONFIG.dataset}.${CONFIG.viewName}\`
    WHERE schedule_id = @scheduleId
    ORDER BY day_of_week, scheduled_send_time
  `;

  const request = {
    query: query,
    parameterMode: 'NAMED',
    queryParameters: [{
      name: 'scheduleId',
      parameterType: { type: 'STRING' },
      parameterValue: { value: scheduleId }
    }],
    useLegacySql: false
  };

  try {
    const queryResults = BigQuery.Jobs.query(request, CONFIG.projectId);

    if (!queryResults.rows) {
      return [];
    }

    // Parse results into objects
    const headers = queryResults.schema.fields.map(field => field.name);
    const data = queryResults.rows.map(row => {
      const obj = {};
      row.f.forEach((cell, index) => {
        obj[headers[index]] = cell.v;
      });
      return obj;
    });

    return data;

  } catch (error) {
    Logger.log(`BigQuery query error: ${error.message}`);
    throw new Error(`Failed to query BigQuery: ${error.message}`);
  }
}

/**
 * Check if schedule has already been exported
 * @param {string} scheduleId - The schedule ID to check
 * @return {Object} Duplicate check result
 */
function checkDuplicateExport(scheduleId) {
  const query = `
    SELECT
      schedule_id,
      export_status,
      record_count,
      sheet_name,
      exported_at,
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), exported_at, HOUR) AS hours_since_export
    FROM \`${CONFIG.projectId}.${CONFIG.dataset}.${CONFIG.logTable}\`
    WHERE schedule_id = @scheduleId
      AND export_status = 'success'
    ORDER BY exported_at DESC
    LIMIT 1
  `;

  const request = {
    query: query,
    parameterMode: 'NAMED',
    queryParameters: [{
      name: 'scheduleId',
      parameterType: { type: 'STRING' },
      parameterValue: { value: scheduleId }
    }],
    useLegacySql: false
  };

  try {
    const queryResults = BigQuery.Jobs.query(request, CONFIG.projectId);

    if (!queryResults.rows || queryResults.rows.length === 0) {
      return { isDuplicate: false };
    }

    const lastExport = {};
    const headers = queryResults.schema.fields.map(field => field.name);
    queryResults.rows[0].f.forEach((cell, index) => {
      lastExport[headers[index]] = cell.v;
    });

    // Allow re-export if more than 24 hours old
    const hoursSinceExport = parseInt(lastExport.hours_since_export);
    if (hoursSinceExport > 24) {
      return {
        isDuplicate: false,
        lastExport: lastExport,
        message: `Previous export was ${hoursSinceExport} hours ago, allowing re-export`
      };
    }

    return {
      isDuplicate: true,
      lastExport: lastExport,
      message: `Schedule already exported ${hoursSinceExport} hours ago to sheet: ${lastExport.sheet_name}`
    };

  } catch (error) {
    // If log table doesn't exist or query fails, allow export
    Logger.log(`Duplicate check warning: ${error.message}`);
    return { isDuplicate: false };
  }
}

/**
 * Log export to BigQuery
 * @param {string} scheduleId - The schedule ID
 * @param {string} status - Export status (success/error)
 * @param {number} recordCount - Number of records exported
 * @param {number} durationSeconds - Export duration in seconds
 * @param {string} sheetName - Target sheet name
 * @param {string} errorMessage - Optional error message
 */
function logExport(scheduleId, status, recordCount, durationSeconds, sheetName, errorMessage) {
  const query = `
    INSERT INTO \`${CONFIG.projectId}.${CONFIG.dataset}.${CONFIG.logTable}\`
    (schedule_id, export_status, record_count, duration_seconds, sheet_name, error_message, exported_at)
    VALUES
    (@scheduleId, @status, @recordCount, @durationSeconds, @sheetName, @errorMessage, CURRENT_TIMESTAMP())
  `;

  const request = {
    query: query,
    parameterMode: 'NAMED',
    queryParameters: [
      {
        name: 'scheduleId',
        parameterType: { type: 'STRING' },
        parameterValue: { value: scheduleId }
      },
      {
        name: 'status',
        parameterType: { type: 'STRING' },
        parameterValue: { value: status }
      },
      {
        name: 'recordCount',
        parameterType: { type: 'INT64' },
        parameterValue: { value: recordCount.toString() }
      },
      {
        name: 'durationSeconds',
        parameterType: { type: 'FLOAT64' },
        parameterValue: { value: durationSeconds.toString() }
      },
      {
        name: 'sheetName',
        parameterType: { type: 'STRING' },
        parameterValue: { value: sheetName || null }
      },
      {
        name: 'errorMessage',
        parameterType: { type: 'STRING' },
        parameterValue: { value: errorMessage || null }
      }
    ],
    useLegacySql: false
  };

  try {
    BigQuery.Jobs.query(request, CONFIG.projectId);
    Logger.log(`Export logged to BigQuery: ${status}`);
  } catch (error) {
    // Don't fail export if logging fails
    Logger.log(`Warning: Failed to log export: ${error.message}`);
  }
}

// =============================================================================
// SHEET OPERATIONS
// =============================================================================

/**
 * Get existing sheet or create new one
 * @param {string} sheetName - Name of the sheet tab
 * @return {Sheet} The sheet object
 */
function getOrCreateSheet(sheetName) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(sheetName);

  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    Logger.log(`Created new sheet: ${sheetName}`);
  } else {
    Logger.log(`Using existing sheet: ${sheetName}`);
  }

  return sheet;
}

/**
 * Clear existing data from sheet (keep structure)
 * @param {Sheet} sheet - The sheet to clear
 */
function clearSheetData(sheet) {
  const lastRow = sheet.getLastRow();
  const lastCol = sheet.getLastColumn();

  if (lastRow > 0 && lastCol > 0) {
    sheet.getRange(1, 1, lastRow, lastCol).clearContent();
    sheet.getRange(1, 1, lastRow, lastCol).clearFormat();
    Logger.log(`Cleared existing data: ${lastRow} rows x ${lastCol} columns`);
  }
}

/**
 * Write headers to sheet
 * @param {Sheet} sheet - The sheet to write to
 */
function writeHeaders(sheet) {
  const headerRange = sheet.getRange(1, 1, 1, CONFIG.headers.length);
  headerRange.setValues([CONFIG.headers]);
  headerRange.setFontWeight('bold');
  headerRange.setBackground('#4285f4');
  headerRange.setFontColor('#ffffff');
  sheet.setFrozenRows(1);

  Logger.log(`Wrote ${CONFIG.headers.length} headers`);
}

/**
 * Write schedule data to sheet
 * @param {Sheet} sheet - The sheet to write to
 * @param {Array<Object>} scheduleData - Array of message objects
 * @return {number} Number of rows written
 */
function writeScheduleData(sheet, scheduleData) {
  if (!scheduleData || scheduleData.length === 0) {
    return 0;
  }

  // Convert objects to arrays in correct column order
  const rows = scheduleData.map(message => {
    return CONFIG.columns.map(col => {
      const value = message[col];

      // Handle null/undefined
      if (value === null || value === undefined) {
        return '';
      }

      // Handle boolean
      if (typeof value === 'boolean') {
        return value ? 'Yes' : 'No';
      }

      return value;
    });
  });

  // Write data
  const dataRange = sheet.getRange(2, 1, rows.length, rows[0].length);
  dataRange.setValues(rows);

  Logger.log(`Wrote ${rows.length} data rows`);
  return rows.length;
}

/**
 * Format the sheet for readability
 * @param {Sheet} sheet - The sheet to format
 */
function formatSheet(sheet) {
  const lastRow = sheet.getLastRow();

  if (lastRow <= 1) {
    return; // No data to format
  }

  // Auto-resize columns
  for (let i = 1; i <= CONFIG.columns.length; i++) {
    sheet.autoResizeColumn(i);
  }

  // Set alternating row colors for data rows
  const dataRange = sheet.getRange(2, 1, lastRow - 1, CONFIG.columns.length);
  dataRange.applyRowBanding(SpreadsheetApp.BandingTheme.LIGHT_GREY, false, false);

  // Format specific columns

  // Day of week (column 3) - center align
  if (lastRow > 1) {
    sheet.getRange(2, 3, lastRow - 1, 1).setHorizontalAlignment('center');
  }

  // Send time (column 4) - datetime format
  if (lastRow > 1) {
    sheet.getRange(2, 4, lastRow - 1, 1).setNumberFormat('yyyy-mm-dd hh:mm:ss');
  }

  // Performance score (column 11) - percentage format
  if (lastRow > 1) {
    sheet.getRange(2, 11, lastRow - 1, 1).setNumberFormat('0.00%');
  }

  // Caption text (column 7) - wrap text
  if (lastRow > 1) {
    sheet.getRange(2, 7, lastRow - 1, 1).setWrap(true);
  }

  Logger.log('Applied formatting to sheet');
}

// =============================================================================
// UI FUNCTIONS (For manual use in Sheets)
// =============================================================================

/**
 * Create custom menu on spreadsheet open
 */
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu('EROS Scheduler')
    .addItem('Export Schedule from BigQuery', 'showExportDialog')
    .addSeparator()
    .addItem('Check Export Log', 'showExportLog')
    .addItem('About', 'showAbout')
    .addToUi();
}

/**
 * Show export dialog to get schedule ID from user
 */
function showExportDialog() {
  const ui = SpreadsheetApp.getUi();

  const response = ui.prompt(
    'Export Schedule',
    'Enter Schedule ID (e.g., SCH_A1B2C3D4):',
    ui.ButtonSet.OK_CANCEL
  );

  if (response.getSelectedButton() === ui.Button.OK) {
    const scheduleId = response.getResponseText().trim();

    if (scheduleId) {
      const result = exportScheduleToSheet(scheduleId);

      if (result.status === 'success') {
        ui.alert(
          'Export Successful',
          `Exported ${result.rows_exported} messages to sheet: ${result.sheet_name}\n\n` +
          `Duration: ${result.duration_seconds.toFixed(2)} seconds`,
          ui.ButtonSet.OK
        );
      } else if (result.status === 'skipped') {
        ui.alert(
          'Export Skipped',
          result.message,
          ui.ButtonSet.OK
        );
      } else {
        ui.alert(
          'Export Failed',
          `Error: ${result.error}`,
          ui.ButtonSet.OK
        );
      }
    }
  }
}

/**
 * Show recent export log
 */
function showExportLog() {
  const query = `
    SELECT
      schedule_id,
      export_status,
      record_count,
      sheet_name,
      FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', exported_at) AS exported_at
    FROM \`${CONFIG.projectId}.${CONFIG.dataset}.${CONFIG.logTable}\`
    ORDER BY exported_at DESC
    LIMIT 10
  `;

  const request = {
    query: query,
    useLegacySql: false
  };

  try {
    const queryResults = BigQuery.Jobs.query(request, CONFIG.projectId);

    if (!queryResults.rows) {
      SpreadsheetApp.getUi().alert('No export history found');
      return;
    }

    const headers = queryResults.schema.fields.map(field => field.name);
    const rows = queryResults.rows.map(row => {
      return row.f.map(cell => cell.v).join(' | ');
    });

    const message = 'Recent Exports:\n\n' +
                    headers.join(' | ') + '\n' +
                    rows.join('\n');

    SpreadsheetApp.getUi().alert('Export Log', message, SpreadsheetApp.getUi().ButtonSet.OK);

  } catch (error) {
    SpreadsheetApp.getUi().alert('Error', `Failed to load export log: ${error.message}`, SpreadsheetApp.getUi().ButtonSet.OK);
  }
}

/**
 * Show about dialog
 */
function showAbout() {
  const ui = SpreadsheetApp.getUi();
  ui.alert(
    'EROS Sheets Exporter',
    'Version: 1.0.0\n\n' +
    'Export schedules from BigQuery to Google Sheets\n\n' +
    'Project: of-scheduler-proj\n' +
    'Dataset: eros_scheduling_brain\n' +
    'View: schedule_recommendations_messages',
    ui.ButtonSet.OK
  );
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Test function to verify BigQuery connection
 */
function testBigQueryConnection() {
  const query = `SELECT CURRENT_TIMESTAMP() as timestamp`;

  try {
    const result = BigQuery.Jobs.query({
      query: query,
      useLegacySql: false
    }, CONFIG.projectId);

    Logger.log('BigQuery connection successful');
    Logger.log(`Server time: ${result.rows[0].f[0].v}`);
    return true;
  } catch (error) {
    Logger.log(`BigQuery connection failed: ${error.message}`);
    return false;
  }
}

/**
 * Create export log table if it doesn't exist
 */
function createExportLogTable() {
  const query = `
    CREATE TABLE IF NOT EXISTS \`${CONFIG.projectId}.${CONFIG.dataset}.${CONFIG.logTable}\` (
      schedule_id STRING NOT NULL,
      export_status STRING NOT NULL,
      record_count INT64,
      duration_seconds FLOAT64,
      sheet_name STRING,
      error_message STRING,
      exported_at TIMESTAMP NOT NULL,
      exported_by STRING
    )
    PARTITION BY DATE(exported_at)
    CLUSTER BY schedule_id, export_status
  `;

  try {
    BigQuery.Jobs.query({
      query: query,
      useLegacySql: false
    }, CONFIG.projectId);

    Logger.log('Export log table created or already exists');
    return true;
  } catch (error) {
    Logger.log(`Failed to create export log table: ${error.message}`);
    return false;
  }
}
