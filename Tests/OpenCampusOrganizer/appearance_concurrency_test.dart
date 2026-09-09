import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/appearance.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/platform/window_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'jp.nononoyuyuyu.open_campus_organizer/appearance',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    test('遅いOS更新中の連続選択は最後の色に収束する: ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      final started = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      String? icon;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final theme = call.arguments as String;
        calls.add(theme);
        if (theme == 'light') {
          started.complete();
          await release.future;
        }
        icon = theme;
        return null;
      });
      final store = MemoryStore();
      final controller = AppearanceController(
        store,
        updatePlatformAppearance: updateWindowAppearance,
      );
      addTearDown(controller.dispose);
      final first = controller.select(AppAppearance.light);
      await started.future;
      final middle = controller.select(AppAppearance.warm);
      final last = controller.select(AppAppearance.orange);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['light']);
      expect(controller.value, AppAppearance.orange);
      release.complete();
      await Future.wait([first, middle, last]);
      expect(calls, ['light', 'orange']);
      expect(icon, 'orange');
      expect(await store.read('appearance'), 'orange');
      expect(controller.error, isNull);
    });
  }

  test('保存色のOS反映中に選択しても古いアイコンが後から戻らない', () async {
    final store = MemoryStore();
    await store.write('appearance', 'sage');
    final started = Completer<void>();
    final release = Completer<void>();
    final calls = <AppAppearance>[];
    AppAppearance? icon;
    final controller = AppearanceController(
      store,
      updatePlatformAppearance: (theme) async {
        calls.add(theme);
        if (theme == AppAppearance.sage) {
          started.complete();
          await release.future;
        }
        icon = theme;
      },
    );
    addTearDown(controller.dispose);
    final initialize = controller.initialize();
    await started.future;
    final select = controller.select(AppAppearance.orange);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [AppAppearance.sage]);
    release.complete();
    await Future.wait([initialize, select]);
    expect(icon, AppAppearance.orange);
    expect(controller.value, AppAppearance.orange);
    expect(await store.read('appearance'), 'orange');
  });

  test('古い読込失敗は新しい選択のエラーを上書きしない', () async {
    final store = _DelayedReadStore();
    final controller = AppearanceController(store);
    addTearDown(controller.dispose);
    final initialize = controller.initialize();
    await controller.select(AppAppearance.orange);
    store.readResult.completeError(StateError('古い読込の失敗'));
    await initialize;
    expect(controller.value, AppAppearance.orange);
    expect(controller.error, isNull);
  });

  test('古い保存失敗でも最新の保存を続け、誤ったエラーを残さない', () async {
    final store = _DelayedWriteStore();
    final controller = AppearanceController(store);
    addTearDown(controller.dispose);
    final first = controller.select(AppAppearance.light);
    await store.started.future;
    final last = controller.select(AppAppearance.orange);
    store.release.completeError(StateError('古い保存の失敗'));
    await Future.wait([first, last]);
    expect(await store.read('appearance'), 'orange');
    expect(controller.error, isNull);
  });

  test('OS更新が失敗しても同じ色で再試行でき、キューを停止しない', () async {
    var attempts = 0;
    final controller = AppearanceController(
      MemoryStore(),
      updatePlatformAppearance: (_) async {
        if (++attempts == 1) throw StateError('一時的な更新失敗');
      },
    );
    addTearDown(controller.dispose);
    await controller.select(AppAppearance.orange);
    expect(controller.error, 'アプリのアイコンを変更できませんでした。');
    await controller.select(AppAppearance.orange);
    expect(attempts, 2);
    expect(controller.error, isNull);
  });

  test('古いOS更新の失敗は最新の選択を妨げない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    AppAppearance? icon;
    final controller = AppearanceController(
      MemoryStore(),
      updatePlatformAppearance: (theme) async {
        if (theme == AppAppearance.light) {
          started.complete();
          await release.future;
        }
        icon = theme;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.select(AppAppearance.light);
    await started.future;
    final last = controller.select(AppAppearance.orange);
    release.completeError(StateError('古いOS更新の失敗'));
    await Future.wait([first, last]);
    expect(icon, AppAppearance.orange);
    expect(controller.error, isNull);
  });

  test('破棄後は待機中と新規のOS更新を開始せず通知もしない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final calls = <AppAppearance>[];
    final controller = AppearanceController(
      MemoryStore(),
      updatePlatformAppearance: (theme) async {
        calls.add(theme);
        started.complete();
        await release.future;
      },
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    final first = controller.select(AppAppearance.light);
    await started.future;
    final last = controller.select(AppAppearance.orange);
    controller.dispose();
    final before = notifications;
    await controller.select(AppAppearance.dark);
    await controller.initialize();
    release.completeError(StateError('破棄済みの更新失敗'));
    await Future.wait([first, last]);
    expect(calls, [AppAppearance.light]);
    expect(controller.value, AppAppearance.orange);
    expect(notifications, before);
  });

  test('リスナーから再選択しても保存順序とOS更新順序を逆転させない', () async {
    final store = MemoryStore();
    final calls = <AppAppearance>[];
    final controller = AppearanceController(
      store,
      updatePlatformAppearance: (theme) async => calls.add(theme),
    );
    addTearDown(controller.dispose);
    Future<void>? nested;
    controller.addListener(() {
      if (controller.value == AppAppearance.light) {
        nested = controller.select(AppAppearance.orange);
      }
    });
    await controller.select(AppAppearance.light);
    await nested;
    expect(controller.value, AppAppearance.orange);
    expect(await store.read('appearance'), 'orange');
    expect(calls, [AppAppearance.orange]);
  });
}

class _DelayedReadStore extends MemoryStore {
  final readResult = Completer<String?>();
  @override
  Future<String?> read([String? key]) => readResult.future;
}

class _DelayedWriteStore extends MemoryStore {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (value == 'light') {
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}
