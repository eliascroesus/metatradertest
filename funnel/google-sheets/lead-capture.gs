/**
 * Lead capture for the YouTube dropshipping funnel (page 1 opt-in form).
 * Every form submit adds one row to this spreadsheet.
 *
 * Setup (once):
 *   1. Open the "Ricky - Master Lead Sheet" spreadsheet.
 *   2. Extensions → Apps Script. Delete what's there, paste this whole file, save.
 *   3. Pick "setup" in the function dropdown and click Run. Allow access when asked.
 *      This writes the column headers into row 1.
 *   4. Deploy → New deployment → type "Web app".
 *      Execute as: Me. Who has access: Anyone. Click Deploy.
 *   5. Copy the Web app URL (ends in /exec) and paste it into
 *      leadSheetUrl in the CONFIG block of funnel/youtube-dropshipping.html.
 *
 * If you edit this script later, use Deploy → Manage deployments → Edit →
 * Version: New version, so the same URL keeps working.
 */

const SHEET_NAME = 'Sheet1';

// [column header, form field name]. The first column is filled by the server.
const COLUMNS = [
  ['Submitted At', null],
  ['Full Name', 'name'],
  ['Email', 'email'],
  ['Phone', 'phone'],
  ['Country', 'country'],
  ['Funnel', 'funnel'],
  ['Page URL', 'page_url'],
  ['UTM Source', 'utm_source'],
  ['UTM Medium', 'utm_medium'],
  ['UTM Campaign', 'utm_campaign'],
  ['UTM Content', 'utm_content'],
  ['UTM Term', 'utm_term'],
  ['Referrer', 'referrer'],
  ['Device', 'device'],
  ['Time Zone', 'timezone'],
];

function setup() {
  ensureHeaders_(getSheet_());
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = getSheet_();
    ensureHeaders_(sheet);
    const params = (e && e.parameter) || {};
    const row = COLUMNS.map(([, field]) => (field ? clean_(params[field]) : new Date()));
    sheet.appendRow(row);
    return json_({ ok: true });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// Open the Web app URL in a browser to check the deployment is live.
function doGet() {
  return ContentService.createTextOutput('Lead capture is running.');
}

function getSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  return ss.getSheetByName(SHEET_NAME) || ss.getSheets()[0];
}

function ensureHeaders_(sheet) {
  const headers = COLUMNS.map(([header]) => header);
  if (sheet.getLastRow() > 0 && sheet.getRange(1, 1).getValue() === headers[0]) return;
  if (sheet.getLastRow() > 0) sheet.insertRowBefore(1);
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight('bold');
  sheet.setFrozenRows(1);
  sheet.getRange('A:A').setNumberFormat('yyyy-mm-dd hh:mm:ss');
}

// Keep values as plain text: cap the length and stop "=", "+", "-" or "@" at the
// start from being read as a formula (phone numbers start with "+").
function clean_(value) {
  const text = value == null ? '' : String(value).slice(0, 500);
  return /^[=+\-@]/.test(text) ? "'" + text : text;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
