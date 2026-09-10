'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, utilities, plain } = require('./helpers');

function environment(options = {}) {
  let now = options.now || '2026-09-10T15:00:00Z';
  class Clock extends Date { constructor(...args) { super(...(args.length ? args : [now])); } }
  const s = { alerts: [], writes: [], reads: 0, ruleReads: 0, flushes: 0, locked: false, releases: 0,
    backgrounds: { A3: '#ffeeaa', A4: '#ff0000' } };
  // 物理順が異なる5・6月列を追加。当月9/13は空欄、翌月10/1の予定は無視する。
  s.headers = ['登録・\n更新日', '学籍番号', '名前', '4/19', '7/01', '8/30', '9/13', '5/10', '6/07', '10/01'];
  s.matrix = [Array(10).fill(''), s.headers,
    ['2026/04/05', 'PERSONAL-ID1', '個人情報氏名1', '', '', '', '', '', '', '予定'],
    ['2026/04/05', 'PERSONAL-ID2', '個人情報氏名2', '', '', '〇', '', '', '', '']];
  s.registrations = [['2026/04/05'], ['2026/04/05']];
  s.rawHeaders = ['登録・\n更新日', '学籍番号', '名前',
    new Date('2026-04-18T15:00Z'), new Date('2026-06-30T15:00Z'),
    new Date('2026-08-29T15:00Z'), new Date('2026-09-12T15:00Z'),
    new Date('2026-05-09T15:00Z'), new Date('2026-06-06T15:00Z'), new Date('2026-09-30T15:00Z')];
  function range(a1, row, column, countRows, countColumns) {
    const canonical = a1 ? a1.replace(/^([A-Z]+\d+):\1$/, '$1') : `${row}:${column}:${countRows}:${countColumns}`;
    return { getSheet: () => sheet, getA1Notation: () => canonical,
      canEdit: () => !options.uneditable,
      isPartOfMerge: () => !!options.merged,
      getDisplayValues() {
        s.reads += 1;
        if (options.mutateBeforeSecondRead && s.reads === 2) options.mutateBeforeSecondRead(s);
        return s.matrix.map(item => item.slice());
      },
      getValues: () => row === 2 ? [s.rawHeaders.slice()] : s.registrations.map(item => item.slice()) };
  }
  function color(value, kind = 'RGB') {
    return { getColorType: () => kind,
      asRgbColor: () => ({ asHexString: () => value }),
      asThemeColor: () => ({ getThemeColorType: () => value }) };
  }
  function rule(formula, addresses, settings = {}) {
    return { formula, addresses, settings,
      getRanges: () => addresses.map(item => range(item)),
      getGradientCondition: () => settings.gradient || null,
      getBooleanCondition: () => settings.gradient ? null : ({
        getCriteriaType: () => settings.type || 'CUSTOM_FORMULA', getCriteriaValues: () => [formula],
        getBackgroundObject: () => color(settings.color || '#ff0000', settings.colorType || 'RGB'),
        getFontColorObject: () => settings.fontColor ? color(settings.fontColor) : null,
        getBold: () => settings.bold == null ? null : settings.bold,
        getItalic: () => settings.italic == null ? null : settings.italic,
        getStrikethrough: () => null, getUnderline: () => null }) };
  }
  s.rule = rule;
  const gradient = {};
  for (const p of ['Min', 'Mid', 'Max']) {
    gradient[`get${p}ColorObject`] = () => p === 'Mid' ? null : color(p === 'Min' ? '#ffffff' : '#00ff00');
    gradient[`get${p}Type`] = () => p === 'Mid' ? null : 'NUMBER';
    gradient[`get${p}Value`] = () => p === 'Min' ? '0' : p === 'Max' ? '100' : '';
  }
  s.userRules = [rule('=A3>0', ['A3:A4'], { color: 'ACCENT1', colorType: 'THEME', bold: true }),
    rule('', ['C3:C4'], { gradient })];
  s.rules = s.userRules.slice();
  const sheet = {
    getSheetId: () => 2,
    getLastRow: () => options.huge ? 500001 : s.matrix.length,
    getLastColumn: () => s.headers.length,
    getRange: (row, column, nRows, nColumns) => range(null, row, column, nRows, nColumns),
    getRangeList: addresses => ({ getRanges: () => addresses.map(item => range(item)) }),
    getProtections: () => options.protected ? [{ isWarningOnly: () => false, canEdit: () => false }] : [],
    getConditionalFormatRules() {
      s.ruleReads += 1;
      if (options.mutateRulesAtRead === s.ruleReads) s.rules.push(rule('=TRUE', ['D3']));
      if (options.failRecoveryRead && s.writes.length) throw Error('状態取得失敗');
      return s.rules.slice();
    },
    setConditionalFormatRules(rules) {
      s.writes.push(rules.slice());
      if (options.writeFailsBeforeApply && s.writes.length === 1) throw Error('権限不足');
      if (options.restoreFails && s.writes.length > 1) throw Error('復元失敗');
      s.rules = rules.slice();
      if (options.writeFailsAfterApply && s.writes.length === 1) throw Error('通信失敗');
      if (options.concurrentAtWrite && s.writes.length === 1) {
        s.rules.push(rule('=A1<>0', ['C1'])); throw Error('競合');
      }
    } };
  const spreadsheet = { getSheetByName: () => options.missingSheet ? null : sheet,
    getId: () => 'FILE', getSpreadsheetTimeZone: () => options.timeZone || 'Asia/Tokyo' };
  const ui = { Button: { YES: 'YES' }, ButtonSet: { YES_NO: 'YES_NO', OK: 'OK' },
    alert(title, message, buttons) {
      assert.equal(s.locked, false, 'ダイアログ中にロックを保持してはいけない');
      s.alerts.push({ title, message, buttons });
      if (buttons === 'YES_NO' && options.onConfirm) options.onConfirm(s);
      if (buttons === 'YES_NO' && options.nextDay) now = '2026-09-11T15:00:00Z';
      if (buttons === 'YES_NO' && options.nextInstant) now = options.nextInstant;
      return options.cancel ? 'NO' : 'YES';
    } };
  const ctx = load({ Date: Clock, Utilities: utilities,
    SpreadsheetApp: { BooleanCriteria: { CUSTOM_FORMULA: 'CUSTOM_FORMULA' }, ProtectionType: { SHEET: 'SHEET' },
      getUi: () => ui, getActiveSpreadsheet: () => spreadsheet,
      flush() { s.flushes += 1; if (options.flushFails && s.flushes === 1) throw Error('反映失敗'); },
      newConditionalFormatRule() {
        let formula, ranges, background;
        return { whenFormulaSatisfied(value) { formula = value; return this; },
          setBackground(value) { background = value; return this; },
          setRanges(value) { ranges = value; return this; },
          build() { return rule(formula, ranges.map(item => item.getA1Notation()), { color: background }); } };
      } },
    LockService: { getDocumentLock: () => ({
      tryLock() { s.locked = !options.lockFail; return s.locked; },
      hasLock: () => s.locked, releaseLock() { s.locked = false; s.releases += 1; } }) } });
  s.marker = ctx.ocBlank3mV2Config_().formula;
  s.run = () => ctx.runOC_ThreeMonthBlankHighlighter();
  s.preview = () => ctx.previewOC_ThreeMonthBlankHighlighter();
  s.ctx = ctx;
  return s;
}

test('対象A3だけに専用ルール・元背景色と他ルールの相対順保持', () => {
  const s = environment(); const background = plain(s.backgrounds); s.run();
  assert.equal(s.writes.length, 1);
  assert.equal(s.rules[0].formula, s.marker);
  assert.deepEqual(plain(s.rules[0].addresses), ['A3']);
  assert.equal(s.rules[1], s.userRules[0]); assert.equal(s.rules[2], s.userRules[1]);
  assert.deepEqual(s.backgrounds, background); assert.equal(s.releases, 1);
  const messages = s.alerts.map(item => item.message).join('');
  assert(!messages.includes('個人情報')); assert(!messages.includes('PERSONAL-ID'));
});
test('過去区間の後に非空欄があるA4は新規対象にしない', () => {
  const s = environment(); s.run();
  assert(!s.rules[0].addresses.includes('A4'));
});
test('再実行時に非該当になった専用表示を解除し、手動の赤は残す', () => {
  const s = environment(); s.run(); s.matrix[2][5] = '確定'; s.run();
  assert.equal(s.writes.length, 2); assert.deepEqual(s.rules, s.userRules);
  assert.equal(s.backgrounds.A4, '#ff0000');
});
test('該当0件でも既存専用ルールを削除する', () => {
  const s = environment(); s.matrix[2][5] = 'キャンセル';
  s.rules.unshift(s.rule(s.marker, ['A3:A4'])); s.run();
  assert.equal(s.writes.length, 1); assert.deepEqual(s.rules, s.userRules);
});
test('データ行削除後も専用ルールだけを外す', () => {
  const s = environment(); s.run(); s.matrix = s.matrix.slice(0, 2); s.registrations = []; s.run();
  assert.equal(s.writes.length, 2); assert.deepEqual(s.rules, s.userRules);
});
test('同一結果の再実行は書き込まない', () => {
  const s = environment(); s.run(); s.run(); assert.equal(s.writes.length, 1);
  assert(s.alerts.at(-1).message.includes('変更はありません'));
});
test('マーカーに似た他ルールは削除しない', () => {
  const s = environment(); const other = s.rule(s.marker + '+0', ['A4']); s.rules.push(other); s.run();
  assert(s.rules.includes(other));
});
test('重複した専用ルールを1件に整理', () => {
  const s = environment(); s.rules.push(s.rule(s.marker, ['A4']), s.rule(s.marker, ['A3'])); s.run();
  assert.equal(s.rules.filter(item => item.formula === s.marker).length, 1);
});
test('確認のみはロック取得・書込みなし', () => {
  const s = environment(); s.preview(); assert.equal(s.writes.length, 0); assert.equal(s.releases, 0);
  assert.equal(s.alerts.length, 1); assert(s.alerts[0].title.includes('確認のみ'));
});
test('キャンセルは書込みなし', () => {
  const s = environment({ cancel: true }); s.run(); assert.equal(s.writes.length, 0); assert.equal(s.releases, 0);
});
test('確認中の対象データ変更は書込み前に停止', () => {
  const s = environment({ onConfirm: state => { state.matrix[2][5] = '〇'; } }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('確認中の登録日変更は書込み前に停止', () => {
  const s = environment({ onConfirm: state => { state.registrations[0][0] = '2026/06/01'; } }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('確認中の他ルール変更を検出', () => {
  const s = environment({ onConfirm: state => { state.rules[0].settings.bold = false; } }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('確認中に日付が変われば再確認を要求', () => {
  const s = environment({ nextDay: true }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('確認中の対象外列の変更では継続', () => {
  const s = environment({ onConfirm: state => { state.matrix[2][2] = '氏名編集'; } }); s.run();
  assert.equal(s.writes.length, 1);
});
for (const [name, options, text] of [
  ['ロック競合', { lockFail: true }, '別の処理'],
  ['シート保護', { protected: true }, 'シート保護'],
  ['範囲保護', { uneditable: true }, '保護セル'],
  ['結合セル', { merged: true }, '結合セル'],
  ['読取上限', { huge: true }, '500,000'],
  ['対象シートなし', { missingSheet: true }, '見つかりません'],
  ['直前のルール競合', { mutateRulesAtRead: 3 }, '上書きせず']
]) test(`${name}では無変更で中止`, () => {
  const s = environment(options); s.run(); assert.equal(s.writes.length, 0);
  assert(s.alerts.at(-1).message.includes(text), s.alerts.at(-1).message);
});
test('更新前に失敗した場合は不要な復元をしない', () => {
  const s = environment({ writeFailsBeforeApply: true }); s.run();
  assert.equal(s.writes.length, 1); assert.deepEqual(s.rules, s.userRules);
  assert(s.alerts.at(-1).message.includes('実行前の状態です'));
});
for (const key of ['writeFailsAfterApply', 'flushFails']) test(`${key}: 実行前ルールへ復元`, () => {
  const s = environment({ [key]: true }); s.run(); assert.equal(s.writes.length, 2);
  assert.deepEqual(s.rules, s.userRules); assert(s.alerts.at(-1).message.includes('復元しました'));
});
test('更新中に別編集があれば復元で上書きしない', () => {
  const s = environment({ concurrentAtWrite: true }); s.run(); assert.equal(s.writes.length, 1);
  assert(s.rules.some(item => item.formula === '=A1<>0'));
  assert(s.alerts.at(-1).message.includes('自動復元していません'));
});
test('復元失敗は成功と報告しない', () => {
  const s = environment({ flushFails: true, restoreFails: true }); s.run();
  assert.equal(s.writes.length, 2); assert(s.alerts.at(-1).message.includes('手動で確認'));
  assert(!s.alerts.at(-1).message.includes('復元しました'));
});
test('状態読取失敗時は復元できたと偽らない', () => {
  const s = environment({ failRecoveryRead: true }); s.run(); assert.equal(s.writes.length, 1);
  assert(s.alerts.at(-1).message.includes('確認できません'));
});

test('提示3例を同じシートで判定し1例目だけを赤表示', () => {
  const s = environment();
  s.registrations[1][0] = '2026/06/01'; s.matrix[3][5] = '';
  s.matrix.push(['2026/04/05', 'PERSONAL-ID3', '個人情報氏名3', '', '', '', '〇', '', '', '']);
  s.registrations.push(['2026/04/05']);
  s.run();
  assert.deepEqual(plain(s.rules[0].addresses), ['A3']);
  assert(s.alerts[0].message.includes('2026/08/31（先月末）'));
  assert(s.alerts[0].message.includes('2026/09/30（当月末）'));
  assert(s.alerts[0].message.includes('2026/05/01～2026/08/31（連続4か月）'));
});
test('当月の未来日への記入を再実行すると専用赤表示を解除', () => {
  const s = environment(); s.run(); s.matrix[2][6] = '予定'; s.run();
  assert.equal(s.writes.length, 2); assert.deepEqual(s.rules, s.userRules);
});
test('確認中の当月未来日の変更も無変更で停止', () => {
  const s = environment({ onConfirm: state => { state.matrix[2][6] = '予定'; } }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('確認中の翌月の予定変更は対象外なので継続', () => {
  const s = environment({ onConfirm: state => { state.matrix[2][9] = '変更'; } }); s.run();
  assert.equal(s.writes.length, 1);
});
test('シート時間で月をまたぐ確認は再実行を要求', () => {
  const s = environment({ now: '2026-09-30T14:59:59Z', nextInstant: '2026-09-30T15:00:00Z' }); s.run();
  assert.equal(s.writes.length, 0); assert(s.alerts.at(-1).message.includes('確認中'));
});
test('旧Coreと新Codeの混在では書き込まない', () => {
  const s = environment(); const getCore = s.ctx.ocBlank3mV2Core_;
  s.ctx.ocBlank3mV2Core_ = () => ({ ...getCore(), version: undefined });
  s.run(); assert.equal(s.writes.length, 0); assert(s.alerts[0].message.includes('版が異なります'));
});
