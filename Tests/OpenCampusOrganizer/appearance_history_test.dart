import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/history_page.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/tool_activity.dart';
import 'package:open_campus_organizer/core/tool_module.dart';
import 'package:open_campus_organizer/core/tool_status.dart';
import 'package:open_campus_organizer/design/theme.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as widgets;
import 'support.dart';

void main() {
  test('初期値と未知の配色はダークになり、保存済みの選択は維持する', () async {
    final store = MemoryStore();
    final fresh = AppearanceController(store);
    expect(fresh.value, AppAppearance.dark);
    await fresh.initialize();
    expect(fresh.value, AppAppearance.dark);
    expect(buildTheme().brightness, Brightness.dark);
    await store.write('appearance', 'unknown-theme');
    await fresh.initialize();
    expect(fresh.value, AppAppearance.dark);
    await store.write('appearance', 'light');
    await fresh.initialize();
    expect(fresh.value, AppAppearance.light);
    fresh.dispose();
  });
  test('全配色を保存して復元でき、他の設定キーを変更しない', () async {
    final store = MemoryStore();
    await store.write('another', 'unchanged');
    for (final appearance in AppAppearance.values) {
      final first = AppearanceController(store);
      await first.select(appearance);
      final restored = AppearanceController(store);
      await restored.initialize();
      expect(restored.value, appearance);
      expect(await store.read('another'), 'unchanged');
      first.dispose();
      restored.dispose();
    }
  });
  test('連続で配色を変更しても最後の選択を保存する', () async {
    final store = MemoryStore();
    final c = AppearanceController(store);
    final initial = c.initialize();
    final warm = c.select(AppAppearance.warm);
    final dark = c.select(AppAppearance.dark);
    await Future.wait([initial, warm, dark]);
    expect(c.value, AppAppearance.dark);
    expect(await store.read('appearance'), 'dark');
    c.dispose();
  });
  test('全配色で通常文字4.5対1と入力枠3対1のコントラストを確保する', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final appearance in AppAppearance.values) {
      final s = buildTheme(appearance).colorScheme;
      for (final surface in [
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ]) {
        expect(
          contrast(s.onSurface, surface),
          greaterThanOrEqualTo(4.5),
          reason: appearance.name,
        );
        expect(
          contrast(s.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: appearance.name,
        );
      }
      expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      expect(
        contrast(s.onPrimaryContainer, s.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(s.onSecondaryContainer, s.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(s.onTertiary, s.tertiary), greaterThanOrEqualTo(4.5));
      expect(
        contrast(s.onTertiaryContainer, s.tertiaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      for (final color in [s.primary, s.tertiary]) {
        expect(
          contrast(
            color,
            Color.alphaBlend(color.withValues(alpha: .09), s.surface),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${appearance.name}の状態表示',
        );
      }
      expect(
        contrast(s.onErrorContainer, s.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
      for (final color in [s.primary, s.tertiary, s.onSurfaceVariant]) {
        expect(
          contrast(
            color,
            Color.alphaBlend(color.withValues(alpha: .09), s.surface),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${appearance.name}の接続状態表示',
        );
      }
      expect(contrast(s.outline, s.surface), greaterThanOrEqualTo(3));
    }
  });
  testWidgets('全体履歴は別ツールの同じIDも区別し、時刻順に内容を表示する', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final modules = [
      _HistoryTool('alpha', 'ツール甲', DateTime.utc(2026, 1, 1)),
      _HistoryTool('beta', 'ツール乙', DateTime.utc(2026, 1, 2)),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: HistoryPage(modules: modules)),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('activity_beta_same-id'));
    final second = find.byKey(const ValueKey('activity_alpha_same-id'));
    expect(tester.getRect(first).top, lessThan(tester.getRect(second).top));
    expect(tester.getRect(first).height, lessThanOrEqualTo(112));
    expect(tester.getRect(first).width, lessThanOrEqualTo(460));
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('ツール乙の詳細'), findsOneWidget);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.text('ツール甲の詳細'), findsOneWidget);
    expect(find.text('ツール乙の詳細'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final module in modules) {
      module.dispose();
    }
  });
  testWidgets('設定で全配色を切り替えてもツールの入力値と接続を保つ', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = widgets.controller(FakeGateway());
    await c.connect('fixture-only', remember: false);
    final appearance = AppearanceController(MemoryStore());
    await tester.pumpWidget(
      OcoApp(modules: [KakuteiModule(c)], appearance: appearance),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    final minimum = find.widgetWithText(TextField, '最小投稿数');
    await tester.enterText(minimum, '3');
    for (final option in AppAppearance.values) {
      await tester.tap(find.text('設定').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option.label));
      await tester.pumpAndSettle();
      expect(appearance.value, option);
      await tester.tap(find.text('確定ロール').first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(minimum).controller!.text, '3');
      expect(c.connected, isTrue);
      final select = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == '対象ロール',
      );
      final remove = find.byKey(const ValueKey('remove-selected-role'));
      expect(
        (tester.getRect(remove).top - tester.getRect(select).bottom).abs(),
        lessThan(24),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class _HistoryTool implements ToolModule {
  _HistoryTool(this.id, this.title, DateTime at)
    : activities = [
        ToolActivity(
          id: 'same-id',
          at: at,
          action: '登録',
          subject: id == 'alpha' ? '対象甲' : '対象乙',
          context: 'テスト',
          result: '成功 1件',
        ),
      ];
  @override
  final String id;
  @override
  final String title;
  @override
  final List<ToolActivity> activities;
  @override
  String get description => '';
  @override
  IconData get icon => Icons.widgets;
  @override
  final ValueNotifier<bool> changes = ValueNotifier(false);
  @override
  bool get busy => false;
  @override
  bool get connected => false;
  @override
  ToolConnection? get connection => null;
  @override
  ToolFeedback? get feedback => null;
  @override
  String get status => '';
  @override
  Widget buildPage() => const SizedBox();
  @override
  Widget buildSettings() => const SizedBox();
  @override
  Widget buildActivityFeedback() => const SizedBox();
  @override
  Widget buildActivityDetails(String id) => Text('$titleの詳細');
  @override
  Future<void> initialize() async {}
  @override
  void dispose() => changes.dispose();
}
