'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, formatDate, plain } = require('./helpers');
const context = load();
const core = context.ocBlank3mV2Core_();
const config = context.ocBlank3mV2Config_();
const day = text => core.parseDate(text, text, 'Asia/Tokyo', formatDate);
const dates = texts => texts.map((text, column) => ({ column, date: day(text) }));
const registration = day('2026/04/01');

test('過去3か月の区間後に非空欄があれば対象外', () => {
  assert.equal(core.trailing(['', '', '', '', '〇'], dates([
    '2026/04/01', '2026/05/01', '2026/06/01', '2026/07/01', '2026/08/01']), registration, 3), null);
});
test('過去区間を破棄した後の短い末尾空欄も対象外', () => {
  assert.equal(core.trailing(['', '', '', '', '×', '', ''], dates([
    '2026/04/01', '2026/05/01', '2026/06/01', '2026/07/01', '2026/08/01',
    '2026/08/15', '2026/09/01']), registration, 3), null);
});
test('非空欄後に新しく3か月空欄が続けば再度対象', () => {
  const actual = core.trailing(['', '', '', '', '確定', '', '', '', ''], dates([
    '2026/04/01', '2026/05/01', '2026/06/01', '2026/07/01', '2026/08/01',
    '2026/09/01', '2026/10/01', '2026/11/01', '2026/12/01']), registration, 3);
  assert.deepEqual(plain(actual), { start: '2026/09/01', end: '2026/12/01', threshold: '2026/12/01' });
});
test('最初から空欄なら登録日起算・閾値を超えても最後の列まで評価', () => {
  const actual = core.trailing(['', '', ''], dates(['2026/04/19', '2026/07/01', '2026/08/30']), registration, 3);
  assert.equal(actual.start, '2026/04/01');
  assert.equal(actual.end, '2026/08/30');
});
test('登録日より前の非空欄は影響しない', () => {
  assert(core.trailing(['〇', '', ''], dates(['2026/03/01', '2026/04/19', '2026/07/01']), registration, 3));
});
test('日付列のない期間を今日まで水増ししない', () => {
  assert.equal(core.trailing(['', ''], dates(['2026/04/19', '2026/06/30']), registration, 3), null);
});
test('対象列なし・全非空欄・最新非空欄を除外', () => {
  assert.equal(core.trailing([], [], registration, 3), null);
  assert.equal(core.trailing(['〇'], dates(['2026/07/01']), registration, 3), null);
  assert.equal(core.trailing([''], dates(['2026/03/01']), registration, 3), null);
});
test('空白とゼロ幅文字は空欄・0やfalseやエラー表示は非空欄', () => {
  for (const value of ['', '　 \u200b\ufeff\u2060', '\n\t']) assert(core.blank(value));
  for (const value of ['〇', '×', 'キャンセル', '確定', '定員', '未定', '0', false, '#N/A']) assert.equal(core.blank(value), false);
});
test('3暦月の境界と月末・うるう年', () => {
  for (const [start, end] of [['2026/01/31', '2026/04/30'], ['2023/11/30', '2024/02/29'],
    ['2024/11/30', '2025/02/28'], ['2026/12/31', '2027/03/31']]) {
    assert.equal(core.addMonths(day(start), 3).text, end);
  }
});
test('Date型をシートのタイムゾーンで解釈', () => {
  const instant = new Date('2026-04-18T15:00:00.000Z');
  assert.equal(core.parseDate(instant, '4/19', 'Asia/Tokyo', formatDate).text, '2026/04/19');
  assert.equal(core.parseDate(instant, '4/18', 'America/Los_Angeles', formatDate).text, '2026/04/18');
});
test('日付・日時文字列・和文形式', () => {
  for (const text of ['2026/4/1', '2026-04-01', '2026/4/1 10:30:59', '2026-04-01T10:30', '2026年4月1日 10:30']) {
    assert.equal(day(text).text, '2026/04/01');
  }
});
test('不正日付・不正時刻・曖昧な日付は拒否', () => {
  for (const text of ['2026/02/30', '2026/13/01', '2026/00/01', '2026/4/1 24:00',
    '2026/4/1 10:60', '2026/4/1 10:30:60', '2026/04-01', '4/19', '2026-04-01T10:30Z', '0099/01/01']) {
    assert.equal(day(text), null, text);
  }
  assert.equal(core.parseDate(46000, '4/19', 'Asia/Tokyo', formatDate), null);
  assert.equal(core.parseDate(new Date(NaN), '', 'Asia/Tokyo', formatDate), null);
});
const headers = ['登録・\n更新日', '記入者', '番号', '学籍番号', '名前', 'フリガナ', '性別',
  '学科名', '学年', 'SA/TA', '電話番号', 'メールアドレス', '通学時間（分）', '誕生日',
  '出身地', '出身高校', '話せる言語', '備考', '顔写真', 'ポジション\n備考', '遅刻\n回数', 'キャンセル',
  '4/19', '7/01', '8/30', '9/13'];
function input() {
  const raw = headers.slice();
  ['2026-04-18T15:00Z', '2026-06-30T15:00Z', '2026-08-29T15:00Z', '2026-09-12T15:00Z']
    .forEach((value, i) => { raw[22 + i] = new Date(value); });
  const row = Array(headers.length).fill(''); row[0] = '2026/4/1'; row[3] = 'A001'; row[4] = '架空氏名';
  row[17] = '追加列の改行\n値'; row[25] = '未来の予定';
  const matrix = [Array(headers.length).fill(''), headers, row];
  return { matrix, location: core.findHeader(matrix), rawHeaders: raw,
    registrationValues: [['2026/4/1']], timeZone: 'Asia/Tokyo', today: day('2026/09/11') };
}
test('実列構成・2行目ヘッダー・3行目データ・未来列除外', () => {
  const result = core.analyze(input(), config, formatDate);
  assert.equal(result.matches.length, 1);
  assert.equal(result.matches[0].cell, 'A3');
  assert.equal(result.latest, '2026/08/30');
  assert.equal(result.futureCount, 1);
  assert(!result.fingerprint.includes('架空氏名'));
  assert(!result.fingerprint.includes('A001'));
});
test('日付列の物理順に依存しない', () => {
  const a = input();
  [a.rawHeaders[22], a.rawHeaders[24]] = [a.rawHeaders[24], a.rawHeaders[22]];
  a.matrix[2][22] = '〇';
  assert.equal(core.analyze(a, config, formatDate).matches.length, 0);
});
test('任意行・列順・登録日別名を検出', () => {
  for (const name of ['登録日', '登録更新日', '登録・更新日時', '登録・\n更新日']) {
    assert.deepEqual(plain(core.findHeader([[], [], ['学籍番号', '補助', name]])),
      { row: 3, idColumn: 0, registrationColumn: 2 });
  }
});
test('ヘッダーなし・複数候補・必須列重複は停止', () => {
  assert.throws(() => core.findHeader([['名前']]), /特定できません/);
  assert.throws(() => core.findHeader([['学籍番号', '登録日'], ['学籍番号', '登録日']]), /候補数: 2/);
  assert.throws(() => core.findHeader([['学籍番号', '登録日', '登録・更新日']]), /重複/);
});
test('日付型と文字列の同日重複・年なし・無効日付ヘッダーは停止', () => {
  for (const value of ['2026/04/19', '4/19', '2026/02/30']) {
    const a = input(); a.rawHeaders[23] = value;
    assert.throws(() => core.analyze(a, config, formatDate), /重複|確定できません/);
  }
});
test('登録日空欄・不正・未来・登録後の日付なしを集計し個人情報を出さない', () => {
  for (const [value, reason] of [['', '登録日空欄'], ['不正個人情報', '登録日不正'],
    ['2026/10/01', '登録日が未来'], ['2026/09/01', '登録後の対象日付なし']]) {
    const a = input(); a.registrationValues = [[value]];
    const result = core.analyze(a, config, formatDate);
    assert.deepEqual(plain(result.skipped), [{ cell: 'A3', reason }]);
    assert.equal(result.matches.length, 0);
    assert(!result.fingerprint.includes('不正個人情報'));
  }
});
test('一致しない日付しかない場合は保守的に停止', () => {
  const a = input(); a.today = day('2026/01/01');
  assert.throws(() => core.analyze(a, config, formatDate), /基準日以前/);
});
test('全学生行が削除された再実行も該当0件を返す', () => {
  const a = input(); a.matrix = a.matrix.slice(0, 2); a.registrationValues = [];
  const result = core.analyze(a, config, formatDate);
  assert.equal(result.students, 0); assert.equal(result.matches.length, 0);
});
test('1,000学生・300日付列の全件判定と各上限超過', () => {
  const dateLabels = Array.from({ length: 300 }, (_, i) => {
    const d = new Date(Date.UTC(2025, 0, i + 1)); return formatDate(d, 'UTC', 'yyyy/MM/dd');
  });
  const h = ['登録日', '学籍番号', ...dateLabels];
  const rows = Array.from({ length: 1000 }, (_, i) => ['2025/01/01', `A${i}`, ...Array(300).fill('')]);
  const a = { matrix: [h, ...rows], location: { row: 1, registrationColumn: 0, idColumn: 1 },
    rawHeaders: h, registrationValues: Array.from({ length: 1000 }, () => ['2025/01/01']),
    today: day('2026/09/11'), timeZone: 'Asia/Tokyo' };
  assert.equal(core.analyze(a, config, formatDate).matches.length, 1000);
  a.matrix.push(rows[0]); a.registrationValues.push(['2025/01/01']);
  assert.throws(() => core.analyze(a, config, formatDate), /1000人/);
  a.rawHeaders.push('2025/12/31');
  assert.throws(() => core.analyze(a, config, formatDate), /300列/);
});
test('連続セルだけを範囲化・複数文字列番地', () => {
  assert.deepEqual(plain(core.segments([{ row: 6 }, { row: 3 }, { row: 4 }, { row: 9 }], 26)),
    ['AA3:AA4', 'AA6:AA6', 'AA9:AA9']);
});
test('4,096パターンを独立した順方向オラクルで照合', () => {
  const ds = dates(Array.from({ length: 12 }, (_, i) => `2025/${String(i + 1).padStart(2, '0')}/01`));
  for (let mask = 0; mask < 4096; mask += 1) {
    const row = ds.map((_, i) => mask & (1 << i) ? '〇' : '');
    let start = '2025/01/01';
    for (let i = 0; i < row.length; i += 1) {
      if (row[i]) start = null;
      else if (start === null) start = ds[i].date.text;
    }
    const expected = start !== null && Number(start.slice(5, 7)) + 3 <= 12;
    assert.equal(Boolean(core.trailing(row, ds, day('2025/01/01'), 3)), expected, String(mask));
  }
});
