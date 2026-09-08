import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/scoped_store.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/presentation/operation_dialogs.dart';
import 'support.dart';

void main() {
  test('保存キーは機能ごとの名前空間から外に出ない', () async {
    final store = MemoryStore();
    final a = ScopedStore(store, 'kakutei_v1');
    final b = ScopedStore(store, 'another_v1');
    await a.write('operation_1', 'first');
    await b.write('operation_1', 'second');
    expect(await a.read('operation_1'), 'first');
    expect(await b.read('operation_1'), 'second');
    expect(await a.keys('operation_'), ['operation_1']);
  });
  test('添付のみの投稿を本文の取得失敗と誤認しない', () async {
    final g = FakeGateway()
      ..messagePages = [
        [
          Message(
            '100',
            '4',
            alice,
            start,
            attachments: ['https://example.com/attachment'],
          ),
        ],
      ];
    final result = await ExtractionService(g).extract(
      guild,
      conditions(content: true),
      bot,
      Cancellation(),
      noProgress,
    );
    expect(result.messages.single.content, isEmpty);
    expect(result.messages.single.attachments, isEmpty);
  });
  testWidgets('解除は対象一覧とチェックだけで確認し、文字入力を要求しない', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final g = FakeGateway()
      ..memberPages = [
        [bob],
      ];
    final c = KakuteiController(
      gateway: g,
      credentials: MemoryStore(),
      journal: FakeJournal(),
      exports: FakeExport(),
    );
    await c.connect('fixture-only', remember: false);
    await c.previewRemoval();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => confirmOperation(context, c, c.removalPlan!),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('ロール解除の確認'), findsOneWidget);
    expect(g.writes, 0);
    expect(find.byType(TextField), findsNothing);
    final execute = find.widgetWithText(FilledButton, '一括解除する');
    expect(tester.widget<FilledButton>(execute).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(execute).onPressed, isNotNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(execute).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(execute).onPressed, isNotNull);
    await tester.tap(execute);
    await tester.pumpAndSettle();
    expect(g.writes, 1);
    expect(c.latestReport!.count(Outcome.success), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
