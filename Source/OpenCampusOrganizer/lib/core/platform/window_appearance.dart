import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../appearance.dart';

/// OSのアイコン連動を画面から隔離する。
Future<void> updateWindowAppearance(AppAppearance appearance) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return;
  }
  await const MethodChannel(
    'jp.nononoyuyuyu.open_campus_organizer/appearance',
  ).invokeMethod<void>('setTheme', appearance.name);
}
