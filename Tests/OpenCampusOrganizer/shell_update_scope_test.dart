import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/app_shell.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/tool_activity.dart';
import 'package:open_campus_organizer/core/tool_module.dart';
import 'package:open_campus_organizer/core/tool_status.dart';
import 'package:open_campus_organizer/design/theme.dart';

class _Module extends ChangeNotifier implements ToolModule {
  _Module(this.id);
  @override
  final String id;
  int pagesBuilt = 0, settingsBuilt = 0, initialized = 0, disposed = 0;
  @override
  String get title => 'Tool $id';
  @override
  String get description => 'Fixture $id';
  @override
  IconData get icon => Icons.build;
  @override
  Listenable get changes => this;
  @override
  String get status => 'idle';
  @override
  bool get connected => false;
  @override
  bool get busy => false;
  @override
  ToolConnection? get connection => null;
  @override
  ToolFeedback? get feedback => null;
  @override
  List<ToolActivity> get activities => const [];
  void progress() => notifyListeners();
  @override
  Widget buildPage() {
    pagesBuilt++;
    return Center(child: TextField(key: ValueKey('field-$id')));
  }

  @override
  Widget buildSettings() {
    settingsBuilt++;
    return Text('Settings $id');
  }

  @override
  Widget buildActivityFeedback() => const SizedBox.shrink();
  @override
  Widget buildActivityDetails(String id) => const SizedBox.shrink();
  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }
}

void main() {
  testWidgets('無関係な進捗で共通ヘッダー・別ツール・非表示設定を作り直さない', (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = AppearanceController(MemoryStore());
    addTearDown(appearance.dispose);
    final a = _Module('a');
    final b = _Module('b');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppAppearance.dark),
        home: AppShell(modules: [a, b], appearance: appearance),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-a')), 'kept');
    await tester.pumpAndSettle();
    final header = tester.widget(find.byKey(const ValueKey('app-header')));
    final aPages = a.pagesBuilt, bPages = b.pagesBuilt;
    final aSettings = a.settingsBuilt, bSettings = b.settingsBuilt;
    b.progress();
    await tester.pumpAndSettle();
    expect(a.pagesBuilt, aPages);
    expect(b.pagesBuilt, bPages);
    expect(
      tester.widget(find.byKey(const ValueKey('app-header'))),
      same(header),
    );
    a.progress();
    await tester.pumpAndSettle();
    expect(a.pagesBuilt, aPages + 1);
    expect(b.pagesBuilt, bPages);
    expect(a.settingsBuilt, aSettings);
    expect(b.settingsBuilt, bSettings);
    await tester.tap(find.byKey(const ValueKey('nav-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-a')));
    await tester.pumpAndSettle();
    expect(find.text('kept'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(a.disposed, 1);
    expect(b.disposed, 1);
  });

  testWidgets('ツールの追加・削除時に初期化と解放を行い、既存画面のStateを保つ', (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = AppearanceController(MemoryStore());
    addTearDown(appearance.dispose);
    final a = _Module('a'), b = _Module('b'), c = _Module('c');
    Future<void> show(List<ToolModule> modules) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppAppearance.dark),
          home: AppShell(
            key: const ValueKey('shell'),
            modules: modules,
            appearance: appearance,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show([a, b]);
    await tester.tap(find.byKey(const ValueKey('nav-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-a')), 'retained');
    await show([c, a, b]);
    expect(a.initialized, 1);
    expect(b.initialized, 1);
    expect(c.initialized, 1);
    expect(find.text('retained'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-b')));
    await tester.pumpAndSettle();
    await show([c, a]);
    expect(b.disposed, 1);
    expect(find.byKey(const ValueKey('nav-b')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-a')));
    await tester.pumpAndSettle();
    expect(find.text('retained'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(a.disposed, 1);
    expect(b.disposed, 1);
    expect(c.disposed, 1);
  });
}
