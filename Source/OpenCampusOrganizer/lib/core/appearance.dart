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
  Future<void> _platformUpdates = Future.value();

  Future<void> initialize() async {
    if (_disposed) return;
    final revision = _revision;
    try {
      final saved = await store.read('appearance');
      if (_disposed || revision != _revision) return;
      value =
          AppAppearance.values.where((v) => v.name == saved).firstOrNull ??
          AppAppearance.dark;
    } catch (_) {
      if (_disposed || revision != _revision) return;
      error = '配色設定を読み込めませんでした。';
    }
    if (_disposed || revision != _revision) return;
    await _updatePlatform(value, revision);
    if (!_disposed && revision == _revision) notifyListeners();
  }

  Future<void> _updatePlatform(AppAppearance selected, int revision) {
    // 復元と選択を同じキューへ流す。実行中の古い更新が最新色を後から戻さない。
    _platformUpdates = _platformUpdates.then((_) async {
      // 未着手の中間色は省き、破棄後にOSへ要求を送らない。
      if (_disposed || revision != _revision) return;
      try {
        await updatePlatformAppearance?.call(selected);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          error = 'アプリのアイコンを変更できませんでした。';
          notifyListeners();
        }
      }
    });
    return _platformUpdates;
  }

  Future<void> select(AppAppearance selected) {
    if (_disposed) return Future.value();
    final revision = ++_revision;
    value = selected;
    error = null;
    final platformUpdate = _updatePlatform(selected, revision);
    // 連続選択でも保存順序を保ち、再起動時に最後の選択を復元する。
    final write = _writes = _writes.then((_) async {
      try {
        await store.write('appearance', selected.name);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          error = '配色を保存できませんでした。';
          notifyListeners();
        }
      }
    });
    // リスナーが再度selectしても、先の選択を後からキューに追加しない。
    notifyListeners();
    return Future.wait([write, platformUpdate]).then((_) {});
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
