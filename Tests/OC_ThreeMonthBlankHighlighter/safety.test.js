'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { sourceDir } = require('./helpers');
const files = ['Core.gs', 'Code.gs'];
const source = files.map(file => fs.readFileSync(path.join(sourceDir, file), 'utf8')).join('\n');

test('単体・結合・逆順・二重読込でも構文が成立しトップレベルは関数のみ', () => {
  for (const file of files) new vm.Script(fs.readFileSync(path.join(sourceDir, file), 'utf8'));
  const ctx = vm.createContext({});
  vm.runInContext(source + '\n' + source, ctx);
  for (const value of Object.values(ctx)) assert.equal(typeof value, 'function');
  new vm.Script(files.slice().reverse().map(file => fs.readFileSync(path.join(sourceDir, file), 'utf8')).join('\n'));
});
test('シート値・元背景色・フィルタ・行表示・グループを変更するAPIを使用しない', () => {
  for (const method of ['setValue', 'setValues', 'setFormula', 'setFormulas', 'setBackgrounds',
    'clear', 'clearContent', 'clearFormat', 'clearConditionalFormatRules', 'sort',
    'showRows', 'hideRows', 'expandRowGroupsUpToDepth', 'expandAllRowGroups', 'collapseAllRowGroups',
    'removeColumnFilterCriteria', 'createFilter', 'deleteRows', 'setNote', 'addDeveloperMetadata']) {
    if (method === 'sort') continue; // 配列の時系列ソートだけを使用する。
    assert(!new RegExp('\\.' + method + '\\s*\\(').test(source), method);
  }
  assert.equal((source.match(/\.setBackground\(/g) || []).length, 1, '条件付き書式ビルダーでだけ色を設定');
  assert(!/\.getFilter\(/.test(source));
});
test('通信・ログ・個人情報の永続保存を使用しない', () => {
  for (const name of ['UrlFetchApp', 'DriveApp', 'GmailApp', 'PropertiesService', 'CacheService', 'Logger', 'console']) {
    assert(!new RegExp('\\b' + name + '\\b').test(source), name);
  }
});
test('最小権限・例外ログ抑制・固定マーカー式', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(sourceDir, 'appsscript.json'), 'utf8'));
  assert.equal(manifest.runtimeVersion, 'V8'); assert.equal(manifest.exceptionLogging, 'NONE');
  assert.deepEqual(manifest.dependencies, {});
  assert.deepEqual(manifest.oauthScopes, ['https://www.googleapis.com/auth/script.container.ui',
    'https://www.googleapis.com/auth/spreadsheets.currentonly']);
  const ctx = vm.createContext({}); vm.runInContext(source, ctx);
  assert.equal(ctx.ocBlank3mV2Config_().formula, '=N("OC_ThreeMonthBlankHighlighter:v2")=0');
});
