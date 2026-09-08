'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(
  path.resolve(__dirname, '../../Source/OC_KakuteiExtractor/Code.gs'),
  'utf8',
);

function buildCriteria(id) {
  return {
    id,
    copy() {
      return {
        build() {
          return { id: `${id}-copy` };
        },
      };
    },
  };
}

function buildEnvironment(options = {}) {
  const state = {
    events: [],
    removedColumns: [],
    restoredColumns: [],
    filterRemoveCalled: false,
    rowGroupMethodCalled: false,
    flushCount: 0,
  };

  const criteriaByColumn = new Map([
    [3, buildCriteria('列3条件')],
    [5, buildCriteria('列5条件')],
  ]);
  let removeCallCount = 0;

  const filter = options.noFilter ? null : {
    getRange() {
      state.events.push('フィルタ範囲取得');
      return {
        getColumn: () => 2,
        getNumColumns: () => 5,
      };
    },
    getColumnFilterCriteria(columnPosition) {
      state.events.push(`条件取得:${columnPosition}`);
      return criteriaByColumn.get(columnPosition) || null;
    },
    removeColumnFilterCriteria(columnPosition) {
      removeCallCount += 1;
      state.events.push(`条件解除:${columnPosition}`);
      state.removedColumns.push(columnPosition);
      if (options.failClearAt === removeCallCount) {
        throw new Error('条件解除失敗');
      }
    },
    setColumnFilterCriteria(columnPosition, criteria) {
      state.events.push(`条件復元:${columnPosition}:${criteria.id}`);
      state.restoredColumns.push([columnPosition, criteria.id]);
      if (options.failRestore && state.restoredColumns.length === 1) {
        throw new Error('条件復元失敗');
      }
    },
    remove() {
      state.filterRemoveCalled = true;
      throw new Error('フィルタ本体を削除してはならない');
    },
  };

  const protections = options.protectionCheckThrows
    ? null
    : (options.blockingProtection
      ? [{ isWarningOnly: () => false, canEdit: () => false }]
      : [{ isWarningOnly: () => true, canEdit: () => false }]);

  const sourceSheet = {
    getFilter() {
      state.events.push('フィルタ取得');
      if (options.filterReadThrows) {
        throw new Error('フィルタ読取失敗');
      }
      return filter;
    },
    getProtections(type) {
      state.events.push(`保護確認:${type}`);
      if (options.protectionCheckThrows) {
        throw new Error('保護確認失敗');
      }
      return protections;
    },
    getMaxRows() {
      state.events.push('最大行取得');
      return 1000;
    },
    showRows(start, count) {
      state.events.push(`行再表示:${start}:${count}`);
      if (options.showRowsThrows) {
        throw new Error('行再表示失敗');
      }
    },
    // 行グループAPIは、存在しないグループでも環境によって例外となる。
    // 新実装が呼び出していないことを検証するため、呼ばれたら失敗させる。
    expandRowGroupsUpToDepth() {
      state.rowGroupMethodCalled = true;
      throw new Error('行グループAPIを呼び出してはならない');
    },
    expandAllRowGroups() {
      state.rowGroupMethodCalled = true;
      throw new Error('行グループAPIを呼び出してはならない');
    },
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
      flush() {
        state.flushCount += 1;
        state.events.push(`flush:${state.flushCount}`);
        if (options.flushThrowsAt === state.flushCount) {
          throw new Error('flush失敗');
        }
      },
    },
  };

  vm.createContext(context);
  vm.runInContext(
    source + `\n;globalThis.__test = {
      ocKakuteiGetConfig_,
      ocKakuteiResetSourceSheetView_,
      ocKakuteiCaptureStandardFilterState_,
      ocKakuteiAssertViewResetPermission_,
      ocKakuteiRevealManualHiddenRowsSafely_,
      ocKakuteiClearStandardFilterCriteriaSafely_
    };`,
    context,
  );

  return {
    t: context.__test,
    config: context.__test.ocKakuteiGetConfig_(),
    sourceSheet,
    state,
  };
}

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

// 正常系: 手動非表示行を再表示した後、フィルタ条件だけを解除する。
{
  const { t, config, sourceSheet, state } = buildEnvironment();
  t.ocKakuteiResetSourceSheetView_(config, sourceSheet);
  assert.deepStrictEqual(state.removedColumns, [3, 5]);
  assert.deepStrictEqual(state.restoredColumns, []);
  assert.strictEqual(state.filterRemoveCalled, false);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.flushCount, 2);
  assert(state.events.indexOf('行再表示:1:1000') < state.events.indexOf('条件解除:3'));
}

// フィルタがない場合も行再表示だけを実行し、行グループには触れない。
{
  const { t, config, sourceSheet, state } = buildEnvironment({ noFilter: true });
  t.ocKakuteiResetSourceSheetView_(config, sourceSheet);
  assert.deepStrictEqual(state.removedColumns, []);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.flushCount, 1);
}

// シート保護で変更不可なら、行にもフィルタ条件にも触れず中止する。
{
  const { t, config, sourceSheet, state } = buildEnvironment({ blockingProtection: true });
  expectUserError(
    () => t.ocKakuteiResetSourceSheetView_(config, sourceSheet),
    ['シート保護', 'フィルタ本体、絞り込み条件、行の表示状態は変更していません'],
  );
  assert(!state.events.some((event) => event.startsWith('行再表示:')));
  assert(!state.events.some((event) => event.startsWith('条件解除:')));
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

// 行再表示に失敗してもフィルタ条件は変更しない。
{
  const { t, config, sourceSheet, state } = buildEnvironment({ showRowsThrows: true });
  expectUserError(
    () => t.ocKakuteiResetSourceSheetView_(config, sourceSheet),
    [
      '手動で非表示にされた行を再表示できませんでした',
      'フィルタ本体と絞り込み条件は変更していません',
      '行グループの開閉状態も変更していません',
    ],
  );
  assert.deepStrictEqual(state.removedColumns, []);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

// 条件解除の途中で失敗した場合は、退避した全条件を復元する。
{
  const { t, config, sourceSheet, state } = buildEnvironment({ failClearAt: 2 });
  expectUserError(
    () => t.ocKakuteiResetSourceSheetView_(config, sourceSheet),
    ['元の条件へ復元しました', 'フィルタ本体は削除していません'],
  );
  assert.deepStrictEqual(state.removedColumns, [3, 5]);
  assert.deepStrictEqual(state.restoredColumns, [
    [3, '列3条件-copy'],
    [5, '列5条件-copy'],
  ]);
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

// 復元にも失敗した場合は、フィルタ本体を残したまま明示する。
{
  const { t, config, sourceSheet, state } = buildEnvironment({
    failClearAt: 2,
    failRestore: true,
  });
  expectUserError(
    () => t.ocKakuteiResetSourceSheetView_(config, sourceSheet),
    ['一部の条件を元へ戻せない可能性があります', 'フィルタ本体は削除していません'],
  );
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

// フィルタ状態を読み取れない場合も無変更で中止する。
{
  const { t, config, sourceSheet, state } = buildEnvironment({ filterReadThrows: true });
  expectUserError(
    () => t.ocKakuteiResetSourceSheetView_(config, sourceSheet),
    ['通常フィルタの状態を読み取れませんでした', '行の表示状態は変更していません'],
  );
  assert(!state.events.some((event) => event.startsWith('行再表示:')));
  assert.strictEqual(state.rowGroupMethodCalled, false);
  assert.strictEqual(state.filterRemoveCalled, false);
}

console.log('表示状態検証: PASS（行グループ非操作・フィルタ本体保持）');
