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
    test('復元した配色と全5色の選択をOSに反映する: ' + platform.name, () async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final store = MemoryStore();
      await store.write('appearance', 'sage');
      final appearance = AppearanceController(
        store,
        updatePlatformAppearance: updateWindowAppearance,
      );
      await appearance.initialize();
      expect(calls.single.method, 'setTheme');
      expect(calls.single.arguments, 'sage');
      for (final value in AppAppearance.values) {
        await appearance.select(value);
        expect(calls.last.arguments, value.name);
        expect(await store.read('appearance'), value.name);
      }
      appearance.dispose();
    });
  }
  test('iOSではネイティブの呼び出しを行わない', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    for (final platform in [TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      await updateWindowAppearance(AppAppearance.orange);
    }
    expect(calls, 0);
  });

  test('アイコンの更新に失敗しても選んだ配色と保存値は保持する', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'icon_unavailable');
    });
    final store = MemoryStore();
    final appearance = AppearanceController(
      store,
      updatePlatformAppearance: updateWindowAppearance,
    );
    await appearance.select(AppAppearance.orange);
    expect(appearance.value, AppAppearance.orange);
    expect(await store.read('appearance'), 'orange');
    expect(appearance.error, 'アプリのアイコンを変更できませんでした。');
    appearance.dispose();
  });
}
