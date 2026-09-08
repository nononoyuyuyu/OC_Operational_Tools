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
vm.runInContext(
  source + `\n;globalThis.__test = {
    ocKakuteiGetConfig_,
    ocKakuteiParseStrictInputDate_,
    ocKakuteiParseHeaderDate_,
    ocKakuteiValidateMaximumDateRange_,
    ocKakuteiFindHeaderRow_,
    ocKakuteiAnalyzeHeaders_,
    ocKakuteiValidateStudentRows_,
    ocKakuteiBuildCopyOutput_,
    ocKakuteiNormalizeIdentifier_,
    ocKakuteiNormalizeOptionalDateValue_,
    ocKakuteiValidateOptionalAsciiAlphanumeric_,
    ocKakuteiIsAllowedFurigana_,
    ocKakuteiValidateFurigana_,
    ocKakuteiBuildCellA1_,
    ocKakuteiSha256Hex_
  };`,
  context,
);

const t = context.__test;
const config = t.ocKakuteiGetConfig_();

function expectUserError(fn, fragments) {
  let caught = null;
  try {
    fn();
  } catch (error) {
    caught = error;
  }
  assert(caught, '利用者向け例外が発生しませんでした');
  assert.strictEqual(caught.name, 'OC_KakuteiExtractorUserError');
  for (const fragment of Array.isArray(fragments) ? fragments : [fragments]) {
    assert(caught.message.includes(fragment), `${fragment}: ${caught.message}`);
  }
  return caught;
}

function parseInput(text) {
  return t.ocKakuteiParseStrictInputDate_(text, '試験日');
}

function jstDate(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day - 1, 15));
}

assert.deepStrictEqual(
  Array.from(config.fixedHeaders),
  ['学籍番号', '名前', 'フリガナ', 'SA/TA'],
);
assert.deepStrictEqual(
  Array.from(config.allowedStatusValues),
  ['〇', '×', 'キャンセル', '確定', '定員'],
);
assert.strictEqual(config.allowBlankSaTa, true);
assert.strictEqual(config.allowBlankDateValues, true);
assert.strictEqual(t.ocKakuteiBuildCellA1_(38, 5), 'F38');

// 日付入力と3年上限。
assert.strictEqual(parseInput('2026/04/19').canonicalText, '2026/04/19');
expectUserError(() => parseInput('2026/4/19'), 'yyyy/MM/dd');
expectUserError(() => parseInput('2026/02/30'), '存在しません');
t.ocKakuteiValidateMaximumDateRange_(config, parseInput('2026/04/19'), parseInput('2029/04/18'));
expectUserError(
  () => t.ocKakuteiValidateMaximumDateRange_(config, parseInput('2026/04/19'), parseInput('2029/04/19')),
  '最大3年間',
);

// 識別子と任意セルの正規化。
assert.strictEqual(t.ocKakuteiNormalizeIdentifier_('　Ｂ６５６５５\u200B '), 'B65655');
assert.strictEqual(t.ocKakuteiValidateOptionalAsciiAlphanumeric_('', 4, 9, 'SA/TA'), '');
assert.strictEqual(t.ocKakuteiNormalizeOptionalDateValue_('　\u200B '), '');
expectUserError(
  () => t.ocKakuteiValidateOptionalAsciiAlphanumeric_('B65-655', 4, 9, 'SA/TA'),
  ['対象セル J4', '空欄または半角英数字'],
);

// フリガナの氏名用文字。
for (const value of [
  'ｻﾄｳ ﾀﾛｳ',
  'ﾏﾘｱ-ｶﾞﾙｼｱ',
  'LEE-JUN HO',
  "O'NEIL.JR/2",
  'ﾁｬﾝ(LEE)',
  'A&B_C, JR',
]) {
  assert.strictEqual(t.ocKakuteiIsAllowedFurigana_(value), true, value);
  assert.doesNotThrow(() => t.ocKakuteiValidateFurigana_(value, 38, 5));
}
for (const value of ['ジョン', 'さとう', 'LEE　JUN', '=IMPORTXML', 'A#B', 'A\tB', 'A\nB']) {
  assert.strictEqual(t.ocKakuteiIsAllowedFurigana_(value), false, value);
}
expectUserError(
  () => t.ocKakuteiValidateFurigana_('ジョン', 38, 5),
  ['対象セル F38', '使用できない文字'],
);

// 任意行のヘッダー検出と、内部Date値による日付列識別。
const headers = [
  '登録・\n更新日', '記入者', '番号', '学籍番号', '名前', 'フリガナ',
  '性別', '学科名', '学年', 'SA/TA', '備考', '4/19', '4/26', '5/10',
];
const rawHeaders = headers.slice();
rawHeaders[11] = jstDate(2026, 4, 19);
rawHeaders[12] = jstDate(2026, 4, 26);
rawHeaders[13] = jstDate(2026, 5, 10);
const location = t.ocKakuteiFindHeaderRow_(
  config,
  [['タイトル'], ['更新日'], headers],
  1,
);
assert.deepStrictEqual(JSON.parse(JSON.stringify(location)), { matrixIndex: 2, rowNumber: 3 });

const headerInfo = t.ocKakuteiAnalyzeHeaders_(
  config,
  headers,
  rawHeaders,
  'Asia/Tokyo',
  parseInput('2026/04/19'),
  parseInput('2026/05/10'),
);
assert.deepStrictEqual(Array.from(headerInfo.fixedIndexes), [3, 4, 5, 9]);
assert.deepStrictEqual(
  Array.from(headerInfo.targetDateColumns, (column) => column.index),
  [11, 12, 13],
);
assert.strictEqual(
  t.ocKakuteiParseHeaderDate_('4/19', jstDate(2026, 4, 19), 'Asia/Tokyo', 12).canonicalText,
  '2026/04/19',
);

function makeActualRow(values) {
  const row = Array(headers.length).fill('');
  for (const [index, value] of Object.entries(values)) {
    row[Number(index)] = value;
  }
  return row.slice(headerInfo.dataStartIndex, headerInfo.dataStartIndex + headerInfo.dataWidth);
}

// 追加列、SA/TA空欄、日付空欄を含めて列位置を維持する。
const rows = [
  makeActualRow({
    3: 'A002', 4: '山田 花子', 5: 'ﾔﾏﾀﾞ-ﾊﾅｺ', 9: '',
    10: '追加列\n改行', 11: '', 12: '〇', 13: '',
  }),
  makeActualRow({
    3: 'A001', 4: '佐藤 太郎', 5: 'LEE-JUN HO', 9: '　Ｂ６５６５５ ',
    11: '確定', 12: '', 13: 'キャンセル',
  }),
];
const result = t.ocKakuteiValidateStudentRows_(config, rows, headerInfo, 4, true);
assert.strictEqual(result.studentCount, 2);
assert.strictEqual(
  t.ocKakuteiBuildCopyOutput_(result.records).copyText,
  'A001\t佐藤 太郎\tLEE-JUN HO\tB65655\t確定\t\tキャンセル\n' +
  'A002\t山田 花子\tﾔﾏﾀﾞ-ﾊﾅｺ\t\t\t〇\t',
);
expectUserError(
  () => t.ocKakuteiValidateStudentRows_(config, [makeActualRow({
    3: 'A003', 4: '鈴木', 5: 'ｽｽﾞｷ', 9: '', 11: '', 12: '未定', 13: '',
  })], headerInfo, 6, false),
  ['許可されていない値', '未定'],
);

// 最大構成。
function makeMaxHeaderInfo(dateCount) {
  const fixedIndexes = [0, 1, 2, 3];
  const targetDateColumns = Array.from({ length: dateCount }, (_, index) => ({
    index: index + 4,
    confirmationLabel: `日付${index + 1}`,
  }));
  return {
    fixedIndexes,
    studentIdIndex: 0,
    nameIndex: 1,
    furiganaIndex: 2,
    saTaIndex: 3,
    targetDateColumns,
    outputIndexes: fixedIndexes.concat(targetDateColumns.map((column) => column.index)),
    dataStartIndex: 0,
    dataWidth: 4 + dateCount,
  };
}
const maxInfo = makeMaxHeaderInfo(300);
const maxRows = Array.from({ length: 1000 }, (_, index) => [
  `A${String(index).padStart(4, '0')}`,
  `学生${index}`,
  index % 5 === 0 ? `STUDENT-${index}` : 'ｶﾞｸｾｲ',
  index % 2 ? `B${String(index).padStart(5, '0')}` : '',
].concat(Array.from({ length: 300 }, (_, dateIndex) => (
  (index + dateIndex) % 3 === 0 ? '' : '〇'
))));
const startedAt = Date.now();
const maxResult = t.ocKakuteiValidateStudentRows_(config, maxRows, maxInfo, 4, true);
const maxOutput = t.ocKakuteiBuildCopyOutput_(maxResult.records);
assert.strictEqual(maxOutput.copyText.split('\n').length, 1000);
assert.strictEqual(maxOutput.copyText.split('\n')[0].split('\t').length, 304);
assert.strictEqual(
  t.ocKakuteiSha256Hex_('abc'),
  'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
);

console.log(`単体検証: PASS（抽出・許容文字・最大構成 ${Date.now() - startedAt} ms）`);
