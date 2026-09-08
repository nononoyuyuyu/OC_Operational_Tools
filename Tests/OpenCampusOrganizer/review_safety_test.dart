import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/pending_task.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/core/task_host.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/features/kakutei/data/recovery_payload.dart';
import 'package:open_campus_organizer/features/kakutei/data/saved_settings.dart';
import 'package:open_campus_organizer/features/kakutei/domain/jst.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_completion.dart';
import 'support.dart';

class _Host extends NoopTaskHost {
  final close = <bool>[];
  final failures = <bool>[];
  final messages = <String>[];

  @override
  Future<void> finish(
    String id,
    String message, {
    required bool closeEligible,
    bool failed = false,
  }) async {
    close.add(closeEligible);
    failures.add(failed);
    messages.add(message);
  }
}

KakuteiController _controller(
  FakeGateway gateway,
  MemoryStore store,
  _Host host, {
  bool persistent = true,
}) => KakuteiController(
  gateway: gateway,
  credentials: store,
  journal: StoredOperationJournal(store),
  exports: FakeExport(),
  settingsStore: KakuteiSettingsStore(store),
  taskStore: persistent ? PendingTaskStore(store) : null,
  taskHost: host,
  retryWait: (_, cancel) async => cancel.check(),
);

Future<void> _seed(
  MemoryStore store,
  RolePlan p, {
  bool blocked = false,
  bool credential = true,
}) async {
  await StoredOperationJournal(store).save(
    OperationReport(
      id: 'review',
      plan: p,
      rows: p.targets.map((m) => OperationRow(m, Outcome.pending, '')).toList(),
      startedAt: start,
    ),
  );
  final task = PendingTask(
    id: 'review',
    botId: bot.id,
    kind: 'operation',
    payload: {'plan': encodePlan(p), 'acknowledged': true},
  );
  await PendingTaskStore(store).save(task.withBlocked(blocked));
  if (credential) await store.save('fixture-only');
}

void main() {
  test('全て成功・スキップかつ完了日時ありの場合だけ正常完了とする', () {
    for (final outcome in Outcome.values) {
      final report = OperationReport(
        id: 'classification',
        plan: plan(targets: [alice]),
        rows: [OperationRow(alice, outcome, '')],
        startedAt: start,
        finishedAt: start.add(const Duration(seconds: 1)),
      );
      expect(
        report.completedSuccessfully,
        outcome == Outcome.success || outcome == Outcome.skipped,
        reason: outcome.name,
      );
    }
    final unfinished = OperationReport(
      id: 'unfinished',
      plan: plan(targets: [alice]),
      rows: [OperationRow(alice, Outcome.success, '')],
      startedAt: start,
    );
    expect(unfinished.completedSuccessfully, isFalse);
  });

  test('完了済みレポートを初回保存しても別インスタンスで完了日時を復元する', () async {
    final store = MemoryStore();
    final finished = start.add(const Duration(minutes: 1));
    await StoredOperationJournal(store).save(
      OperationReport(
        id: 'finished',
        plan: plan(targets: [alice]),
        rows: [OperationRow(alice, Outcome.success, '')],
        startedAt: start,
        finishedAt: finished,
      ),
    );
    final saved = (await StoredOperationJournal(store).load()).single;
    expect(saved.finishedAt, finished);
    expect(saved.completedSuccessfully, isTrue);
  });

  test('旧schema 1のヘッダーと追記完了イベントを読み込める', () async {
    final store = MemoryStore();
    final p = plan(targets: [alice]);
    final journal = StoredOperationJournal(store);
    await journal.save(
      OperationReport(
        id: 'legacy',
        plan: p,
        rows: [OperationRow(alice, Outcome.pending, '')],
        startedAt: start,
      ),
    );
    final header =
        jsonDecode((await store.read('operation_legacy'))!.trim())
            as Map<String, dynamic>;
    header.remove('finishedAt');
    await store.write('operation_legacy', '${jsonEncode(header)}\n');
    final finished = start.add(const Duration(minutes: 1));
    await journal.save(
      OperationReport(
        id: 'legacy',
        plan: p,
        rows: [OperationRow(alice, Outcome.success, '')],
        startedAt: start,
        finishedAt: finished,
      ),
    );
    // 改行に達しない最後のイベントは引き続き採用しない。
    await store.append('operation_legacy', '{"updates":');
    final loaded = (await StoredOperationJournal(store).load()).single;
    expect(loaded.finishedAt, finished);
    expect(loaded.count(Outcome.success), 1);
  });

  test('再起動後の取消を初回保存しても未完了へ戻らない', () async {
    final store = MemoryStore();
    await _seed(store, plan(), blocked: true, credential: false);
    final gateway = FakeGateway();
    final c = _controller(gateway, store, _Host());
    addTearDown(c.dispose);
    await c.initialize();
    await c.discardPending();
    expect(await PendingTaskStore(store).load(), isNull);
    final loaded = (await StoredOperationJournal(store).load()).single;
    expect(loaded.finishedAt, isNotNull);
    expect(loaded.count(Outcome.unprocessed), 2);
    expect(gateway.writes, 0);
  });

  test('再開操作が403で停止したら失敗を通知し自動終了・自動再送しない', () async {
    final store = MemoryStore();
    await _seed(store, plan());
    final host = _Host();
    final gateway = FakeGateway()
      ..writeError = const AppFailure('権限不足', status: 403);
    final c = _controller(gateway, store, host);
    addTearDown(c.dispose);
    await c.initialize();
    expect(gateway.writes, 1);
    expect(c.latestReport!.count(Outcome.failed), 1);
    expect(c.latestReport!.count(Outcome.unprocessed), 1);
    expect(host.close, [false]);
    expect(host.failures, [true]);
    expect(c.error, contains('失敗 1人'));
    expect(host.messages.single, contains('未処理 1人'));
    expect(await PendingTaskStore(store).load(), isNull);
    await c.resumePending(force: true);
    expect(gateway.writes, 1);
  });

  for (final skipped in [false, true]) {
    test('正常な${skipped ? 'スキップ' : '付与'}完了は自動終了の対象を維持する', () async {
      final store = MemoryStore();
      await _seed(store, plan(targets: [skipped ? bob : alice]));
      final host = _Host();
      final gateway = FakeGateway();
      final c = _controller(gateway, store, host);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.error, isNull);
      expect(host.close, [true]);
      expect(host.failures, [false]);
      expect(gateway.writes, skipped ? 0 : 1);
    });
  }

  test('再開記録を使わない経路でも一部失敗は自動終了しない', () async {
    final store = MemoryStore();
    final host = _Host();
    final gateway = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final c = _controller(gateway, store, host, persistent: false);
    addTearDown(c.dispose);
    await c.connect('fixture-only', remember: false);
    await c.extract(conditions());
    gateway.writeError = const AppFailure('権限不足', status: 403);
    await c.execute(c.additionPlan());
    expect(host.close.last, isFalse);
    expect(host.failures.last, isTrue);
    expect(c.error, contains('失敗 1人'));
  });

  test('利用者の中止は失敗扱いにせず自動終了しない', () async {
    final store = MemoryStore();
    await _seed(store, plan());
    final host = _Host();
    final gateway = FakeGateway();
    final c = _controller(gateway, store, host);
    addTearDown(c.dispose);
    gateway.onWrite = c.cancel;
    await c.initialize();
    expect(host.close, [false]);
    expect(host.failures, [false]);
    expect(await PendingTaskStore(store).load(), isNull);
  });

  test('保存しない再接続でも再開条件とJST表示を一致させる', () async {
    final store = MemoryStore();
    final selected = Conditions(
      guildId: '1',
      channelId: '4',
      roleId: '2',
      start: parseJst('2026/01/01 09:00'),
      end: parseJstMinuteEnd('2026/01/02 09:00'),
      minimum: 7,
      excludeBots: false,
      includeContent: true,
      includeAttachments: true,
    );
    final task = PendingTask(
      id: 'extract',
      botId: bot.id,
      kind: 'extract',
      payload: encodeConditions(selected),
    );
    await PendingTaskStore(store).save(task.withBlocked(true));
    final gateway = FakeGateway();
    final c = _controller(gateway, store, _Host());
    addTearDown(c.dispose);
    await c.initialize();
    final revision = c.settingsRevision;
    await c.connect('fixture-only', remember: false);
    final input = c.settings.input;
    expect(c.settingsRevision, greaterThan(revision));
    expect(input.start, '2026/01/01 09:00');
    expect(input.end, '2026/01/02 09:00');
    expect(input.minimum, '7');
    expect(input.excludeBots, isFalse);
    expect(input.includeContent, isTrue);
    expect(input.includeAttachments, isTrue);
    expect(c.extraction!.conditions.fingerprint, selected.fingerprint);
    expect(c.settings.guildId, selected.guildId);
    expect(c.settings.selections['1']!.channelId, selected.channelId);
    expect(c.settings.selections['1']!.roleId, selected.roleId);
    expect(await store.read(), isNull);
    expect(await store.read('settings_9'), isNull);
    expect(gateway.writes, 0);
  });
}
