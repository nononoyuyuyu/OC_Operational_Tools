import 'dart:convert';
import 'failure.dart';
import 'ports.dart';

/// 再開に必要な承認内容だけを保存する。資格情報は含めない。
class PendingTask {
  const PendingTask({
    required this.id,
    required this.botId,
    required this.kind,
    required this.payload,
    this.blocked = false,
  });
  final String id, botId, kind;
  final Map<String, dynamic> payload;
  final bool blocked;
  PendingTask withBlocked(bool value) => PendingTask(
    id: id,
    botId: botId,
    kind: kind,
    payload: payload,
    blocked: value,
  );
}

class PendingTaskStore {
  PendingTaskStore(this.store);
  final LocalStore store;
  Future<void> _writes = Future.value();
  Future<void> save(PendingTask? task) {
    final encoded = jsonEncode({
      'schema': 1,
      'task': task == null
          ? null
          : {
              'id': task.id,
              'botId': task.botId,
              'kind': task.kind,
              'payload': task.payload,
              'blocked': task.blocked,
            },
    });
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => store.write('pending_task', encoded));
  }

  Future<PendingTask?> load() async {
    await _writes;
    final text = await store.read('pending_task');
    if (text == null) return null;
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['schema'] != 1 || !data.containsKey('task')) {
        throw const FormatException();
      }
      final task = data['task'] as Map<String, dynamic>?;
      if (task == null) return null;
      if ((task['id'] as String).isEmpty || (task['botId'] as String).isEmpty) {
        throw const FormatException();
      }
      return PendingTask(
        id: task['id'] as String,
        botId: task['botId'] as String,
        kind: task['kind'] as String,
        payload: task['payload'] as Map<String, dynamic>,
        blocked: task['blocked'] as bool,
      );
    } catch (_) {
      throw const AppFailure('再開用の記録を読み取れません。保存データを保管してください。');
    }
  }
}
