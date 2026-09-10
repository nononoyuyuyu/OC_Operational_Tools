/**
 * @OnlyCurrentDoc
 * OC_ThreeMonthBlankHighlighter v2.1。登録日セルに専用の条件付き書式を設定する。
 * セル値・元背景色・フィルタ・非表示行・行グループは変更しない。
 */
function runOC_ThreeMonthBlankHighlighter() {
  ocBlank3mV2Run_(false);
}

/** 書込みもロック取得も行わない確認専用の公開関数。 */
function previewOC_ThreeMonthBlankHighlighter() {
  ocBlank3mV2Run_(true);
}

function ocBlank3mV2Config_() {
  return { title: 'OC_ThreeMonthBlankHighlighter', version: '2.1', sheet: '学生情報一覧', months: 3,
    maxStudents: 1000, maxDateColumns: 300, maxReadCells: 500000, maxRules: 1000,
    color: '#ff0000', formula: '=N("OC_ThreeMonthBlankHighlighter:v2")=0' };
}

function ocBlank3mV2Run_(previewOnly) {
  var core = ocBlank3mV2Core_(), config = ocBlank3mV2Config_();
  var ui = SpreadsheetApp.getUi(), lock = null, resultMessage = '';
  try {
    if (core.version !== config.version) core.fail('Core.gsとCode.gsの版が異なります。両方を最新版へ更新してください。');
    var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    if (!spreadsheet) core.fail('対象スプレッドシートから実行してください。');
    var initial = ocBlank3mV2Read_(spreadsheet, config);
    var message = ocBlank3mV2Message_(initial, config);
    if (previewOnly) { ui.alert(config.title + '：確認のみ', message, ui.ButtonSet.OK); return; }
    // 確認ダイアログ中はロックを保持しない。
    if (ui.alert(config.title, message + '\n\nこの内容で専用の赤表示を更新しますか。',
        ui.ButtonSet.YES_NO) !== ui.Button.YES) return;
    lock = LockService.getDocumentLock();
    if (!lock || !lock.tryLock(5000)) core.fail('別の処理が実行中です。終了後に再実行してください。');
    var current = ocBlank3mV2Read_(spreadsheet, config);
    if (initial.fingerprint !== current.fingerprint) {
      core.fail('確認中に判定対象・基準日・条件付き書式が変更されました。書き込まずに中止しました。再実行してください。');
    }
    var changed = ocBlank3mV2Apply_(current, config);
    resultMessage = (changed ? '専用の赤表示を更新しました。' : '判定結果と専用表示に変更はありません。') +
      '\n該当: ' + current.analysis.matches.length + '行。対象外の専用表示は残しません。' +
      '\n元の塗りつぶし色と他の条件付き書式は保持しています。';
  } catch (error) {
    resultMessage = error && error.name === 'OCBlank3mV2UserError' ? error.message :
      '処理を完了できませんでした。権限・保護設定と導入した2ファイルの版を確認してください。';
  } finally {
    // アラートでスクリプトを中断する前にロックを必ず解放する。
    if (lock && lock.hasLock()) lock.releaseLock();
  }
  ui.alert(config.title, resultMessage, ui.ButtonSet.OK);
}

function ocBlank3mV2Read_(spreadsheet, config) {
  var core = ocBlank3mV2Core_();
  var sheet = spreadsheet.getSheetByName(config.sheet);
  if (!sheet) core.fail('「' + config.sheet + '」シートが見つかりません。');
  var rows = sheet.getLastRow(), columns = sheet.getLastColumn();
  if (rows < 1 || columns < 1) core.fail('対象シートにデータがありません。');
  if (rows * columns > config.maxReadCells) core.fail('読取範囲が上限の500,000セルを超えています。不要な遠方セルを整理してください。');
  var timeZone = spreadsheet.getSpreadsheetTimeZone();
  if (!timeZone) core.fail('スプレッドシートのタイムゾーンを確認できません。');
  var formatDate = function (value, zone, pattern) { return Utilities.formatDate(value, zone, pattern); };
  var today = core.parseDate(new Date(), '', timeZone, formatDate);
  if (!today) core.fail('判定基準日を確定できません。');
  var matrix = sheet.getRange(1, 1, rows, columns).getDisplayValues();
  var location = core.findHeader(matrix);
  var rawHeaders = sheet.getRange(location.row, 1, 1, columns).getValues()[0];
  var dataRows = rows - location.row;
  var registrationValues = dataRows > 0 ?
    sheet.getRange(location.row + 1, location.registrationColumn + 1, dataRows, 1).getValues() : [];
  var analysis = core.analyze({ matrix: matrix, location: location, rawHeaders: rawHeaders,
    registrationValues: registrationValues, timeZone: timeZone, today: today }, config, formatDate);
  var rules = sheet.getConditionalFormatRules();
  if (rules.length > config.maxRules) core.fail('条件付き書式が多すぎます。既存ルールを整理してください。');
  var rulesSignature = ocBlank3mV2RulesSignature_(rules);
  return { sheet: sheet, analysis: analysis, rules: rules, rulesSignature: rulesSignature,
    managedCount: rules.filter(function (rule) { return ocBlank3mV2Owned_(rule, config); }).length,
    fingerprint: ocBlank3mV2Digest_(JSON.stringify([spreadsheet.getId(), sheet.getSheetId(),
      analysis.fingerprint, rulesSignature])) };
}

function ocBlank3mV2Message_(state, config) {
  var a = state.analysis;
  var lines = [config.sheet + '／ヘッダー: ' + a.location.row + '行目',
    '基準日: ' + a.today + '／空欄月数の集計終点: ' + a.countThrough + '（先月末）',
    '登録月を数えず、翌月から先月まで連続' + config.months + 'か月以上空欄の行を対象にします。',
    '当月は月数に加えませんが、当月内の未来日を含め1つでも記入があれば対象外です。',
    '記入確認の終点: ' + a.reviewThrough + '（当月末）／最新の確認対象日付列: ' + a.latest,
    '非空欄の月で連続期間をリセットします。日付列が存在しない月も空欄と推測せず、連続期間を中断します。',
    '翌月以降の日付列は、記入の有無にかかわらず判定対象外です。',
    '学生: ' + a.students + '行／該当: ' + a.matches.length + '行／判定保留: ' + a.skipped.length + '行',
    '既存の専用ルール: ' + state.managedCount + '件。今回の対象だけに更新し、対象外の専用表示は解除します。',
    '元の塗りつぶし・他の条件付き書式・フィルタ・行表示は保持します。',
    '旧版や手作業で直接塗った赤色は解除しません。判定は再実行時に更新します。'];
  a.matches.slice(0, 20).forEach(function (item) {
    lines.push('対象 ' + item.cell + ': ' + item.start + '～' + item.end + '（連続' + item.monthCount + 'か月）');
  });
  if (a.matches.length > 20) lines.push('対象は他' + (a.matches.length - 20) + '行');
  a.skipped.slice(0, 20).forEach(function (item) { lines.push('保留 ' + item.cell + ': ' + item.reason); });
  if (a.skipped.length > 20) lines.push('保留は他' + (a.skipped.length - 20) + '行');
  return lines.join('\n');
}

/** 専用マーカーと完全一致したカスタム数式だけを所有ルールとする。 */
function ocBlank3mV2Owned_(rule, config) {
  var condition = rule.getBooleanCondition();
  if (!condition || condition.getCriteriaType() !== SpreadsheetApp.BooleanCriteria.CUSTOM_FORMULA) return false;
  var values = condition.getCriteriaValues();
  return values.length === 1 && String(values[0]) === config.formula;
}

function ocBlank3mV2Apply_(state, config) {
  var core = ocBlank3mV2Core_(), sheet = state.sheet;
  var addresses = core.segments(state.analysis.matches, state.analysis.location.registrationColumn);
  var newRanges = addresses.length ? sheet.getRangeList(addresses).getRanges() : [];
  var oldOwned = state.rules.filter(function (rule) { return ocBlank3mV2Owned_(rule, config); });
  var otherRules = state.rules.filter(function (rule) { return !ocBlank3mV2Owned_(rule, config); });
  var proposed = otherRules.slice();
  if (newRanges.length) {
    // 入力値を数式へ連結しない。範囲も物理行列番号から生成する。
    proposed.unshift(SpreadsheetApp.newConditionalFormatRule().whenFormulaSatisfied(config.formula)
      .setBackground(config.color).setRanges(newRanges).build());
  }
  if (proposed.length > config.maxRules) core.fail('条件付き書式の上限を超えます。変更しません。');
  var proposedSignature = ocBlank3mV2RulesSignature_(proposed);
  if (proposedSignature === state.rulesSignature) return false;

  var protections = sheet.getProtections(SpreadsheetApp.ProtectionType.SHEET);
  if (protections.some(function (protection) { return !protection.isWarningOnly() && !protection.canEdit(); })) {
    core.fail('シート保護により条件付き書式を変更できません。変更せずに中止しました。');
  }
  var affected = newRanges.slice();
  oldOwned.forEach(function (rule) { affected = affected.concat(rule.getRanges()); });
  if (affected.some(function (range) { return !range.canEdit(); })) {
    core.fail('対象登録日セルまたは以前の専用表示範囲に保護セルがあります。変更せずに中止しました。');
  }
  if (newRanges.some(function (range) { return range.isPartOfMerge(); })) {
    core.fail('対象登録日セルに結合セルがあります。登録日セルだけを着色できないため中止しました。');
  }
  // 権限確認中の他ルール編集も検知する。
  if (ocBlank3mV2RulesSignature_(sheet.getConditionalFormatRules()) !== state.rulesSignature) {
    core.fail('条件付き書式が変更されました。上書きせずに中止しました。');
  }
  try {
    // 他ルールのオブジェクト・相対順をそのまま保持して専用ルールのみ差し替える。
    sheet.setConditionalFormatRules(proposed);
    SpreadsheetApp.flush();
    if (ocBlank3mV2RulesSignature_(sheet.getConditionalFormatRules()) !== proposedSignature) {
      throw new Error('反映結果不一致');
    }
  } catch (error) {
    var recovery = '現在の状態を確認できません。条件付き書式を手動で確認してください。';
    try {
      var liveSignature = ocBlank3mV2RulesSignature_(sheet.getConditionalFormatRules());
      if (liveSignature === state.rulesSignature) {
        recovery = '条件付き書式は実行前の状態です。';
      } else if (liveSignature === proposedSignature) {
        sheet.setConditionalFormatRules(state.rules);
        SpreadsheetApp.flush();
        recovery = ocBlank3mV2RulesSignature_(sheet.getConditionalFormatRules()) === state.rulesSignature ?
          '条件付き書式を実行前の状態へ復元しました。' : '復元を確認できません。条件付き書式を手動で確認してください。';
      } else {
        recovery = '別の編集または部分変更を検出しました。他の変更を上書きしないため自動復元していません。条件付き書式を確認してください。';
      }
    } catch (restoreError) { /* 個人情報を含み得る例外を記録しない。 */ }
    core.fail('専用の赤表示を更新できませんでした。' + recovery);
  }
  return true;
}

/** 既存の色・条件・範囲・優先順を含むスナップショット。テーマ色も区別する。 */
function ocBlank3mV2RulesSignature_(rules) {
  function color(value) {
    if (!value) return null;
    var kind = String(value.getColorType());
    if (kind === 'RGB') return [kind, value.asRgbColor().asHexString().toLowerCase()];
    if (kind === 'THEME') return [kind, String(value.asThemeColor().getThemeColorType())];
    ocBlank3mV2Core_().fail('未対応の条件付き書式の色種別です。安全のため変更しません。');
  }
  function argument(value) {
    if (Object.prototype.toString.call(value) === '[object Date]') return ['Date', value.getTime()];
    return [typeof value, String(value)];
  }
  return JSON.stringify(rules.map(function (rule) {
    var ranges = rule.getRanges().map(function (range) {
      return [range.getSheet().getSheetId(), range.getA1Notation()];
    });
    var condition = rule.getBooleanCondition(), gradient = rule.getGradientCondition();
    if (condition) return [ranges, String(condition.getCriteriaType()), condition.getCriteriaValues().map(argument),
      color(condition.getBackgroundObject()), color(condition.getFontColorObject()),
      condition.getBold(), condition.getItalic(), condition.getStrikethrough(), condition.getUnderline()];
    if (gradient) return [ranges, 'gradient', ['Min', 'Mid', 'Max'].map(function (point) {
      return [color(gradient['get' + point + 'ColorObject']()),
        String(gradient['get' + point + 'Type']()), gradient['get' + point + 'Value']()];
    })];
    ocBlank3mV2Core_().fail('解析できない条件付き書式があります。安全のため変更しません。');
  }));
}

function ocBlank3mV2Digest_(text) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, text, Utilities.Charset.UTF_8)
    .map(function (value) { return ('0' + ((value + 256) % 256).toString(16)).slice(-2); }).join('');
}
