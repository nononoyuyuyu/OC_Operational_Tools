const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(path.join(__dirname, '../../Source/OC_KakuteiExtractor/Code.gs'), 'utf8');
const t = vm.createContext({});
vm.runInContext(source, t);
const config = t.ocKakuteiGetConfig_();

function fixture(count, dates, width = dates + 7) {
  const firstColumn = 3;
  const info = {
    dataStartIndex: firstColumn, dataWidth: dates + 4,
    studentIdIndex: firstColumn, nameIndex: firstColumn + 1,
    furiganaIndex: firstColumn + 2, saTaIndex: firstColumn + 3,
    outputIndexes: Array.from({ length: dates + 4 }, (_, i) => firstColumn + i),
    targetDateColumns: Array.from({ length: dates }, (_, i) => ({
      index: firstColumn + 4 + i, confirmationLabel: `2026/01/${i + 1}`,
    })),
  };
  const matrix = [Array(width).fill('ヘッダー外の情報')];
  for (let i = 0; i < count; i++) {
    const row = Array(width).fill('対象外の値');
    row.splice(firstColumn, dates + 4, ` Ａ${String(i).padStart(3, '0')} `, `学生 ${i}`, 'ﾔﾏﾀﾞ', ' ＳＡ ', ...Array(dates).fill('〇'));
    matrix.push(Object.freeze(row));
  }
  return { matrix: Object.freeze(matrix), info };
}

for (const [count, dates, width] of [[1, 2, 14], [1000, 300, 307], [999, 300, 500]]) {
  test(`元マトリクスの直接参照と従来の切り出しで出力・指紋が一致: ${count}人/${dates}日`, () => {
    const { matrix, info } = fixture(count, dates, width);
    const sliced = matrix.slice(1).map(row => row.slice(info.dataStartIndex, info.dataStartIndex + info.dataWidth));
    const oldShape = t.ocKakuteiValidateStudentRows_(config, sliced, info, 2, true);
    const direct = t.ocKakuteiValidateStudentRows_(config, matrix, info, 2, true, 1, 0);
    const initial = t.ocKakuteiValidateStudentRows_(config, matrix, info, 2, false, 1, 0);
    assert.equal(t.ocKakuteiBuildCopyOutput_(direct.records).copyText, t.ocKakuteiBuildCopyOutput_(oldShape.records).copyText);
    const expectedFingerprint = JSON.stringify(Array.from(direct.records, row => [row.sourceRow, ...row.values]));
    assert.equal(JSON.stringify(direct.fingerprintRows), expectedFingerprint);
    assert.equal(JSON.stringify(initial.fingerprintRows), expectedFingerprint);
    const digest = rows => crypto.createHash('sha256').update(JSON.stringify({ relevantRows: rows })).digest('hex');
    assert.equal(digest(direct.fingerprintRows), digest(oldShape.fingerprintRows));
    assert.equal(digest(initial.fingerprintRows), digest(oldShape.fingerprintRows));
    assert.equal(initial.records.length, 0);
    assert.equal(direct.records[0].values[0], 'A000');
    assert.equal(matrix[1][3], ' Ａ000 ');
    assert.equal(matrix[1][4], '学生 0');
  });
}

test('直接参照でも危険な値の実セル位置を報告し、対象外列は検証へ混ぜない', () => {
  const { matrix, info } = fixture(1, 1, 20);
  const changed = matrix.map(row => Array.from(row));
  changed[1][0] = '=対象外';
  assert.doesNotThrow(() => t.ocKakuteiValidateStudentRows_(config, changed, info, 35, true, 1, 0));
  changed[1][4] = '\u200B=1+1';
  assert.throws(() => t.ocKakuteiValidateStudentRows_(config, changed, info, 35, true, 1, 0), /対象セル E35/);
});
