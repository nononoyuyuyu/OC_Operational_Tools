import 'dart:async';

class AppFailure implements Exception {
  const AppFailure(
    this.message, {
    this.status,
    this.uncertain = false,
    this.retryable = false,
    this.retryAfter,
  });
  final String message;
  final int? status;
  final bool uncertain;
  final bool retryable;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

class Cancelled implements Exception {}

class TaskSuspended implements Exception {}

class Cancellation {
  bool _cancelled = false;
  bool _suspended = false;
  bool get isCancelled => _cancelled;
  bool get isSuspended => _suspended;
  void cancel() => _cancelled = true;
  void suspend() => _suspended = true;
  void check() {
    if (_cancelled) throw Cancelled();
    if (_suspended) throw TaskSuspended();
  }

  Future<void> wait(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      check();
      final remaining = end.difference(DateTime.now());
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 100)
            ? remaining
            : const Duration(milliseconds: 100),
      );
    }
    check();
  }
}

String failureMessage(Object error) => error is AppFailure
    ? error.message
    : error is Cancelled
    ? '処理を中止しました。'
    : '処理を完了できませんでした。接続状態と保存先を確認してください。';
