import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/pending_task.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/task_host.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/features/kakutei/data/recovery_payload.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_service.dart';
import 'support.dart';

class LiveStateGateway extends FakeGateway {
  bool loseNextResponse = false;
  Completer<void>? sent, release;
  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    cancel.check();
    writes++;
    final m = people[userId]!;
    final roles = m.roles.toSet();
    if (action == RoleAction.add) {
      roles.add(roleId);
    } else {
      roles.remove(roleId);
    }
    people[userId] = Member(m.id, m.username, roles: roles);
    sent?.complete();
    sent = null;
    await release?.future;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const AppFailure('通信切断', retryable: true, uncertain: true);
    }
  }
}

class RecordingHost extends NoopTaskHost {
  final endings = <bool>[];
  @override
  Future<void> finish(
    String id,
    String message, {
    required bool closeEligible,
    bool failed = false,
  }) async {
    endings.add(closeEligible);
  }
}

class RefusingTaskStore extends MemoryStore {
  bool refuse = false;
  @override
  Future<void> write(String key, String value) async {
    if (refuse && key == 'pending_task') throw StateError('fixture disk full');
    await super.write(key, value);
  }
}

KakuteiController makeController(
  FakeGateway g,
  MemoryStore store, {
  Future<void> Function(Duration, Cancellation)? wait,
  TaskHost host = const NoopTaskHost(),
}) => KakuteiController(
  gateway: g,
  credentials: store,
  journal: StoredOperationJournal(store),
  exports: FakeExport(),
  taskStore: PendingTaskStore(store),
  taskHost: host,
  retryWait: wait ?? (_, cancel) async => cancel.check(),
);

Future<PendingTask> seedOperation(
  MemoryStore store,
  RolePlan p, {
  List<OperationRow>? rows,
  bool finished = false,
  String botId = '9',
  bool ack = true,
}) async {
  final task = PendingTask(
    id: '123',
    botId: botId,
    kind: 'operation',
    payload: {'plan': encodePlan(p), 'acknowledged': ack},
  );
  await StoredOperationJournal(store).save(
    OperationReport(
      id: task.id,
      plan: p,
      rows:
          rows ??
          p.targets.map((m) => OperationRow(m, Outcome.pending, '')).toList(),
      startedAt: p.createdAt,
      finishedAt: finished ? DateTime.now().toUtc() : null,
    ),
  );
  await PendingTaskStore(store).save(task);
  await store.save('fixture-only');
  return task;
}

void main() {
  test('送信後に応答を失っても再照合し、同じ人へ重ねて送信しない', () async {
    final store = MemoryStore();
    final g = LiveStateGateway()..loseNextResponse = true;
    final p = plan(targets: [alice]);
    await seedOperation(store, p);
    var retries = 0;
    final c = makeController(
      g,
      store,
      wait: (delay, cancel) async {
        retries++;
        expect(delay, const Duration(seconds: 2));
        cancel.check();
        final report = (await StoredOperationJournal(store).load()).single;
        expect(report.finishedAt, isNull);
        expect(report.rows.single.outcome, Outcome.uncertain);
      },
    );
    await c.initialize();
    expect(retries, 1);
    expect(g.writes, 1);
    expect(c.latestReport!.rows.single.outcome, Outcome.skipped);
    expect(await PendingTaskStore(store).load(), isNull);
    c.dispose();
  });

  test('強制終了相当の記録から、完了済みを保持して未送信だけ再開する', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    final p = plan(at: DateTime.now().subtract(const Duration(days: 1)));
    await seedOperation(
      store,
      p,
      rows: [
        OperationRow(alice, Outcome.success, ''),
        OperationRow(bob, Outcome.pending, ''),
      ],
    );
    // 完了済みの対象は、その後Discord側が変わっても再操作しない。
    g.people[bob.id] = Member(bob.id, bob.username);
    final c = makeController(g, store);
    await c.initialize();
    expect(g.writes, 1);
    expect(g.people[alice.id]!.roles, isEmpty);
    expect(c.latestReport!.count(Outcome.success), 2);
    c.dispose();
  });

  test('解除の承認対象を増やさず、別Botや未承認の解除を実行しない', () async {
    for (final mismatch in [true, false]) {
      final store = MemoryStore();
      final g = LiveStateGateway();
      await seedOperation(
        store,
        plan(action: RoleAction.remove, targets: [bob]),
        botId: mismatch ? 'different-bot' : '9',
        ack: mismatch,
      );
      final c = makeController(g, store);
      await c.initialize();
      expect(g.writes, 0);
      if (mismatch) expect(c.pendingTask!.blocked, isTrue);
      expect(c.error, isNotNull);
      c.dispose();
    }
    final store = MemoryStore();
    final g = LiveStateGateway();
    g.people['12'] = Member('12', 'new', roles: {'2'});
    await seedOperation(store, plan(action: RoleAction.remove, targets: [bob]));
    final c = makeController(g, store);
    await c.initialize();
    expect(g.writes, 1);
    expect(g.people['12']!.roles, contains('2'));
    c.dispose();
  });

  test('利用者の中止は永続化し、再起動や通信復帰でも再開しない', () async {
    final store = MemoryStore();
    final g = LiveStateGateway()
      ..lookupError = const AppFailure('offline', retryable: true);
    await seedOperation(store, plan());
    final c = makeController(
      g,
      store,
      wait: (_, cancel) async {
        cancel.cancel();
        cancel.check();
      },
    );
    await c.initialize();
    expect(g.writes, 0);
    expect(await PendingTaskStore(store).load(), isNull);
    expect(c.history.single.count(Outcome.unprocessed), 2);
    c.dispose();
    g.lookupError = null;
    final next = makeController(g, store);
    await next.initialize();
    expect(g.writes, 0);
    next.dispose();
  });

  test('通常終了は送信済みの応答と記録を待ち、次回は残りだけ再開する', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    g.people[bob.id] = Member(bob.id, bob.username);
    await seedOperation(store, plan());
    final sent = Completer<void>();
    final release = Completer<void>();
    g.sent = sent;
    g.release = release;
    final c = makeController(g, store);
    final run = c.initialize();
    await sent.future;
    var stopped = false;
    final stopping = c.suspendTasks().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    release.complete();
    await stopping;
    await run;
    expect(g.writes, 1);
    expect(await PendingTaskStore(store).load(), isNotNull);
    c.dispose();
    final next = makeController(g, store);
    await next.initialize();
    expect(g.writes, 2);
    expect(next.latestReport!.count(Outcome.success), 2);
    next.dispose();
  });

  test('完了記録の直後に終了しても再実行せず、待ち状態だけ片付ける', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    await seedOperation(
      store,
      plan(targets: [alice]),
      rows: [OperationRow(alice, Outcome.success, '')],
      finished: true,
    );
    final c = makeController(g, store);
    await c.initialize();
    expect(g.writes, 0);
    expect(await PendingTaskStore(store).load(), isNull);
    c.dispose();
  });

  test('保存停止の完了前に前面へ戻っても、停止後に一度だけ再開する', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    g.people[bob.id] = Member(bob.id, bob.username);
    await seedOperation(store, plan());
    final sent = Completer<void>();
    final release = Completer<void>();
    g.sent = sent;
    g.release = release;
    final c = makeController(g, store);
    final run = c.initialize();
    await sent.future;
    final stopping = c.suspendTasks();
    final foreground = c.resumePending();
    final duplicate = c.resumePending();
    release.complete();
    await Future.wait([run, stopping, foreground, duplicate]);
    expect(g.writes, 2);
    expect(c.latestReport!.count(Outcome.success), 2);
    expect(await PendingTaskStore(store).load(), isNull);
    c.dispose();
  });

  test('再開記録の保存が失敗したらDiscordを更新せず元の記録を残す', () async {
    final store = RefusingTaskStore();
    final g = LiveStateGateway();
    await seedOperation(store, plan());
    final original = await store.read('pending_task');
    store.refuse = true;
    final c = makeController(g, store);
    await c.initialize();
    expect(g.writes, 0);
    expect(await store.read('pending_task'), original);
    expect(c.error, isNotNull);
    c.dispose();
  });

  test('送信中に中止したロール操作は結果を保存し自動終了しない', () async {
    final store = MemoryStore();
    final host = RecordingHost();
    final g = LiveStateGateway();
    g.people[bob.id] = Member(bob.id, bob.username);
    await seedOperation(store, plan());
    final sent = Completer<void>();
    final release = Completer<void>();
    g.sent = sent;
    g.release = release;
    final c = makeController(g, store, host: host);
    final run = c.initialize();
    await sent.future;
    c.cancel();
    release.complete();
    await run;
    expect(g.writes, 1);
    expect(c.history.single.count(Outcome.success), 1);
    expect(c.history.single.count(Outcome.unprocessed), 1);
    expect(host.endings, [false]);
    expect(await PendingTaskStore(store).load(), isNull);
    c.dispose();
  });

  test('対象抽出は固定した期間で再取得し、ロール操作を自動承認しない', () async {
    final store = MemoryStore();
    final host = RecordingHost();
    await store.save('fixture-only');
    final task = PendingTask(
      id: 'extract',
      botId: '9',
      kind: 'extract',
      payload: encodeConditions(conditions()),
    );
    await PendingTaskStore(store).save(task);
    final g = LiveStateGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final c = makeController(g, store, host: host);
    await c.initialize();
    expect(c.extraction!.conditions.end, conditions().end);
    expect(c.extraction!.users.length, 1);
    expect(g.writes, 0);
    expect(host.endings, [false]);
    c.dispose();
  });

  test('壊れた再開記録を上書きせず、過去版の履歴だけから自動実行しない', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    await seedOperation(store, plan());
    await store.write('pending_task', '{broken');
    final c = makeController(g, store);
    await c.initialize();
    await c.connect('fixture-only', remember: true);
    await c.extract(conditions());
    expect(await store.read('pending_task'), '{broken');
    expect(g.writes, 0);
    c.dispose();
    await store.write('pending_task', jsonEncode({'schema': 1, 'task': null}));
    final next = makeController(g, store);
    await next.initialize();
    expect(next.history, isNotEmpty);
    expect(g.writes, 0);
    next.dispose();
  });

  test('再開時にも権限を検査し、異なる対象列の履歴を拒否する', () async {
    final store = MemoryStore();
    final g = LiveStateGateway();
    final original = plan(targets: [alice]);
    final saved = OperationReport(
      id: '1',
      plan: original,
      rows: [OperationRow(bob, Outcome.pending, '')],
      startedAt: start,
    );
    await expectLater(
      OperationService(g, StoredOperationJournal(store)).execute(
        original,
        'current',
        Cancellation(),
        noProgress,
        (_) {},
        operationId: '1',
        resume: saved,
        resumable: true,
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(g.writes, 0);
  });
}
