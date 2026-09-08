import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/app/history_page.dart';
import 'package:open_campus_organizer/core/tool_module.dart';
import 'package:open_campus_organizer/core/tool_activity.dart';
import 'package:open_campus_organizer/design/theme.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'support.dart';
import 'history_storage_test.dart' show ObservedStore;

KakuteiController historyController() => KakuteiController(
  gateway: FakeGateway(),
  credentials: MemoryStore(),
  journal: StoredOperationJournal(MemoryStore()),
  exports: FakeExport(),
);

class PagedHistoryFixture extends ChangeNotifier
    implements ToolModule, PagedActivityModule {
  PagedHistoryFixture(this.id, this.minutes);
  @override
  final String id;
  final List<int> minutes;
  var loaded = 2;
  @override
  String get title => id;
  @override
  List<ToolActivity> get activities => minutes
      .take(loaded)
      .map(
        (minute) => ToolActivity(
          id: '$minute',
          at: start.add(Duration(minutes: minute)),
          action: '操作',
          subject: '対象',
          context: '架空',
          result: '成功',
        ),
      )
      .toList();
  @override
  bool get hasMoreActivities => loaded < minutes.length;
  @override
  int get activityTotal => minutes.length;
  @override
  Future<void> loadMoreActivities() async {
    loaded = minutes.length;
    notifyListeners();
  }

  @override
  Widget buildActivityDetails(String id) => const SizedBox();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<String> visibleKeys(WidgetTester tester, String prefix) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith(prefix),
      ),
    )
    .map((w) => (w.key as ValueKey<String>).value)
    .toList();

OperationReport historyReport(int index, {String reason = ''}) =>
    OperationReport(
      id: 'report$index',
      plan: plan(action: RoleAction.remove),
      rows: List.generate(
        50,
        (i) => OperationRow(
          Member('${2000 + i}', '対象者 $i'),
          reason.isEmpty ? Outcome.success : Outcome.failed,
          reason,
        ),
      ),
      startedAt: start.add(Duration(minutes: index)),
      finishedAt: start.add(Duration(minutes: index)),
    );

void main() {
  testWidgets('複数ツールの未取得履歴を挟んでも全体の日時順とページの重複排除を保つ', (tester) async {
    final modules = [
      PagedHistoryFixture('a', [10, 9, 8, 7]),
      PagedHistoryFixture('b', [4, 3, 2, 1]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: Listenable.merge(modules),
            builder: (_, _) => HistoryPage(modules: modules),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final seen = <String>[];
    for (var page = 0; page < 20; page++) {
      seen.addAll(visibleKeys(tester, 'activity_'));
      final next = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '次の履歴',
        ),
      );
      if (next.onPressed == null) break;
      await tester.tap(find.byTooltip('次の履歴'));
      await tester.pumpAndSettle();
    }
    expect(seen, [
      'activity_a_10',
      'activity_a_9',
      'activity_a_8',
      'activity_a_7',
      'activity_b_4',
      'activity_b_3',
      'activity_b_2',
      'activity_b_1',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (final module in modules) {
      module.dispose();
    }
  });

  testWidgets(
    '未表示の履歴詳細を読まず、30件の境界を越えてページ送りできる',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ObservedStore();
      final writer = StoredOperationJournal(store);
      for (var i = 0; i < 65; i++) {
        await writer.save(historyReport(i));
      }
      store.reads.clear();
      final c = KakuteiController(
        gateway: FakeGateway(),
        credentials: MemoryStore(),
        journal: StoredOperationJournal(store),
        exports: FakeExport(),
      );
      await c.initialize();
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      expect(store.reads.where((key) => key.startsWith('operation_')), isEmpty);
      expect(c.history.length, 30);
      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      expect(store.reads.where((key) => key.startsWith('operation_')), [
        'operation_report64',
      ]);
      final seen = <String>[];
      for (var page = 0; page < 100; page++) {
        seen.addAll(visibleKeys(tester, 'activity_'));
        final next = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == '次の履歴',
          ),
        );
        if (next.onPressed == null) break;
        await tester.tap(find.byTooltip('次の履歴'));
        await tester.pumpAndSettle();
      }
      expect(
        seen,
        List.generate(65, (i) => 'activity_kakutei_report${64 - i}'),
      );
      expect(c.history.length, 65);
      expect(
        store.reads.where((key) => key.startsWith('operation_')).length,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('activity_kakutei_report0')));
      await tester.pumpAndSettle();
      expect(store.reads.where((key) => key.startsWith('operation_')), [
        'operation_report64',
        'operation_report0',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '履歴と詳細を横並びから片側表示へ切り替えても両方のページを保つ',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = historyController();
      for (final report in List.generate(30, historyReport)) {
        await c.journal.save(report);
      }
      await c.initialize();
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-history')));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('history-list-panel'));
      final details = find.byKey(const ValueKey('history-details-panel'));
      expect(find.byKey(const ValueKey('history-view-tabs')), findsNothing);
      expect(
        tester.getRect(list).right,
        lessThan(tester.getRect(details).left),
      );
      final initialCount = visibleKeys(tester, 'activity_').length;
      expect(initialCount, inInclusiveRange(1, 10));
      await tester.tap(find.byTooltip('次の履歴'));
      await tester.pumpAndSettle();
      final historyAnchor = visibleKeys(tester, 'activity_').first;
      await tester.tap(find.byKey(ValueKey(historyAnchor)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: details, matching: find.byTooltip('次のページ')),
      );
      await tester.pumpAndSettle();
      final rowAnchor = visibleKeys(tester, 'operation-row-').first;
      expect(rowAnchor.endsWith('-2000'), isFalse);

      for (final size in [
        const Size(1366, 500),
        const Size(1366, 360),
        const Size(1366, 768),
        const Size(390, 844),
        const Size(320, 740),
        const Size(1366, 768),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          visibleKeys(tester, 'operation-row-').first,
          rowAnchor,
          reason: '$size',
        );
        expect(tester.takeException(), isNull, reason: '$size');
        if (size.height >= 700) {
          final pager = find.descendant(
            of: details,
            matching: find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'operation-pagination-',
                  ),
            ),
          );
          expect(
            tester.getRect(pager).bottom,
            lessThanOrEqualTo(
              tester
                  .getRect(find.byKey(const ValueKey('operation-feedback')))
                  .top,
            ),
          );
        }
        if (size.width < 860) {
          expect(list, findsNothing);
          await tester.tap(find.widgetWithText(ChoiceChip, '履歴'));
          await tester.pumpAndSettle();
          expect(visibleKeys(tester, 'activity_').first, historyAnchor);
          expect(details, findsNothing);
          await tester.tap(find.widgetWithText(ChoiceChip, '詳細'));
          await tester.pumpAndSettle();
          expect(visibleKeys(tester, 'operation-row-').first, rowAnchor);
        }
      }
      expect(visibleKeys(tester, 'activity_').first, historyAnchor);
      tester.view.physicalSize = const Size(1366, 1080);
      await tester.pumpAndSettle();
      expect(
        visibleKeys(tester, 'activity_').length,
        greaterThan(initialCount),
      );
      expect(visibleKeys(tester, 'activity_').first, historyAnchor);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('スマートフォンの文字拡大でも長い理由を省略せず結果とページ操作を確認できる', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = historyController();
    final reason = 'ロールの管理権限を確認してください。' * 8;
    await c.journal.save(historyReport(0, reason: reason));
    await c.initialize();
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('操作履歴').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity_kakutei_report0')));
    await tester.pumpAndSettle();
    final reasonText = tester.widget<Text>(find.text(reason));
    expect(find.textContaining('CSV'), findsNothing);
    expect(reasonText.maxLines, isNull);
    expect(reasonText.overflow, isNull);
    expect(find.text('失敗'), findsOneWidget);
    final pager = find.byKey(const ValueKey('operation-pagination-report0'));
    await tester.ensureVisible(pager);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: pager, matching: find.byTooltip('次のページ')),
    );
    await tester.pumpAndSettle();
    expect(visibleKeys(tester, 'operation-row-'), [
      'operation-row-report0-2001',
    ]);
    await tester.ensureVisible(pager);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: pager, matching: find.byTooltip('前のページ')),
    );
    await tester.pumpAndSettle();
    expect(visibleKeys(tester, 'operation-row-'), [
      'operation-row-report0-2000',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
