import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/design/theme.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/presentation/history_panel.dart';
import 'support.dart';

void main() {
  OperationReport reportWith(int count) => OperationReport(
    id: 'compact',
    plan: plan(action: RoleAction.remove),
    rows: List.generate(
      count,
      (i) => OperationRow(Member('${2000 + i}', '対象者 $i'), Outcome.success, ''),
    ),
    startedAt: start,
    finishedAt: start,
  );

  KakuteiController controller() => KakuteiController(
    gateway: FakeGateway(),
    credentials: MemoryStore(),
    journal: StoredOperationJournal(MemoryStore()),
    exports: FakeExport(),
  );

  Widget detailsApp(OperationReport report, KakuteiController c) => MaterialApp(
    theme: buildTheme().copyWith(platform: TargetPlatform.windows),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ReportDetails(report: report, controller: c),
        ),
      ),
    ),
  );

  testWidgets('履歴の詳細は少人数のとき余分な高さを取らない', (tester) async {
    final c = controller();
    await tester.pumpWidget(detailsApp(reportWith(2), c));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ReportDetails)).height, lessThan(240));
    final rows = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const ValueKey('operation_rows_compact')),
        matching: find.byType(ListView),
      ),
    );
    expect(rows.controller!.position.maxScrollExtent, 0);
    expect(find.text('成功'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('履歴の成否表示を隠さず、50人を重複なくページ送りできる', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = controller();
    for (final size in [
      const Size(1366, 768),
      const Size(390, 844),
      const Size(320, 740),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(detailsApp(reportWith(50), c));
      await tester.pumpAndSettle();
      final all = <String>[];
      final pager = find.byKey(const ValueKey('operation-pagination-compact'));
      for (var page = 0; page < 50; page++) {
        final rows = tester.widget<ListView>(
          find.descendant(
            of: find.byKey(const ValueKey('operation_rows_compact')),
            matching: find.byType(ListView),
          ),
        );
        expect(
          rows.controller!.position.maxScrollExtent,
          lessThanOrEqualTo(.5),
        );
        for (final element in find.text('成功').evaluate()) {
          final outcome = find.byWidget(element.widget);
          final rect = tester.getRect(outcome);
          expect(
            rect.right,
            lessThanOrEqualTo(tester.getRect(pager).right - 12),
          );
          expect(rect.bottom, lessThanOrEqualTo(tester.getRect(pager).top));
          all.add((element.widget.key! as ValueKey<String>).value);
        }
        final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
        if (tester.widget<IconButton>(next).onPressed == null) break;
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(all.length, 50);
      expect(all.toSet().length, 50);
      expect(find.text('対象者 49'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('解除の保存結果をスクロール後に展開して名前と結果を表示する', (tester) async {
    final journal = StoredOperationJournal(MemoryStore());
    final p = plan(action: RoleAction.remove, targets: [bob]);
    await journal.save(
      OperationReport(
        id: 'fixture',
        plan: p,
        rows: [OperationRow(bob, Outcome.success, '')],
        startedAt: start,
        finishedAt: start,
      ),
    );
    final restored = (await journal.load()).single;
    expect(restored.rows.single.member.id, bob.id);
    final c = KakuteiController(
      gateway: FakeGateway(),
      credentials: MemoryStore(),
      journal: journal,
      exports: FakeExport(),
    );
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 900),
                ReportPanel(report: restored, controller: c),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('対象者ごとの結果'));
    await tester.pumpAndSettle();
    expect(find.text(bob.displayName), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    c.dispose();
  });
}
