/**
 * OC_ThreeMonthBlankHighlighter v2: 副作用を持たない判定エンジン。
 * トップレベルには関数宣言だけを置き、既存GASと名前空間を分離する。
 */
function ocBlank3mV2Core_() {
  'use strict';

  function fail(message) {
    var error = new Error(message);
    error.name = 'OCBlank3mV2UserError';
    throw error;
  }

  function blank(value) {
    return String(value == null ? '' : value)
      .replace(/[\u200B-\u200D\u2060\uFEFF]/g, '').trim() === '';
  }

  function header(value) {
    return String(value == null ? '' : value).normalize('NFKC')
      .replace(/[\s\u200B-\u200D\u2060\uFEFF]/g, '');
  }

  function day(year, month, date) {
    if (!Number.isInteger(year) || year < 1900 || year > 9999 ||
        !Number.isInteger(month) || !Number.isInteger(date)) return null;
    var key = Date.UTC(year, month - 1, date);
    var checked = new Date(key);
    if (checked.getUTCFullYear() !== year || checked.getUTCMonth() + 1 !== month ||
        checked.getUTCDate() !== date) return null;
    return { year: year, month: month, day: date, key: key,
      text: String(year) + '/' + String(month).padStart(2, '0') + '/' + String(date).padStart(2, '0') };
  }

  // オフセットなしの日時文字列はシートの暦日として解釈する。年は推測しない。
  function parseDate(raw, display, timeZone, formatDate) {
    if (Object.prototype.toString.call(raw) === '[object Date]') {
      if (!Number.isFinite(raw.getTime())) return null;
      return parseDate(formatDate(raw, timeZone, 'yyyy/MM/dd'), '', timeZone, formatDate);
    }
    // 数値シリアルを年月日と推測しない。
    if (typeof raw !== 'string') return null;
    var text = raw.trim();
    var match = /^(\d{4})([\/-])(\d{1,2})\2(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/.exec(text);
    if (!match) {
      var japanese = /^(\d{4})年(\d{1,2})月(\d{1,2})日(?:\s*(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/.exec(text);
      if (!japanese) return null;
      match = [text, japanese[1], '/', japanese[2], japanese[3], japanese[4], japanese[5], japanese[6]];
    }
    if ((match[5] && Number(match[5]) > 23) ||
        (match[6] && Number(match[6]) > 59) || (match[7] && Number(match[7]) > 59)) return null;
    return day(Number(match[1]), Number(match[3]), Number(match[4]));
  }

  function addMonths(start, months) {
    var monthIndex = start.year * 12 + start.month - 1 + months;
    var year = Math.floor(monthIndex / 12);
    var month = monthIndex % 12 + 1;
    var lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
    return day(year, month, Math.min(start.day, lastDay));
  }

  function cell(row, column) {
    var letters = '';
    for (var n = column + 1; n > 0; n = Math.floor((n - 1) / 26)) {
      letters = String.fromCharCode(65 + (n - 1) % 26) + letters;
    }
    return letters + row;
  }

  function findHeader(matrix) {
    var aliases = ['登録・更新日', '登録更新日', '登録・更新日時', '登録日'];
    var candidates = [];
    matrix.forEach(function (row, index) {
      var ids = [], registrations = [];
      row.forEach(function (value, column) {
        var text = header(value);
        if (text === '学籍番号') ids.push(column);
        if (aliases.indexOf(text) >= 0) registrations.push(column);
      });
      if (ids.length && registrations.length) {
        if (ids.length !== 1 || registrations.length !== 1) {
          fail('シート上の' + (index + 1) + '行目に必須ヘッダーの重複があります。');
        }
        candidates.push({ row: index + 1, idColumn: ids[0], registrationColumn: registrations[0] });
      }
    });
    if (candidates.length !== 1) {
      fail('「学籍番号」と登録日列が各1つ存在するヘッダー行を一意に特定できません。候補数: ' + candidates.length);
    }
    return candidates[0];
  }

  function dateColumns(rawHeaders, displayHeaders, location, timeZone, today, formatDate, limit) {
    var dates = [], seen = Object.create(null);
    rawHeaders.forEach(function (raw, column) {
      if (column === location.idColumn || column === location.registrationColumn) return;
      var parsed = parseDate(raw, displayHeaders[column], timeZone, formatDate);
      if (!parsed) {
        var text = String(raw == null ? '' : raw).trim();
        var looksLikeDate = /^\d{4}[\/-]\d{1,2}[\/-]/.test(text) ||
          /^\d{4}年\d{1,2}月/.test(text) || /^\d{1,2}\/\d{1,2}$/.test(text);
        if (looksLikeDate || Object.prototype.toString.call(raw) === '[object Date]') {
          fail('日付見出し ' + cell(location.row, column) + ' の年月日を確定できません。日付型、または年付き日付にしてください。');
        }
        return;
      }
      if (seen[parsed.text]) fail('同じ日付の見出しが重複しています: ' + parsed.text);
      seen[parsed.text] = true;
      dates.push({ column: column, date: parsed });
    });
    if (dates.length > limit) fail('日付列数が上限の' + limit + '列を超えています。');
    dates.sort(function (a, b) { return a.date.key - b.date.key; });
    var past = dates.filter(function (item) { return item.date.key <= today.key; });
    if (!past.length) fail('基準日以前の日付列がありません。背景表示は変更しません。');
    return { past: past, futureCount: dates.length - past.length };
  }

  // 最新列から逆走し、最後の非空欄より後の区間だけを評価する。
  // 過去区間の達成時点で早期に「該当」と返してはならない。
  function trailing(row, dates, registration, months) {
    var eligible = dates.filter(function (item) { return item.date.key >= registration.key; });
    if (!eligible.length) return null;
    var i = eligible.length - 1;
    while (i >= 0 && blank(row[eligible[i].column])) i -= 1;
    if (i === eligible.length - 1) return null;
    var start = i < 0 ? registration : eligible[i + 1].date;
    var end = eligible[eligible.length - 1].date;
    var threshold = addMonths(start, months);
    if (!threshold || end.key < threshold.key) return null;
    return { start: start.text, end: end.text, threshold: threshold.text };
  }

  function analyze(input, config, formatDate) {
    var matrix = input.matrix, location = input.location;
    var columns = dateColumns(input.rawHeaders, matrix[location.row - 1], location,
      input.timeZone, input.today, formatDate, config.maxDateColumns);
    var matches = [], skipped = [], fingerprint = [], students = 0;
    for (var rowNumber = location.row + 1; rowNumber <= matrix.length; rowNumber += 1) {
      var row = matrix[rowNumber - 1];
      if (blank(row[location.idColumn])) continue;
      students += 1;
      if (students > config.maxStudents) fail('学生数が上限の' + config.maxStudents + '人を超えています。');
      var offset = rowNumber - location.row - 1;
      var raw = input.registrationValues[offset][0];
      var registration = parseDate(raw, row[location.registrationColumn], input.timeZone, formatDate);
      var address = cell(rowNumber, location.registrationColumn);
      var status = blank(raw) ? '登録日空欄' : !registration ? '登録日不正' :
        registration.key > input.today.key ? '登録日が未来' : '';
      var eligible = registration ? columns.past.filter(function (item) {
        return item.date.key >= registration.key;
      }) : [];
      if (!status && !eligible.length) status = '登録後の対象日付なし';
      var blankFlags = eligible.map(function (item) { return blank(row[item.column]); });
      // 個人識別子や氏名は保存・表示せず、判定に必要な情報だけを照合する。
      fingerprint.push([rowNumber, registration ? registration.text : status, blankFlags]);
      if (status) { skipped.push({ cell: address, reason: status }); continue; }
      var streak = trailing(row, eligible, registration, config.months);
      if (streak) matches.push({ row: rowNumber, cell: address, start: streak.start,
        end: streak.end, threshold: streak.threshold });
    }
    return { matches: matches, skipped: skipped, students: students, location: location,
      today: input.today.text, latest: columns.past[columns.past.length - 1].date.text,
      futureCount: columns.futureCount,
      fingerprint: JSON.stringify([input.today.text, input.timeZone, matrix.length, location,
        columns.past.map(function (item) { return [item.column, item.date.text]; }), fingerprint]) };
  }

  // 連続する登録日セルをまとめ、サービス呼び出しを学生数分発生させない。
  function segments(matches, column) {
    var rows = matches.map(function (item) { return item.row; }).sort(function (a, b) { return a - b; });
    var result = [];
    rows.forEach(function (row) {
      var last = result[result.length - 1];
      if (last && last.end + 1 === row) last.end = row;
      else result.push({ start: row, end: row });
    });
    return result.map(function (item) { return cell(item.start, column) + ':' + cell(item.end, column); });
  }

  return { fail: fail, blank: blank, header: header, day: day, parseDate: parseDate,
    addMonths: addMonths, cell: cell, findHeader: findHeader, dateColumns: dateColumns,
    trailing: trailing, analyze: analyze, segments: segments };
}
