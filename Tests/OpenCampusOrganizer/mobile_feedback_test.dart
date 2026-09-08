import 'date_field_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/mobile_feedback_host.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/tool_status.dart';
import 'package:open_campus_organizer/design/theme.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';

final popup = find.byKey(const ValueKey('mobile-feedback'));

void main() {
  testWidgets('通常通知は6秒で消え、同文の再通知・別画面での操作も一度ずつ表示する', (tester) async {
    var dismissed = 0;
    var taps = 0;
    Future<void> mount(int revision, {String page = '画面A'}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: MobileFeedbackHost(
              enabled: true,
              feedback: [
                ToolFeedback(
                  sourceId: 'test',
                  revision: revision,
                  message: '解除する対象者はいません。',
                  dismiss: () => dismissed++,
                ),
              ],
              child: Align(
                alignment: Alignment.topCenter,
                child: TextButton(onPressed: () => taps++, child: Text(page)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await mount(1);
    expect(popup, findsOneWidget);
    await tester.tap(find.text('画面A'));
    expect(taps, 1, reason: '通知で他の操作をブロックしない');
    await tester.tap(find.text('解除する対象者はいません。'));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await mount(1, page: '画面B');
    await tester.pump(const Duration(seconds: 2));
    expect(popup, findsNothing);
    expect(dismissed, 1);
    await mount(1);
    expect(popup, findsNothing, reason: '画面の切り替えで過去の通知を再表示しない');
    await mount(2);
    expect(popup, findsOneWidget, reason: '同じ文面でも新しい操作なら表示する');
    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pump();
    expect(popup, findsNothing);
    expect(dismissed, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('進捗は自動で消えず中止でき、失敗の全文と次の通知を確認できる', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var cancelled = 0;
    var dismissed = 0;
    Future<void> mount(ToolFeedback value, {bool accessible = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppAppearance.sage),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              accessibleNavigation: accessible,
            ),
            child: Scaffold(
              body: MobileFeedbackHost(
                enabled: true,
                feedback: [value],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    ToolFeedback progress(int done) => ToolFeedback(
      sourceId: 'test',
      revision: 1,
      message: '対象者を確認中 · $done / 50',
      working: true,
      progress: done / 50,
      cancel: () => cancelled++,
      dismiss: () => dismissed++,
    );
    await mount(progress(1));
    await tester.pump(const Duration(seconds: 10));
    await mount(progress(25));
    expect(find.text('対象者を確認中 · 25 / 50'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .5,
    );
    await tester.tap(find.text('中止'));
    expect(cancelled, 1);
    final longError = '確認できませんでした。' * 100 + '通知の末尾';
    await mount(
      ToolFeedback(
        sourceId: 'test',
        revision: 1,
        message: longError,
        error: true,
        dismiss: () => dismissed++,
      ),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(popup, findsOneWidget);
    expect(find.text('中止'), findsNothing);
    final scrollFinder = find.descendant(
      of: popup,
      matching: find.byType(Scrollable),
    );
    final scroll = tester.state<ScrollableState>(scrollFinder).position;
    expect(scroll.maxScrollExtent, greaterThan(0));
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pump();
    expect(scroll.pixels, scroll.maxScrollExtent);
    await mount(
      ToolFeedback(
        sourceId: 'test',
        revision: 2,
        message: '次の通知',
        dismiss: () => dismissed++,
      ),
      accessible: true,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(popup, findsOneWidget, reason: '読み上げ利用時は自動で閉じない');
    expect(tester.state<ScrollableState>(scrollFinder).position.pixels, 0);
    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pump();
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('日付エラーはスマホ共通通知に出し、入力修正で消える', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixtures.controller(FakeGateway());
    await c.connect('fixture-only', remember: false);
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '開始日時（JST）');
    await restoreDateField(tester, field, '不正な日時');
    await tester.tap(find.byKey(const ValueKey('extract-users')));
    await tester.pumpAndSettle();
    expect(c.error, isNotNull);
    expect(popup, findsOneWidget);
    await restoreDateField(tester, field, '2026/01/01 00:00');
    await tester.pumpAndSettle();
    expect(c.error, isNull);
    expect(popup, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
