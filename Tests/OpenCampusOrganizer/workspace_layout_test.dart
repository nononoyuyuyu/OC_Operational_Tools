import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/design/adaptive_page_list.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/demo_gateway.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';

FakeGateway manyPeople() {
  final gateway = FakeGateway();
  final people = List.generate(
    50,
    (i) => Member('${1000 + i}', 'member$i', nickname: '対象者 ${i + 1}'),
  );
  gateway.people.addEntries(people.map((m) => MapEntry(m.id, m)));
  gateway.messagePages = [
    people
        .map((m) => Message(m.id, '4', m, start, content: '長い本文。' * 100))
        .toList(),
  ];
  return gateway;
}

List<String> visibleMembers(WidgetTester tester) => tester
    .widgetList<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('member-'),
      ),
    )
    .map((w) => (w.key as ValueKey<String>).value)
    .toList();

void main() {
  test('サンプルでも終了日時のカーソルを受け取り8人を抽出できる', () async {
    final gateway = DemoGateway();
    final cancel = Cancellation();
    final bot = await gateway.connect('', cancel);
    final result = await ExtractionService(gateway).extract(
      DemoGateway.guild,
      Conditions(
        guildId: DemoGateway.guild.id,
        channelId: DemoGateway.channelId,
        roleId: DemoGateway.roleId,
        start: DateTime.now().toUtc().subtract(const Duration(days: 7)),
      ),
      bot,
      cancel,
      noProgress,
    );
    expect(result.users.length, 8);
    expect(result.messages.length, 18);
  });
  testWidgets(
    '通知で位置が変わらず、表示高さに合う件数と操作欄が一画面に収まる',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtures.controller(manyPeople());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      final conditionsRect = tester.getRect(
        find.byKey(const ValueKey('conditions-panel')),
      );
      final settingsRect = tester.getRect(
        find.byKey(const ValueKey('nav-settings')),
      );
      expect(settingsRect.left, lessThan(208));
      final connectionRect = tester.getRect(
        find.byKey(const ValueKey('connection-kakutei')),
      );
      expect(settingsRect.bottom, lessThan(connectionRect.top));
      expect(connectionRect.bottom, greaterThan(720));
      await c.extract(conditions(content: true));
      expect(c.error, isNull);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('conditions-panel'))),
        conditionsRect,
      );
      final fields = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('condition-fields')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        fields.position.maxScrollExtent,
        lessThanOrEqualTo(0.5),
        reason: '通常のPC幅では条件もスクロール不要',
      );
      final initialCount = visibleMembers(tester).length;
      expect(initialCount, inInclusiveRange(1, 10));
      final header = tester.getRect(find.byKey(const ValueKey('app-header')));
      c.busy = true;
      c.clearMessage();
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('app-header'))), header);
      expect(
        tester.getRect(find.byKey(const ValueKey('conditions-panel'))),
        conditionsRect,
      );
      c.busy = false;
      c.clearMessage();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('次のページ'));
      await tester.pumpAndSettle();
      final anchor = visibleMembers(tester).first;
      tester.view.physicalSize = const Size(1440, 1080);
      await tester.pumpAndSettle();
      expect(visibleMembers(tester).first, anchor);
      expect(visibleMembers(tester).length, greaterThan(initialCount));
      for (final size in [
        const Size(1366, 768),
        const Size(1280, 720),
        const Size(390, 844),
        const Size(320, 740),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(visibleMembers(tester).first, anchor, reason: 'リサイズ後も同じ対象者から表示');
        final pager = tester.getRect(
          find.byKey(const ValueKey('results-pagination')),
        );
        final button = tester.getRect(find.byKey(const ValueKey('add-role')));
        final feedback = tester.getRect(
          find.byKey(const ValueKey('operation-feedback')),
        );
        expect(button.bottom, lessThanOrEqualTo(feedback.top));
        expect(pager.bottom, lessThanOrEqualTo(button.top));
        for (final id in visibleMembers(tester)) {
          expect(
            tester.getRect(find.byKey(ValueKey(id))).bottom,
            lessThanOrEqualTo(pager.top + .5),
          );
        }
        final list = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(AdaptivePageList),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(list.position.maxScrollExtent, lessThanOrEqualTo(.5));
        expect(tester.takeException(), isNull);
        c.clearMessage();
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('results-pagination'))),
          pager,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '高さを縮めて局所スクロールに切り替わってもページ位置を保つ',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtures.controller(manyPeople());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await c.extract(conditions(content: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('次のページ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('次のページ'));
      await tester.pumpAndSettle();
      final anchor = visibleMembers(tester).first;
      expect(anchor, isNot('member-1000'));
      for (final size in [
        const Size(1366, 500),
        const Size(1366, 360),
        const Size(1366, 768),
        const Size(390, 620),
        const Size(390, 844),
        const Size(1366, 768),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(visibleMembers(tester).first, anchor, reason: '$size');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '全対象者を重複なくページ送りでき、検索と長い投稿の詳細を確認できる',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtures.controller(manyPeople());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      final all = <String>[];
      await c.extract(conditions(content: true));
      expect(c.error, isNull);
      await tester.pumpAndSettle();
      for (var n = 0; n < 50; n++) {
        all.addAll(visibleMembers(tester));
        if (tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == '次のページ',
                  ),
                )
                .onPressed ==
            null)
          break;
        await tester.tap(find.byTooltip('次のページ'));
        await tester.pumpAndSettle();
      }
      expect(all.length, 50);
      expect(all.toSet().length, 50);
      final search = find.widgetWithText(TextField, '名前・ユーザーIDで検索');
      await tester.enterText(search, '1000');
      await tester.pumpAndSettle();
      expect(visibleMembers(tester), ['member-1000']);
      await tester.enterText(search, '存在しない検索');
      await tester.pumpAndSettle();
      expect(find.text('検索結果はありません'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.tap(find.text('投稿 50'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('長い本文。' * 100).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '工程タブは片側表示だけに出し、大画面では実行結果だけを切り替える',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixtures.controller(manyPeople());
      await c.connect('fixture-only', remember: false);
      await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確定ロール').first);
      await c.extract(conditions());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kakutei-step-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('conditions-panel')), findsNothing);
      await tester.tap(find.text('条件設定'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conditions-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('results-panel')), findsNothing);
      await tester.tap(find.text('対象者確認'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1366, 768);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kakutei-step-tabs')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('conditions-panel'))).right,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('results-panel'))).left,
        ),
      );
      c.latestReport = OperationReport(
        id: 'layout-report',
        plan: plan(),
        rows: [OperationRow(alice, Outcome.success, '')],
        startedAt: start,
        finishedAt: start,
      );
      c.clearMessage();
      await tester.pumpAndSettle();
      expect(find.text('対象者ごとの結果'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '対象者一覧'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('results-panel')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '実行結果'));
      await tester.pumpAndSettle();
      expect(find.text('対象者ごとの結果'), findsOneWidget);
      expect(find.byKey(const ValueKey('kakutei-step-tabs')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
