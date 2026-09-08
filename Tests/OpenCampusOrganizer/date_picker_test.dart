import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/features/kakutei/data/saved_settings.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';

void main() {
  for (final size in [const Size(1366, 768), const Size(320, 740)]) {
    testWidgets('日時欄のタップ、キャンセル、決定、終了リセット $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = fixtures.controller(FakeGateway());
      await c.connect('fixture-only', remember: false);
      c.updateInput(
        const ExtractionInput(
          start: '2026/01/01 09:00',
          end: '2026/01/02 18:30',
        ),
      );
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      final start = find.widgetWithText(TextField, '開始日時（JST）');
      final end = find.widgetWithText(TextField, '終了日時（任意）');
      for (final field in [start, end]) {
        expect(tester.widget<TextField>(field).readOnly, isTrue);
        await tester.tap(field);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(find.text('キャンセル'));
        await tester.pumpAndSettle();
      }
      expect(c.settings.input.end, '2026/01/02 18:30');
      await tester.tap(end);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(c.settings.input.end, '2026/01/02 18:30');
      await tester.tap(find.byTooltip('終了日時をリセット'));
      await tester.pumpAndSettle();
      expect(c.settings.input.end, '');
      expect(tester.widget<TextField>(end).controller!.text, '');
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(c.settings.input.start, '2026/01/02 09:00');
      expect(c.settings.input.end, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
