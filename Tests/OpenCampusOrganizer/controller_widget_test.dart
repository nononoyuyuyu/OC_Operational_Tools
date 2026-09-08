import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

KakuteiController controller(FakeGateway gateway) => KakuteiController(
  gateway: gateway,
  credentials: MemoryStore(),
  journal: FakeJournal(),
  exports: FakeExport(),
);

void main() {
  test('条件変更後はCSVも付与も実行できない', () async {
    final g = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final c = controller(g);
    await c.connect('fixture-only', remember: false);
    await c.extract(conditions());
    expect(c.extraction, isNotNull);
    final oldPlan = c.additionPlan();
    c.invalidate();
    await c.exportUsers();
    expect(c.error, isNotNull);
    expect((c.exports as FakeExport).bytes, isNull);
    await c.execute(oldPlan);
    expect(c.error, isNotNull);
    expect(g.writes, 0);
    c.dispose();
  });
  test('処理を二重に要求しても二重付与にならない', () async {
    final g = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final c = controller(g);
    await c.connect('fixture-only', remember: false);
    await c.extract(conditions());
    final p = c.additionPlan();
    final first = c.execute(p);
    final second = c.execute(p);
    await Future.wait([first, second]);
    expect(g.writes, 1);
    expect(c.extraction, isNull);
    c.dispose();
  });
  test('切断すると以前のプレビューが無効になる', () async {
    final g = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final c = controller(g);
    await c.connect('fixture-only', remember: false);
    await c.extract(conditions());
    final p = c.additionPlan();
    await c.disconnect();
    await c.execute(p);
    expect(g.writes, 0);
    expect(c.connected, isFalse);
    c.dispose();
  });
  for (final size in [
    const Size(1440, 1000),
    const Size(390, 844),
    const Size(320, 740),
  ]) {
    testWidgets('ツール・結果・設定の表示が収まる $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = FakeGateway()
        ..messagePages = [
          [Message('100', '4', alice, start)],
        ];
      final c = controller(g);
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      expect(find.text('ツールを開く'), findsNothing);
      expect(find.text('ホーム'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      expect(find.text('抽出条件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await c.extract(conditions());
      await tester.pumpAndSettle();
      expect(find.textContaining('付与予定'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const PageStorageKey('kakutei')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      await c.execute(c.additionPlan());
      await tester.pumpAndSettle();
      expect(find.text('処理終了'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('設定').first);
      await tester.pumpAndSettle();
      expect(find.text('Discord接続'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('スマートフォンの大きな文字設定でも画面が収まる', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = controller(FakeGateway());
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
