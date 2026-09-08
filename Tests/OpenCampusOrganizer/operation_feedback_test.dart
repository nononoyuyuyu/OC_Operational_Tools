import 'date_field_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';

final feedback = find.byKey(const ValueKey('operation-feedback'));

void main() {
  testWidgets(
    '解除対象が0人の通知は全配色で共通欄に表示し、直前の入力エラーを残さない',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeGateway();
      final c = fixtures.controller(gateway);
      final appearance = AppearanceController(MemoryStore());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(
        OcoApp(modules: [KakuteiModule(c)], appearance: appearance),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      await restoreDateField(
        tester,
        find.widgetWithText(TextField, '開始日時（JST）'),
        '入力エラー',
      );
      await tester.tap(find.text('対象者を確認'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final workspace = find.byKey(const ValueKey('kakutei-workspace'));
      final before = tester.getRect(workspace);

      for (final value in AppAppearance.values) {
        await appearance.select(value);
        await tester.pumpAndSettle();
        await tester.tap(find.text('このロールを一括解除…'));
        await tester.pumpAndSettle();
        final notice = find.descendant(
          of: feedback,
          matching: find.text('操作対象者はいません。'),
        );
        expect(notice, findsOneWidget, reason: value.label);
        expect(
          tester.widget<Text>(notice).style!.color,
          Theme.of(tester.element(feedback)).colorScheme.onSurfaceVariant,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(tester.getRect(workspace), before);
        expect(gateway.writes, 0);
        expect(c.latestReport, isNull);
        await tester.tap(notice);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(find.byTooltip('通知を閉じる'));
        await tester.pumpAndSettle();
        expect(find.text('操作対象者はいません。'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final size in [const Size(1366, 768), const Size(320, 740)]) {
    testWidgets(
      '長い通知は欄内で最後までスクロールでき、押しても別画面を開かない $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final gateway = FakeGateway();
        final c = fixtures.controller(gateway);
        await c.connect('fixture-only', remember: false);
        await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('確定ロール').first);
        await tester.pumpAndSettle();
        final workspace = find.byKey(const ValueKey('kakutei-workspace'));
        final before = tester.getRect(workspace);
        final feedbackRect = tester.getRect(feedback);
        final longError = '${'権限設定を確認してください。\n' * 12}通知の末尾';
        gateway.onContext = () => throw AppFailure(longError);
        await c.checkPermissions();
        await tester.pumpAndSettle();
        await tester.tapAt(feedbackRect.center);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        final scrollable = find.descendant(
          of: feedback,
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0));
        await tester.drag(scrollable, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(position.maxScrollExtent, 1));
        expect(tester.getRect(workspace), before);
        expect(tester.getRect(feedback), feedbackRect);

        gateway.onContext = () => throw const AppFailure('次の通知');
        await c.checkPermissions();
        await tester.pumpAndSettle();
        expect(find.text('次の通知').hitTestable(), findsOneWidget);
        expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    '招待URLのコピー通知も設定画面の共通欄に表示する',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final c = fixtures.controller(FakeGateway());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bot招待URLをコピー'));
      await tester.tap(find.text('Bot招待URLをコピー'));
      await tester.pumpAndSettle();
      expect(copied, c.bot!.inviteUrl.toString());
      expect(
        find.descendant(of: feedback, matching: find.text('招待URLをコピーしました。')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
