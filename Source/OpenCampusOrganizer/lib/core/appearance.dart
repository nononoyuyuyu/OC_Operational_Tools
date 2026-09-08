import 'package:flutter/foundation.dart';
import 'ports.dart';

enum AppAppearance {
  dark('ダーク'),
  light('白・青'),
  warm('ウォームグレー'),
  sage('セージグリーン'),
  orange('アプリコット');

  const AppAppearance(this.label);
  final String label;
}

class AppearanceController extends ChangeNotifier {
  AppearanceController(this.store, {this.updatePlatformAppearance});
  final LocalStore store;
  final Future<void> Function(AppAppearance)? updatePlatformAppearance;
  AppAppearance value = AppAppearance.dark;
  String? error;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> initialize() async {
    final revision = _revision;
    try {
      final saved = await store.read('appearance');
      if (_disposed || revision != _revision) return;
      value =
          AppAppearance.values.where((v) => v.name == saved).firstOrNull ??
          AppAppearance.dark;
    } catch (_) {
      error = '配色設定を読み込めませんでした。';
    }
    if (_disposed || revision != _revision) return;
    await _updatePlatform(value, revision);
    if (!_disposed) notifyListeners();
  }

  Future<void> _updatePlatform(AppAppearance selected, int revision) async {
    try {
      await updatePlatformAppearance?.call(selected);
    } catch (_) {
      if (!_disposed && revision == _revision) {
        error = 'アプリのアイコンを変更できませんでした。';
        notifyListeners();
      }
    }
  }

  Future<void> select(AppAppearance selected) {
    _revision++;
    value = selected;
    error = null;
    notifyListeners();
    final platformUpdate = _updatePlatform(selected, _revision);
    // 連続選択でも保存順序を保ち、再起動時に最後の選択を復元する。
    _writes = _writes.then((_) async {
      try {
        await store.write('appearance', selected.name);
      } catch (_) {
        error = '配色を保存できませんでした。';
        if (!_disposed) notifyListeners();
      }
    });
    return Future.wait([_writes, platformUpdate]).then((_) {});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
