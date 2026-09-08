import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/design/connection_indicator.dart';
import 'package:open_campus_organizer/design/system_bars.dart';
import 'package:open_campus_organizer/features/kakutei/data/saved_settings.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';
import 'workspace_layout_test.dart' show manyPeople, visibleMembers;

final _list = find.byKey(const ValueKey('mobile-member-list'));
final _popup = find.byKey(const ValueKey('mobile-feedback'));

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
}

ScrollableState _listState(WidgetTester tester) =>
    tester.state(find.descendant(of: _list, matching: find.byType(Scrollable)));

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platformの320×640で5人以上を表示し、一覧だけをスクロールできる',
      (tester) async {
        _size(tester, const Size(320, 640));
        final c = fixtures.controller(manyPeople());
        await c.connect('fixture-only', remember: false);
        await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
        await tester.pumpAndSettle();
        await tester.tap(find.text('確定ロール').first);
        await tester.pumpAndSettle();
        final workspace = tester.getRect(
          find.byKey(const ValueKey('kakutei-workspace')),
        );
        await c.extract(conditions(content: true));
        await tester.pumpAndSettle();
        expect(_popup, findsOneWidget);
        expect(
          tester.getRect(find.byKey(const ValueKey('kakutei-workspace'))),
          workspace,
        );
        expect(find.byKey(const ValueKey('operation-feedback')), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.textContaining('CSV'), findsNothing);
        expect(find.byKey(const ValueKey('results-pagination')), findsNothing);
        expect(find.textContaining('最終投稿'), findsNothing);
        expect(find.text('1000'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        final connection = tester.getRect(
          find.byKey(const ValueKey('connection-kakutei')),
        );
        final header = tester.getRect(find.byKey(const ValueKey('app-header')));
        expect(header.contains(connection.center), isTrue);
        expect(connection.center.dx, greaterThan(160));

        await tester.tap(find.byTooltip('通知を閉じる'));
        await tester.pumpAndSettle();
        final listRect = tester.getRect(_list);
        final button = tester.getRect(find.byKey(const ValueKey('add-role')));
        final nav = tester.getRect(find.byType(NavigationBar));
        final completeRows = visibleMembers(tester).where((key) {
          final row = tester.getRect(find.byKey(ValueKey(key)));
          return row.top >= listRect.top && row.bottom <= listRect.bottom;
        });
        expect(completeRows.length, greaterThanOrEqualTo(5));
        expect(button.top, greaterThanOrEqualTo(listRect.bottom));
        expect(button.bottom, lessThan(nav.top));
        final outerScrolls = find.ancestor(
          of: _list,
          matching: find.byType(Scrollable),
        );
        expect(outerScrolls, findsNothing);

        final seen = <String>{};
        for (var i = 0; i < 60; i++) {
          seen.addAll(visibleMembers(tester));
          final position = _listState(tester).position;
          if (position.pixels >= position.maxScrollExtent) break;
          await tester.drag(_list, Offset(0, -listRect.height / 2));
          await tester.pumpAndSettle();
        }
        expect(seen.length, 50);
        expect(tester.getRect(find.byKey(const ValueKey('add-role'))), button);
        _listState(tester).position.jumpTo(600);
        await tester.pumpAndSettle();
        final offset = _listState(tester).position.pixels;
        for (final size in [
          const Size(390, 740),
          const Size(640, 320),
          const Size(320, 640),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(_listState(tester).position.pixels, closeTo(offset, .5));
          expect(find.byType(ChoiceChip), findsNothing);
          expect(find.textContaining('CSV'), findsNothing);
          expect(tester.takeException(), isNull, reason: '$size');
        }
        await tester.enterText(
          find.byKey(const ValueKey('mobile-member-search')),
          '対象者 50',
        );
        await tester.pumpAndSettle();
        expect(visibleMembers(tester), ['member-1049']);
        expect(_listState(tester).position.pixels, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('本文と添付URLの保存設定があってもスマホでは取得・表示しない', (tester) async {
    _size(tester, const Size(390, 844));
    final c = fixtures.controller(manyPeople());
    await c.connect('fixture-only', remember: false);
    c.updateInput(
      const ExtractionInput(
        start: '2026/01/01 00:00',
        includeContent: true,
        includeAttachments: true,
      ),
    );
    c.settingsRevision++;
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    expect(find.text('本文'), findsNothing);
    expect(find.text('添付URL'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('extract-users')));
    await tester.pumpAndSettle();
    expect(c.error, isNull);
    expect(c.extraction!.conditions.includeContent, isFalse);
    expect(c.extraction!.conditions.includeAttachments, isFalse);
    expect(c.settings.input.includeContent, isTrue);
    expect(c.settings.input.includeAttachments, isTrue);
    c.clearMessage();
    await c.execute(c.additionPlan());
    await tester.pumpAndSettle();
    expect(find.text('処理終了'), findsOneWidget);
    expect(find.textContaining('CSV'), findsNothing);
    await tester.tap(find.text('操作履歴').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('CSV'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('5配色で接続表示・通知・OSバーの文字色が追従する', (tester) async {
    _size(tester, const Size(390, 844));
    final c = fixtures.controller(FakeGateway());
    final appearance = AppearanceController(MemoryStore());
    await tester.pumpWidget(
      OcoApp(modules: [KakuteiModule(c)], appearance: appearance),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discord · 未接続'), findsOneWidget);
    for (final theme in AppAppearance.values) {
      await appearance.select(theme);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ConnectionIndicator));
      final colors = Theme.of(context).colorScheme;
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ConnectionIndicator),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, colors.onSurfaceVariant);
      final style = tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find
                .descendant(
                  of: find.byType(ThemedSystemBars),
                  matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
                )
                .first,
          )
          .value;
      expect(style.systemNavigationBarColor, colors.surface);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
      expect(
        style.systemNavigationBarIconBrightness,
        theme == AppAppearance.dark ? Brightness.light : Brightness.dark,
      );
      expect(
        Theme.of(context).navigationBarTheme.backgroundColor,
        colors.surface,
      );
      c.showNotice('解除する対象者はいません。');
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find.descendant(of: _popup, matching: find.byType(Material)).first,
      );
      expect(material.color, colors.surfaceContainerHigh);
      await tester.tap(find.byTooltip('通知を閉じる'));
      await tester.pumpAndSettle();
    }
    await c.connect('fixture-only', remember: false);
    await tester.pumpAndSettle();
    expect(find.text('Discord · 接続済み'), findsOneWidget);
    final connected = tester.widget<Icon>(
      find.descendant(
        of: find.byType(ConnectionIndicator),
        matching: find.byType(Icon),
      ),
    );
    expect(
      connected.color,
      Theme.of(
        tester.element(find.byType(ConnectionIndicator)),
      ).colorScheme.primary,
    );
    await c.startDemo();
    await tester.pumpAndSettle();
    expect(find.text('Discord · サンプル'), findsOneWidget);
    await c.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('Discord · 未接続'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('文字1.5倍とキーボード表示でも一覧と操作を画面内に保つ', (tester) async {
    _size(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = fixtures.controller(manyPeople());
    await c.connect('fixture-only', remember: false);
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await c.extract(conditions());
    await tester.pumpAndSettle();
    c.clearMessage();
    await tester.pumpAndSettle();
    expect(visibleMembers(tester).length, greaterThanOrEqualTo(3));
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.getRect(_list).height, greaterThan(0));
    expect(
      tester.getRect(find.byKey(const ValueKey('add-role'))).bottom,
      lessThanOrEqualTo(360),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
