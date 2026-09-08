'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(
  path.resolve(__dirname, '../../Source/OC_KakuteiExtractor/Code.gs'),
  'utf8',
);

function formatDate(date, timeZone, format) {
  assert.strictEqual(format, 'yyyy/MM/dd');
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}/${values.month}/${values.day}`;
}

function jstDate(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day - 1, 15, 0, 0));
}

function buildEnvironment(options = {}) {
  const state = {
    alerts: [],
    filterRemoveCalled: false,
    criteriaRemoved: [],
    criteriaRestored: [],
    showRowsCalls: [],
    rowGroupMethodCalled: false,
    events: [],
    flushCount: 0,
    modal: null,
    lockReleased: false,
    matrixReadCount: 0,
    rawHeaderReadCount: 0,
    template: null,
  };

  const headers = [
    '登録・\n更新日', '記入者', '番号', '学籍番号', '名前', 'フリガナ',
    '性別', '学科名', '学年', 'SA/TA', '備考', '4/19', '4/26',
  ];
  const rawHeaders = headers.slice();
  rawHeaders[11] = jstDate(2026, 4, 19);
  rawHeaders[12] = jstDate(2026, 4, 26);

  function makeRow(values) {
    const row = Array(headers.length).fill('');
    for (const [index, value] of Object.entries(values)) {
      row[Number(index)] = value;
    }
    return row;
  }

  const initialMatrix = [
    ['OC学生情報管理'],
    headers,
    makeRow({
      3: 'A001', 4: '佐藤 太郎', 5: 'ｻﾄｳ-ﾀﾛｳ', 9: 'B65655',
      10: '追加列\n改行', 11: '〇', 12: '',
    }),
    makeRow({
      3: 'A002', 4: '山田 花子', 5: 'LEE-JUN HO', 9: '',
      10: '任意値', 11: '', 12: '確定',
    }),
  ];

  const changedMatrix = initialMatrix.map((row) => row.slice());
  changedMatrix[3][12] = '×';

  const criteriaByColumn = new Map([
    [4, {
      id: '学籍番号条件',
      copy: () => ({ build: () => ({ id: '学籍番号条件-copy' }) }),
    }],
    [12, {
      id: '日付条件',
      copy: () => ({ build: () => ({ id: '日付条件-copy' }) }),
    }],
  ]);
  let clearCalls = 0;

  const filter = options.noFilter ? null : {
    getRange: () => ({
      getColumn: () => 1,
      getNumColumns: () => headers.length,
    }),
    getColumnFilterCriteria(columnPosition) {
      return criteriaByColumn.get(columnPosition) || null;
    },
    removeColumnFilterCriteria(columnPosition) {
      clearCalls += 1;
      state.events.push(`条件解除:${columnPosition}`);
      state.criteriaRemoved.push(columnPosition);
      if (options.clearCriteriaThrowsAt === clearCalls) {
        throw new Error('条件解除失敗');
      }
    },
    setColumnFilterCriteria(columnPosition, criteria) {
      state.events.push(`条件復元:${columnPosition}`);
      state.criteriaRestored.push([columnPosition, criteria.id]);
    },
    remove() {
      state.filterRemoveCalled = true;
      throw new Error('フィルタ本体を削除してはならない');
    },
  };

  const controlSheet = {
    getName: () => 'スクリプト用シート',
    getSheetId: () => 101,
    getRange(a1) {
      assert.strictEqual(a1, 'A2:B2');
      return { getDisplayValues: () => [['2026/04/19', '2026/04/26']] };
    },
  };

  const sourceSheet = {
    getSheetId: () => 202,
    getLastColumn: () => headers.length,
    getLastRow: () => initialMatrix.length,
    getMaxRows: () => 1000,
    getFilter: () => filter,
    getProtections(type) {
      assert.strictEqual(type, 'SHEET');
      return options.blockingProtection
        ? [{ isWarningOnly: () => false, canEdit: () => false }]
        : [];
    },
    showRows(start, count) {
      state.events.push('行再表示');
      state.showRowsCalls.push([start, count]);
      if (options.showRowsThrows) {
        throw new Error('行再表示失敗');
      }
    },
    // 新実装は行グループの開閉状態を保持するため、呼ばれたら失敗させる。
    expandRowGroupsUpToDepth() {
      state.rowGroupMethodCalled = true;
      throw new Error('行グループAPIを呼び出してはならない');
    },
    expandAllRowGroups() {
      state.rowGroupMethodCalled = true;
      throw new Error('行グループAPIを呼び出してはならない');
    },
    getRange(row, column, numRows, numColumns) {
      if (
        row === 1 && column === 1 &&
        numRows === initialMatrix.length && numColumns === headers.length
      ) {
        return {
          getDisplayValues() {
            state.matrixReadCount += 1;
            if (options.changeAfterConfirmation && state.matrixReadCount >= 2) {
              return changedMatrix.map((item) => item.slice());
            }
            return initialMatrix.map((item) => item.slice());
          },
        };
      }

      if (row === 2 && column === 1 && numRows === 1 && numColumns === headers.length) {
        return {
          getValues() {
            state.rawHeaderReadCount += 1;
            return [rawHeaders.slice()];
          },
        };
      }

      throw new Error(`想定外の範囲取得: ${row},${column},${numRows},${numColumns}`);
    },
  };

  const spreadsheet = {
    getActiveSheet: () => controlSheet,
    getSheetByName: (name) => name === '学生情報一覧' ? sourceSheet : null,
    getId: () => 'spreadsheet-id',
    getName: () => 'OC参加者管理',
    getSpreadsheetTimeZone: () => 'Asia/Tokyo',
  };

  const ui = {
    Button: { YES: 'YES', OK: 'OK' },
    ButtonSet: { YES_NO: 'YES_NO', OK: 'OK_SET' },
    alert(title, message, buttons) {
      state.alerts.push({ title, message, buttons });
      if (buttons === 'YES_NO') {
        return options.answerNo ? 'NO' : 'YES';
      }
      return 'OK';
    },
    showModalDialog(html, title) {
      state.modal = { html, title };
    },
  };

  const lock = {
    tryLock: () => !options.lockFail,
    releaseLock: () => { state.lockReleased = true; },
  };

  const context = {
    Date,
    JSON,
    Math,
    Object,
    String,
    Number,
    RegExp,
    Array,
    Error,
    isNaN,
    SpreadsheetApp: {
      ProtectionType: { SHEET: 'SHEET' },
      getUi: () => ui,
      getActiveSpreadsheet: () => spreadsheet,
      flush() {
        state.flushCount += 1;
        state.events.push(`flush:${state.flushCount}`);
      },
    },
    LockService: { getDocumentLock: () => lock },
    HtmlService: {
      createTemplateFromFile(name) {
        assert.strictEqual(name, 'コピー確認');
        const template = {
          evaluate() {
            state.template = {
              toolName: template.toolName,
              copyText: template.copyText,
              dateLabels: template.dateLabels,
              rowCount: template.rowCount,
              headerRow: template.headerRow,
            };
            return {
              setWidth() { return this; },
              setHeight() { return this; },
            };
          },
        };
        return template;
      },
    },
    Utilities: {
      DigestAlgorithm: { SHA_256: 'SHA_256' },
      Charset: { UTF_8: 'UTF_8' },
      computeDigest(_algorithm, value) {
        return Array.from(crypto.createHash('sha256').update(value, 'utf8').digest());
      },
      formatDate,
    },
  };

  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, state };
}

// 正常系: フィルタ本体を残し、条件だけ解除して抽出する。
{
  const { context, state } = buildEnvironment();
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.alerts.length, 1);
  assert(state.alerts[0].message.includes('フィルタ自体を残したまま各列の絞り込み条件だけを解除'));
  assert(state.alerts[0].message.includes('行グループは通常の非表示行とは別機能として扱い、開閉状態を変更しません'));
  assert.strictEqual(state.filterRemoveCalled, false);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.deepStrictEqual(state.criteriaRemoved, [4, 12]);
  assert.deepStrictEqual(state.criteriaRestored, []);
  assert.deepStrictEqual(state.showRowsCalls, [[1, 1000]]);
  assert(state.events.indexOf('行再表示') < state.events.indexOf('条件解除:4'));
  assert.strictEqual(state.lockReleased, true);
  assert(state.modal);
  assert.strictEqual(state.template.rowCount, 2);
  assert.strictEqual(
    state.template.copyText,
    'A002\t山田 花子\tLEE-JUN HO\t\t\t確定\n' +
    'A001\t佐藤 太郎\tｻﾄｳ-ﾀﾛｳ\tB65655\t〇\t',
  );
}

// いいえなら表示状態へ一切触れない。
{
  const { context, state } = buildEnvironment({ answerNo: true });
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.filterRemoveCalled, false);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.deepStrictEqual(state.criteriaRemoved, []);
  assert.deepStrictEqual(state.showRowsCalls, []);
  assert.strictEqual(state.modal, null);
}

// 行再表示に失敗した場合、フィルタ条件を変更せず終了する。
{
  const { context, state } = buildEnvironment({ showRowsThrows: true });
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.alerts.length, 2);
  assert(state.alerts[1].message.includes('フィルタ本体と絞り込み条件は変更していません'));
  assert(state.alerts[1].message.includes('行グループの開閉状態も変更していません'));
  assert.deepStrictEqual(state.criteriaRemoved, []);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
  assert.strictEqual(state.modal, null);
}

// 保護で操作不能なら、行・条件とも無変更で終了する。
{
  const { context, state } = buildEnvironment({ blockingProtection: true });
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.alerts.length, 2);
  assert(state.alerts[1].message.includes('シート保護'));
  assert.deepStrictEqual(state.showRowsCalls, []);
  assert.deepStrictEqual(state.criteriaRemoved, []);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

// 条件解除途中の失敗では元条件を復元する。
{
  const { context, state } = buildEnvironment({ clearCriteriaThrowsAt: 2 });
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.alerts.length, 2);
  assert(state.alerts[1].message.includes('元の条件へ復元しました'));
  assert(state.alerts[1].message.includes('行グループの開閉状態は変更していません'));
  assert.deepStrictEqual(state.criteriaRemoved, [4, 12]);
  assert.deepStrictEqual(state.criteriaRestored, [
    [4, '学籍番号条件-copy'],
    [12, '日付条件-copy'],
  ]);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
  assert.strictEqual(state.modal, null);
}

// 確認中に取得対象データが変わった場合は表示状態変更前に中止する。
{
  const { context, state } = buildEnvironment({ changeAfterConfirmation: true });
  context.runOC_KakuteiExtractor();
  assert.strictEqual(state.alerts.length, 2);
  assert(state.alerts[1].message.includes('変更されました'));
  assert.deepStrictEqual(state.showRowsCalls, []);
  assert.deepStrictEqual(state.criteriaRemoved, []);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

console.log('統合モック検証: PASS（行グループ非操作・フィルタ本体保持）');
