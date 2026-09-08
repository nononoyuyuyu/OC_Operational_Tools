import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ports.dart';
import 'task_host.dart';

abstract interface class RuntimePlatform {
  set onEvent(Future<void> Function(String) handler);
  Future<void> invoke(String method, Map<String, Object?> arguments);
  void dispose();
}

class NativeRuntimePlatform implements RuntimePlatform {
  static const channel = MethodChannel(
    'jp.nononoyuyuyu.open_campus_organizer/runtime',
  );
  @override
  set onEvent(Future<void> Function(String) handler) {
    channel.setMethodCallHandler((call) => handler(call.method));
  }

  @override
  Future<void> invoke(String method, Map<String, Object?> arguments) async {
    if (kIsWeb ||
        ![
          TargetPlatform.windows,
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    await channel.invokeMethod<void>(method, arguments);
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
  }
}

class RuntimeController extends ChangeNotifier implements TaskHost {
  RuntimeController(this.store, this.platform) {
    platform.onEvent = _event;
  }
  final LocalStore store;
  final RuntimePlatform platform;
  bool trayEnabled = false;
  bool mobileAutoClose = true;
  bool foreground = true;
  String? error;
  final _tasks = <String, String>{};
  final _participants =
      <
        ({
          Future<void> Function() pause,
          Future<void> Function() resume,
          VoidCallback cancel,
        })
      >[];
  Future<bool> Function()? confirmExit;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  Future<void> _updates = Future.value();
  bool _validSettings = true, _disposed = false, _closing = false;
  bool get busy => _tasks.isNotEmpty;

  void register({
    required Future<void> Function() pause,
    required Future<void> Function() resume,
    required VoidCallback cancel,
  }) {
    _participants.add((pause: pause, resume: resume, cancel: cancel));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final saved = await store.read('runtime');
      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        if (data['schema'] != 1) throw const FormatException();
        trayEnabled = data['trayEnabled'] as bool;
        mobileAutoClose = data['mobileAutoClose'] as bool;
      }
      await _configure();
    } catch (_) {
      _validSettings = false;
      error = 'バックグラウンド設定を読み込めませんでした。';
    }
    _notify();
  }

  Future<void> _configure() => platform.invoke('configure', {
    'trayEnabled': trayEnabled,
    'mobileAutoClose': mobileAutoClose,
  });
  Future<void> setPreferences({bool? tray, bool? autoClose}) async {
    await initialize();
    if (!_validSettings) return;
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final nextTray = tray ?? trayEnabled;
      final nextAutoClose = autoClose ?? mobileAutoClose;
      await store.write(
        'runtime',
        jsonEncode({
          'schema': 1,
          'trayEnabled': nextTray,
          'mobileAutoClose': nextAutoClose,
        }),
      );
      trayEnabled = nextTray;
      mobileAutoClose = nextAutoClose;
      await _configure();
      error = null;
      _notify();
    });
    try {
      await _writes;
    } catch (_) {
      error = 'バックグラウンド設定を保存・反映できませんでした。';
      _notify();
    }
  }

  @override
  Future<void> start(String id, String title) async {
    await initialize();
    if (_closing) throw StateError('closing');
    _tasks[id] = title;
    try {
      await platform.invoke('begin', {'id': id, 'title': title});
    } catch (_) {
      _tasks.remove(id);
      rethrow;
    }
    _notify();
  }

  @override
  void update(String id, String message, int done, int? total) {
    if (!_tasks.containsKey(id)) return;
    _updates = _updates
        .catchError((Object _) {})
        .then(
          (_) => platform.invoke('progress', {
            'id': id,
            'title': _tasks[id] ?? 'Open Campus Organizer',
            'message': message,
            'done': done,
            'total': total,
          }),
        )
        .catchError((Object _) {
          error = '進捗通知を更新できませんでした。';
          _notify();
        });
  }

  @override
  Future<void> finish(
    String id,
    String message, {
    required bool closeEligible,
    bool failed = false,
  }) async {
    if (!_tasks.containsKey(id)) return;
    await _updates;
    _tasks.remove(id);
    try {
      await platform.invoke('finish', {
        'id': id,
        'message': message,
        'failed': failed,
        'remaining': _tasks.length,
        'autoClose':
            closeEligible &&
            !failed &&
            !foreground &&
            mobileAutoClose &&
            _tasks.isEmpty &&
            !_closing,
      });
    } catch (_) {
      error = '処理結果の通知を表示できませんでした。';
    }
    _notify();
  }

  Future<void> _event(String event) async {
    switch (event) {
      case 'background':
        foreground = false;
      case 'foreground':
        foreground = true;
        if (!_closing) {
          for (final p in _participants) {
            unawaited(p.resume());
          }
        }
      case 'suspend':
        for (final p in _participants) {
          unawaited(p.pause());
        }
      case 'cancel':
        for (final p in _participants) {
          p.cancel();
        }
      case 'notificationsDenied':
        error = '通知が許可されていません。OSの設定で通知を許可してください。';
      case 'closeRequested':
        if (_closing) return;
        _closing = true;
        try {
          if (await confirmExit?.call() != true) return;
          for (final p in _participants) {
            await p.pause();
          }
          // 設定保存の失敗は既に表示済み。終了確認で選んだ終了を妨げない。
          await _writes.catchError((Object _) {});
          await _updates;
          await platform.invoke('exit', const {});
        } finally {
          _closing = false;
        }
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    platform.dispose();
    super.dispose();
  }
}
