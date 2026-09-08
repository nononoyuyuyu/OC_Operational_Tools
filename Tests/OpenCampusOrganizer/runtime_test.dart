import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/runtime_settings.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/runtime_controller.dart';

class FakeRuntimePlatform implements RuntimePlatform {
  @override
  late Future<void> Function(String) onEvent;
  final calls = <({String method, Map<String, Object?> args})>[];
  @override
  Future<void> invoke(String method, Map<String, Object?> arguments) async {
    calls.add((method: method, args: arguments));
  }

  @override
  void dispose() {}
}

class FailedRuntimeStore extends MemoryStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('fixture disk full');
  }
}

void main() {
  testWidgets('iOSは終了スイッチを置かず、通知許可のエラーを表示する', (tester) async {
    final platform = FakeRuntimePlatform();
    final c = RuntimeController(MemoryStore(), platform);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(body: RuntimeSettings(controller: c)),
      ),
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('バックグラウンド'), findsNothing);
    await platform.onEvent('notificationsDenied');
    await tester.pump();
    expect(find.textContaining('通知が許可されていません'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  test('続けて設定を変えても別項目を巻き戻さず、保存失敗後も終了できる', () async {
    final c = RuntimeController(MemoryStore(), FakeRuntimePlatform());
    await Future.wait([
      c.setPreferences(tray: true),
      c.setPreferences(autoClose: false),
    ]);
    expect(c.trayEnabled, isTrue);
    expect(c.mobileAutoClose, isFalse);
    c.dispose();
    final platform = FakeRuntimePlatform();
    final failing = RuntimeController(FailedRuntimeStore(), platform);
    await failing.setPreferences(tray: true);
    expect(failing.error, isNotNull);
    expect(failing.trayEnabled, isFalse);
    failing.confirmExit = () async => true;
    await platform.onEvent('closeRequested');
    expect(platform.calls.last.method, 'exit');
    failing.dispose();
  });
  test('トレイは初期オフ、自動終了は初期オンで、設定を復元する', () async {
    final store = MemoryStore();
    final platform = FakeRuntimePlatform();
    final c = RuntimeController(store, platform);
    await c.initialize();
    expect(c.trayEnabled, isFalse);
    expect(c.mobileAutoClose, isTrue);
    await c.setPreferences(tray: true, autoClose: false);
    c.dispose();
    final next = RuntimeController(store, FakeRuntimePlatform());
    await next.initialize();
    expect(next.trayEnabled, isTrue);
    expect(next.mobileAutoClose, isFalse);
    next.dispose();
  });
  test('前面・抽出・他タスクあり・設定オフでは自動終了しない', () async {
    final platform = FakeRuntimePlatform();
    final c = RuntimeController(MemoryStore(), platform);
    await c.start('1', 'role');
    await c.finish('1', '完了', closeEligible: true);
    expect(platform.calls.last.args['autoClose'], isFalse);
    await platform.onEvent('background');
    await c.start('1', 'extract');
    await c.finish('1', '対象者', closeEligible: false);
    expect(platform.calls.last.args['autoClose'], isFalse);
    await c.start('1', 'role');
    await c.start('2', 'another');
    await c.finish('1', '完了', closeEligible: true);
    expect(platform.calls.last.args['autoClose'], isFalse);
    await c.finish('2', '完了', closeEligible: true);
    expect(platform.calls.last.args['autoClose'], isTrue);
    await c.setPreferences(autoClose: false);
    await c.start('1', 'role');
    await c.finish('1', '完了', closeEligible: true);
    expect(platform.calls.last.args['autoClose'], isFalse);
    c.dispose();
  });
  test('終了を取り消せて、終了を選んだら保存完了まで閉じない', () async {
    final platform = FakeRuntimePlatform();
    final c = RuntimeController(MemoryStore(), platform);
    final saved = Completer<void>();
    var pauses = 0;
    c.register(
      pause: () {
        pauses++;
        return saved.future;
      },
      resume: () async {},
      cancel: () {},
    );
    c.confirmExit = () async => false;
    await platform.onEvent('closeRequested');
    expect(pauses, 0);
    c.confirmExit = () async => true;
    final closing = platform.onEvent('closeRequested');
    await Future<void>.delayed(Duration.zero);
    await platform.onEvent('closeRequested');
    expect(pauses, 1);
    expect(platform.calls.where((c) => c.method == 'exit'), isEmpty);
    saved.complete();
    await closing;
    expect(platform.calls.last.method, 'exit');
    c.dispose();
  });
  test('OSの時間切れは保存停止、通知の中止は利用者の取消へ渡す', () async {
    final platform = FakeRuntimePlatform();
    final c = RuntimeController(MemoryStore(), platform);
    var paused = 0, resumed = 0, cancelled = 0;
    c.register(
      pause: () async {
        paused++;
      },
      resume: () async {
        resumed++;
      },
      cancel: () {
        cancelled++;
      },
    );
    await platform.onEvent('suspend');
    await platform.onEvent('foreground');
    await platform.onEvent('cancel');
    expect([paused, resumed, cancelled], [1, 1, 1]);
    await platform.onEvent('notificationsDenied');
    expect(c.error, contains('通知'));
    c.dispose();
  });
}
