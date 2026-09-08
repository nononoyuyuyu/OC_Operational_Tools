'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = fs.readFileSync(
  path.resolve(__dirname, '../../Source/OC_KakuteiExtractor/Code.gs'),
  'utf8',
);

function load(globals = {}) {
  const context = vm.createContext(globals);
  vm.runInContext(source, context);
  return context;
}

const t = load();
const config = t.ocKakuteiGetConfig_();
const info = {
  studentIdIndex: 0, nameIndex: 1, furiganaIndex: 2, saTaIndex: 3,
  dataStartIndex: 0, dataWidth: 5,
  outputIndexes: [0, 1, 2, 3, 4],
  targetDateColumns: [{ index: 4, confirmationLabel: '2026/01/01' }],
};

function userError(fragment) {
  return (error) => error.name === 'OC_KakuteiExtractorUserError' &&
    error.message.includes(fragment);
}

for (const value of [
  '=1+1', '+1', '-1', '@SUM(A1:A2)', '  =1+1', '\u200B=1+1',
  '\u200C \u2060=1', '\u0000=1', '\uFEFF=1',
  '＝1+1', '＋1', '－1', '＠SUM(A1:A2)', '　＝1',
]) {
  test(`数式形式をコピー用レコードの生成前に拒否: ${JSON.stringify(value)}`, () => {
    for (const retainRecords of [false, true]) {
      assert.throws(
        () => t.ocKakuteiValidateStudentRows_(
          config, [['A001', value, 'ﾔﾏﾀﾞ', '', '〇']], info, 38, retainRecords,
        ),
        userError('対象セル B38'),
      );
    }
  });
}

test('安全な氏名の文字列と名前内のハイフンを変更しない', () => {
  for (const name of ['山田 太郎', 'Anne-Marie', "O'Neil", ' A-B ']) {
    const rows = [['A001', name, 'LEE-JUN HO', '', '〇']];
    const before = JSON.stringify(rows);
    const result = t.ocKakuteiValidateStudentRows_(config, rows, info, 2, true);
    assert.equal(t.ocKakuteiBuildCopyOutput_(result.records).copyText,
      `A001\t${name}\tLEE-JUN HO\t\t〇`);
    assert.equal(JSON.stringify(rows), before);
  }
});

test('フリガナ先頭の数式起点も拒否し、内部ハイフンは許可する', () => {
  assert.throws(
    () => t.ocKakuteiValidateStudentRows_(
      config, [['A001', '山田', '-1', '', '〇']], info, 2, true,
    ),
    userError('対象セル C2'),
  );
});

test('TSVのタブ・改行拒否を維持する', () => {
  for (const name of ['A\tB', 'A\nB', 'A\rB']) {
    assert.throws(
      () => t.ocKakuteiValidateStudentRows_(
        config, [['A001', name, 'ﾔﾏﾀﾞ', '', '〇']], info, 2, true,
      ),
      userError('タブまたは改行'),
    );
  }
});

test('1,000人と300日付列・ヘッダーは読み込み上限内', () => {
  assert.doesNotThrow(() => t.ocKakuteiValidateReadSize_(config, 1001, 304));
  assert.doesNotThrow(() => t.ocKakuteiValidateReadSize_(config, 1000, 500));
  assert.throws(() => t.ocKakuteiValidateReadSize_(config, 1001, 500), userError('上限'));
  assert.throws(() => t.ocKakuteiValidateReadSize_(config, 1, 500001), userError('上限'));
});

test('不正な上限や次元を黙って無制限にしない', () => {
  for (const limit of [0, -1, NaN, Infinity, undefined]) {
    assert.throws(
      () => t.ocKakuteiValidateReadSize_({ maxReadCells: limit }, 2, 5),
      userError('不正'),
    );
  }
  assert.throws(() => t.ocKakuteiValidateReadSize_(config, 0, 5), userError('不正'));
});

function workflowFixture({ huge = false } = {}) {
  const events = [];
  const matrix = [
    ['学籍番号', '名前', 'フリガナ', 'SA/TA', '2026/01/01'],
    ['A001', '=1+1', 'ﾔﾏﾀﾞ', '', '〇'],
  ];
  const sourceSheet = {
    getLastColumn: () => huge ? 10000 : 5,
    getLastRow: () => huge ? 100000 : 2,
    getRange: () => {
      events.push('source-range');
      assert.equal(huge, false, '巨大な範囲へアクセスしてはいけない');
      return {
        getDisplayValues: () => matrix,
        getValues: () => [matrix[0]],
      };
    },
    getFilter: () => { events.push('filter'); return null; },
    showRows: () => events.push('show-rows'),
  };
  const ui = {
    Button: { YES: 'YES' },
    ButtonSet: { YES_NO: 'YES_NO', OK: 'OK' },
    alert: (_title, message) => { events.push(message); return 'YES'; },
    showModalDialog: () => events.push('dialog'),
  };
  const spreadsheet = {
    getActiveSheet: () => ({
      getName: () => config.controlSheetName,
      getRange: () => ({ getDisplayValues: () => [['2026/01/01', '2026/01/01']] }),
    }),
    getSheetByName: () => sourceSheet,
    getSpreadsheetTimeZone: () => 'Asia/Tokyo',
  };
  const context = load({
    SpreadsheetApp: {
      getUi: () => ui,
      getActiveSpreadsheet: () => spreadsheet,
      flush: () => events.push('flush'),
    },
    LockService: {
      getDocumentLock: () => { events.push('lock'); throw new Error('unexpected lock'); },
    },
    HtmlService: {
      createTemplateFromFile: () => { events.push('template'); throw new Error('unexpected template'); },
    },
  });
  return { context, events };
}

for (const huge of [false, true]) {
  test(`${huge ? '巨大範囲' : '数式形式'}は公開実行関数でも副作用の前に停止する`, () => {
    const { context, events } = workflowFixture({ huge });
    context.runOC_KakuteiExtractor();
    assert(events.some((event) => event.includes(huge ? '上限' : '数式')));
    for (const forbidden of ['filter', 'show-rows', 'dialog', 'lock', 'template', 'flush']) {
      assert(!events.includes(forbidden), forbidden);
    }
    if (huge) assert(!events.includes('source-range'));
  });
}
