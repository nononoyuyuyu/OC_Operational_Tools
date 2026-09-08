'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../..');
const sourceDir = path.join(root, 'Source/OC_KakuteiExtractor');
const code = fs.readFileSync(path.join(sourceDir, 'Code.gs'), 'utf8');
const html = fs.readFileSync(path.join(sourceDir, 'コピー確認.html'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(sourceDir, 'appsscript.json'), 'utf8'));

new vm.Script(code, { filename: 'Code.gs' });
new vm.Script(`${code}\n${code}`, { filename: 'Code.gs（二重結合試験）' });

const scriptBlocks = Array.from(html.matchAll(/<script>([\s\S]*?)<\/script>/g));
assert.strictEqual(scriptBlocks.length, 1, 'インラインscript要素は1つである必要があります');
new vm.Script(scriptBlocks[0][1], { filename: 'コピー確認.html内JavaScript' });

assert(!/^const\s+/m.test(code), 'トップレベルconstを宣言してはいけません');
assert(!/^let\s+/m.test(code), 'トップレベルletを宣言してはいけません');
assert(!/^var\s+/m.test(code), 'トップレベルvarを宣言してはいけません');
assert(!/OC_KAKUTEI_CONFIG_/.test(code), '旧トップレベル定数名を残してはいけません');
assert(/function\s+runOC_KakuteiExtractor\s*\(/.test(code));
assert(/allowBlankSaTa:\s*true/.test(code));
assert(/allowBlankDateValues:\s*true/.test(code));
assert(/function\s+ocKakuteiIsAllowedFurigana_\s*\(/.test(code));
assert(/function\s+ocKakuteiResetSourceSheetView_\s*\(/.test(code));
assert(/function\s+ocKakuteiCaptureStandardFilterState_\s*\(/.test(code));
assert(/function\s+ocKakuteiRevealManualHiddenRowsSafely_\s*\(/.test(code));
assert(/function\s+ocKakuteiClearStandardFilterCriteriaSafely_\s*\(/.test(code));
assert(/function\s+ocKakuteiRestoreStandardFilterCriteria_\s*\(/.test(code));

// フィルタ本体を削除してはならない。条件解除APIだけを使用する。
assert(!/filter\.remove\s*\(/.test(code), '通常フィルタ本体を削除してはいけません');
assert(/removeColumnFilterCriteria\s*\(/.test(code), '列ごとのフィルタ条件解除が必要です');
assert(/setColumnFilterCriteria\s*\(/.test(code), '失敗時の条件復元が必要です');
assert(/getColumnFilterCriteria\s*\(/.test(code), '既存条件の退避が必要です');
assert(/\.copy\(\)\.build\(\)/.test(code), 'フィルタ条件を独立コピーしてください');
assert(/getProtections\s*\(\s*SpreadsheetApp\.ProtectionType\.SHEET/.test(code));
assert(/フィルタ自体を残したまま各列の絞り込み条件だけを解除/.test(code));
assert(/フィルタ本体と絞り込み条件は変更していません/.test(code));

// 行グループAPIは呼ばず、開閉状態を保持する。
assert(!/expandRowGroupsUpToDepth\s*\(/.test(code));
assert(!/expandAllRowGroups\s*\(/.test(code));
assert(!/collapseAllRowGroups\s*\(/.test(code));
assert(!/maxRowGroupDepth/.test(code));
assert(/行グループは通常の非表示行とは別機能として扱い、開閉状態を変更しません/.test(code));

// 手動非表示行の再表示を、フィルタ条件解除より先に確定する。
const showRowsPosition = code.indexOf('sourceSheet.showRows(1, maxRows)');
const clearCriteriaPosition = code.indexOf('filterState.filter.removeColumnFilterCriteria');
assert(showRowsPosition >= 0 && clearCriteriaPosition >= 0);
assert(showRowsPosition < clearCriteriaPosition, '行再表示はフィルタ条件解除より先に行ってください');

const forbiddenCodePatterns = [
  /\bLogger\s*\./,
  /\bconsole\s*\./,
  /\bUrlFetchApp\b/,
  /\bPropertiesService\b/,
  /\bCacheService\b/,
  /\bDriveApp\b/,
  /\bGmailApp\b/,
];
for (const pattern of forbiddenCodePatterns) {
  assert(!pattern.test(code), `禁止APIが含まれています: ${pattern}`);
}

assert(!/google\.script\.run/.test(html), 'コピー前にサーバー通信してはいけません');
assert(!/<script\s+[^>]*src=/i.test(html), '外部scriptを読み込んではいけません');
assert(!/<link\s+[^>]*href=/i.test(html), '外部スタイル等を読み込んではいけません');
assert(/<\?=\s*copyText\s*\?>/.test(html));
assert(!/<\?!=\s*copyText\s*\?>/.test(html));
assert(/navigator\.clipboard\.writeText\(copySource\.value\)/.test(html));
assert(/document\.execCommand\('copy'\)/.test(html));

assert.strictEqual(manifest.timeZone, 'Asia/Tokyo');
assert.strictEqual(manifest.runtimeVersion, 'V8');
assert.deepStrictEqual(manifest.dependencies, {});
assert.deepStrictEqual(
  manifest.oauthScopes,
  [
    'https://www.googleapis.com/auth/script.container.ui',
    'https://www.googleapis.com/auth/spreadsheets.currentonly',
  ],
);

console.log('静的・セキュリティ検証: PASS（行グループ非操作・フィルタ本体保持）');
