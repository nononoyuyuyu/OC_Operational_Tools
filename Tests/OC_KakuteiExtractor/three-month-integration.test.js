'use strict';
// 既存の必須GASチェックから新ツールの全検証を実行する統合入口。
// ワークフロー名を変更せず、両GASの同一プロジェクト配置も検証する。
require('../OC_ThreeMonthBlankHighlighter/logic.test.js');
require('../OC_ThreeMonthBlankHighlighter/workflow.test.js');
require('../OC_ThreeMonthBlankHighlighter/safety.test.js');
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('既存抽出GASと空欄判定GASを同一プロジェクトで読込可能', () => {
  const root = path.resolve(__dirname, '../../Source');
  const sources = ['OC_KakuteiExtractor', 'OC_ThreeMonthBlankHighlighter'].flatMap(name =>
    fs.readdirSync(path.join(root, name)).filter(file => file.endsWith('.gs'))
      .map(file => fs.readFileSync(path.join(root, name, file), 'utf8')));
  const ctx = vm.createContext({});
  vm.runInContext(sources.join('\n'), ctx);
  assert.equal(typeof ctx.runOC_KakuteiExtractor, 'function');
  assert.equal(typeof ctx.runOC_ThreeMonthBlankHighlighter, 'function');
  assert.equal(typeof ctx.previewOC_ThreeMonthBlankHighlighter, 'function');
});
