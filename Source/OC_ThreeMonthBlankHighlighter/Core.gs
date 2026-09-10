/**
 * OC_ThreeMonthBlankHighlighter v2.1: 副作用を持たない判定エンジン。
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

  function monthIndex(value) { return value.year * 12 + value.month - 1; }

  function monthBoundary(index, last) {
    var year = Math.floor(index / 12), month = index % 12 + 1;
    return day(year, month, last ? new Date(Date.UTC(year, month, 0)).getUTCDate() : 1);
  }

  function windowFor(today) {
    var current = monthIndex(today);
    var countThrough = monthBoundary(current - 1, true);
    var reviewThrough = monthBoundary(current, true);
    if (!countThrough || !reviewThrough) fail('集計対象月を確定できません。基準日を確認してください。');
    return { currentMonth: current, countThrough: countThrough, reviewThrough: reviewThrough };
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
    var window = windowFor(today);
    // 当月は月数に加算しないが、未来の日付も記入有無の確認には含める。
    var reviewed = dates.filter(function (item) { return item.date.key <= window.reviewThrough.key; });
    if (!reviewed.length) fail('当月末以前の日付列がありません。背景表示は変更しません。');
    return { reviewed: reviewed, futureCount: dates.length - reviewed.length, window: window };
  }

  // 登録月の翌月から先月までの末尾連続月を数える。
  // 日付列のない月は空欄と断定せず、非空欄の月と同様に連続区間を中断する。
  function completedMonths(row, dates, registration, today) {
    var firstMonth = monthIndex(registration) + 1, current = monthIndex(today);
    var buckets = Object.create(null);
    dates.forEach(function (item) {
      var month = monthIndex(item.date);
      if (month < firstMonth || month > current) return;
      if (!buckets[month]) buckets[month] = { nonblank: false };
      if (!blank(row[item.column])) buckets[month].nonblank = true;
    });
    var count = 0;
    for (var month = current - 1; month >= firstMonth; month -= 1) {
      if (!buckets[month] || buckets[month].nonblank) break;
      count += 1;
    }
    return { monthCount: count,
      start: count ? monthBoundary(current - count, false).text : null,
      end: monthBoundary(current - 1, true).text,
      currentMonthHasValue: !!(buckets[current] && buckets[current].nonblank) };
  }

  function trailing(row, dates, registration, months, today) {
    if (!today) fail('月単位判定には基準日が必要です。Core.gsとCode.gsを同じ版へ更新してください。');
    if (registration.key > today.key) return null;
    var status = completedMonths(row, dates, registration, today);
    if (status.currentMonthHasValue || status.monthCount < months) return null;
    var startMonth = monthIndex(today) - status.monthCount;
    return { start: status.start, end: status.end,
      threshold: monthBoundary(startMonth + months - 1, true).text, monthCount: status.monthCount };
  }

  function analyze(input, config, formatDate) {
    if (config.version !== '2.1') fail('Core.gsとCode.gsの版が異なります。両方を最新版へ更新してください。');
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
      var eligible = registration ? columns.reviewed.filter(function (item) {
        return monthIndex(item.date) > monthIndex(registration);
      }) : [];
      if (!status && !eligible.length) status = '登録翌月以降の対象日付なし';
      var blankFlags = eligible.map(function (item) { return blank(row[item.column]); });
      // 当月の未来日への記入も、確認中の変更検知に必ず含める。
      fingerprint.push([rowNumber, registration ? registration.text : status, blankFlags]);
      if (status) { skipped.push({ cell: address, reason: status }); continue; }
      var streak = trailing(row, eligible, registration, config.months, input.today);
      if (streak) matches.push({ row: rowNumber, cell: address, start: streak.start,
        end: streak.end, threshold: streak.threshold, monthCount: streak.monthCount });
    }
    return { matches: matches, skipped: skipped, students: students, location: location,
      today: input.today.text, latest: columns.reviewed[columns.reviewed.length - 1].date.text,
      countThrough: columns.window.countThrough.text, reviewThrough: columns.window.reviewThrough.text,
      futureCount: columns.futureCount,
      fingerprint: JSON.stringify(['calendar-month-v1', input.today.text, input.timeZone, matrix.length, location,
        columns.reviewed.map(function (item) { return [item.column, item.date.text]; }), fingerprint]) };
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

  return { version: '2.1', fail: fail, blank: blank, header: header, day: day, parseDate: parseDate,
    addMonths: addMonths, monthIndex: monthIndex, monthBoundary: monthBoundary, windowFor: windowFor,
    cell: cell, findHeader: findHeader, dateColumns: dateColumns, completedMonths: completedMonths,
    trailing: trailing, analyze: analyze, segments: segments };
}
