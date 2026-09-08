import 'package:flutter/foundation.dart';

enum ToolConnectionState { disconnected, connecting, connected, sample }

/// 接続先の表示情報。通信方式や認証処理は各ツールが管理する。
class ToolConnection {
  const ToolConnection({required this.service, required this.state});
  final String service;
  final ToolConnectionState state;

  String get label => switch (state) {
    ToolConnectionState.disconnected => '未接続',
    ToolConnectionState.connecting => '接続中',
    ToolConnectionState.connected => '接続済み',
    ToolConnectionState.sample => 'サンプル',
  };
}

/// 共通の通知領域に渡す表示情報。同じ文面の再通知もrevisionで識別する。
class ToolFeedback {
  const ToolFeedback({
    required this.sourceId,
    required this.revision,
    required this.message,
    required this.dismiss,
    this.error = false,
    this.working = false,
    this.progress,
    this.cancel,
  });
  final String sourceId;
  final int revision;
  final String message;
  final bool error;
  final bool working;
  final double? progress;
  final VoidCallback dismiss;
  final VoidCallback? cancel;

  Object get eventKey => (sourceId, revision, working, error);
}
