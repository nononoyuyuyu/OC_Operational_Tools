import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/platform/file_store.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_service.dart';
import 'support.dart';

class ObservedStore extends MemoryStore {
  final reads = <String>[];
  final writes = <String>[];
  final appends = <String>[];
  String? failWrite;
  bool tearAppend = false;
  @override
  Future<String?> read([String? key]) {
    if (key != null) reads.add(key);
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    if (key == failWrite) throw const FileSystemException('fixture disk full');
    await super.write(key, value);
  }

  @override
  Future<void> append(String key, String value) async {
    appends.add(key);
    if (tearAppend) {
      tearAppend = false;
      await super.append(key, value.substring(0, value.length ~/ 2));
      throw const FileSystemException('fixture interrupted append');
    }
    await super.append(key, value);
  }
}

OperationReport storedReport(
  int id, {
  bool finished = true,
  List<OperationRow>? rows,
}) => OperationReport(
  id: '$id',
  plan: plan(),
  startedAt: start.add(Duration(minutes: id)),
  finishedAt: finished ? start.add(Duration(minutes: id + 1)) : null,
  rows:
      rows ??
      [
        OperationRow(alice, Outcome.success, ''),
        OperationRow(bob, Outcome.skipped, '既に保有'),
      ],
);

class DurableGateway extends FakeGateway {
  DurableGateway(this.directory);
  final Directory directory;
  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    // 同じインスタンスのキャッシュを使わず、実際のファイルを別Storeから読み直す。
    final disk = StoredOperationJournal(FileLocalStore(() async => directory));
    final report = (await disk.load()).single;
    expect(
      report.rows.firstWhere((row) => row.member.id == userId).outcome,
      Outcome.uncertain,
    );
    await super.setRole(guildId, userId, roleId, action, cancel);
  }
}

void main() {
  test('1000履歴の起動では30要約、次ページと選択詳細だけを読む', () async {
    final store = ObservedStore();
    final writer = StoredOperationJournal(store);
    for (var id = 0; id < 1000; id++) {
      await writer.save(storedReport(id));
    }
    store.reads.clear();
    final journal = StoredOperationJournal(store);
    final first = await journal.summaries();
    expect(first.total, 1000);
    expect(
      first.items.map((item) => item.id),
      List.generate(30, (i) => '${999 - i}'),
    );
    expect(store.reads.where((key) => key.startsWith('operation_')), isEmpty);
    expect(
      store.reads.where((key) => key.startsWith('history_summary_')).length,
      30,
    );
    store.reads.clear();
    expect((await journal.summaries(offset: 30)).items.first.id, '969');
    expect(store.reads.length, 30);
    store.reads.clear();
    expect((await journal.find('400'))!.rows.length, 2);
    expect(store.reads, ['operation_400']);
    expect(await journal.find('missing'), isNull);
    expect(await store.keys('result_'), isEmpty);
  });

  test('旧schema1の移行と壊れた派生索引・要約を原本を書き換えず回復する', () async {
    final store = ObservedStore();
    await StoredOperationJournal(store).save(storedReport(1));
    final raw = await store.read('operation_1');
    final legacy = ObservedStore();
    await legacy.write('operation_1', raw!);
    final migrated = await StoredOperationJournal(legacy).summaries();
    expect(migrated.items.single.count(Outcome.success), 1);
    expect(await legacy.read('operation_1'), raw);
    await legacy.write('history_index', '{');
    await legacy.write('history_summary_1', '{}');
    expect(
      (await StoredOperationJournal(legacy).summaries()).items.single.id,
      '1',
    );
    await legacy.write('history_summary_1', '{');
    expect(
      (await StoredOperationJournal(
        legacy,
      ).summaries()).items.single.count(Outcome.skipped),
      1,
    );
    expect(await legacy.read('operation_1'), raw);
    // 原本の破損は黙って捨てず、詳細を開く時に明示的に失敗する。
    await legacy.write('operation_1', '{"schema":99}\n');
    await expectLater(
      StoredOperationJournal(legacy).find('1'),
      throwsA(isA<AppFailure>()),
    );
  });

  test('未完了の古い要約は原本で再照合し、破損末尾と未確認・未処理を保持する', () async {
    final store = ObservedStore();
    final journal = StoredOperationJournal(store);
    final first = storedReport(
      1,
      finished: false,
      rows: [
        OperationRow(alice, Outcome.pending, ''),
        OperationRow(bob, Outcome.pending, ''),
      ],
    );
    await journal.save(first);
    await journal.save(
      storedReport(
        1,
        finished: false,
        rows: first.rows.updated(
          0,
          OperationRow(alice, Outcome.inFlight, '送信中'),
        ),
      ),
    );
    await store.append('operation_1', '{"updates":');
    final restarted = StoredOperationJournal(store);
    final summary = (await restarted.summaries()).items.single;
    expect(summary.count(Outcome.uncertain), 1);
    expect(summary.count(Outcome.unprocessed), 1);
    final report = (await restarted.find('1'))!;
    expect(report.rows.map((row) => row.outcome), [
      Outcome.uncertain,
      Outcome.unprocessed,
    ]);
    expect(report.finishedAt, isNull);
  });

  test('索引書込失敗後も原本を保持し、再起動で終了を復元する', () async {
    final store = ObservedStore();
    final journal = StoredOperationJournal(store);
    await journal.save(storedReport(1, finished: false));
    store.failWrite = 'history_index';
    await expectLater(
      journal.save(storedReport(1)),
      throwsA(isA<FileSystemException>()),
    );
    store.failWrite = null;
    final restarted = StoredOperationJournal(store);
    expect((await restarted.summaries()).items.single.finishedAt, isNotNull);
    expect((await restarted.find('1'))!.count(Outcome.success), 1);
  });

  test('途中の追記失敗後は原子置換で復帰し、差分だけを追記する', () async {
    final store = ObservedStore();
    final journal = StoredOperationJournal(store);
    final first = storedReport(
      1,
      finished: false,
      rows: List.generate(
        100,
        (i) => OperationRow(Member('$i', 'm$i'), Outcome.pending, ''),
      ),
    );
    await journal.save(first);
    final next = storedReport(
      1,
      finished: false,
      rows: first.rows.updated(
        73,
        OperationRow(first.rows[73].member, Outcome.inFlight, ''),
      ),
    );
    store.tearAppend = true;
    await expectLater(journal.save(next), throwsA(isA<FileSystemException>()));
    expect(
      (await StoredOperationJournal(store).find('1'))!.count(Outcome.uncertain),
      0,
    );
    await journal.save(next);
    final done = storedReport(
      1,
      rows: next.rows.updated(
        73,
        OperationRow(first.rows[73].member, Outcome.success, ''),
      ),
    );
    await journal.save(done);
    final event = jsonDecode(
      (await store.read('operation_1'))!.trim().split('\n').last,
    );
    expect((event['updates'] as List).map((row) => row['index']), [73]);
    expect(
      (await StoredOperationJournal(store).find('1'))!.count(Outcome.success),
      1,
    );
    final count = store.writes.where((key) => key == 'operation_1').length;
    await journal.save(done);
    // 完了済みの詳細は書込キャッシュから解放され、再保存は独立したヘッダーになる。
    expect(store.writes.where((key) => key == 'operation_1').length, count + 1);
  });

  test('CSV自動保存の選択を復元し、オフへ戻しても過去CSVは残す', () async {
    final store = ObservedStore();
    final journal = StoredOperationJournal(store);
    expect(journal.autoSaveCsv, isFalse);
    await journal.setAutoSaveCsv(true);
    final restarted = StoredOperationJournal(store);
    await restarted.summaries();
    expect(restarted.autoSaveCsv, isTrue);
    await restarted.save(storedReport(1));
    final csv = await store.read('result_1_csv');
    await restarted.setAutoSaveCsv(false);
    await restarted.save(storedReport(2));
    expect(await store.read('result_1_csv'), csv);
    expect(await store.read('result_2_csv'), isNull);
    store.failWrite = 'journal_options';
    await expectLater(
      restarted.setAutoSaveCsv(true),
      throwsA(isA<FileSystemException>()),
    );
    expect(restarted.autoSaveCsv, isFalse);
    store.failWrite = null;
    await store.write('journal_options', '{');
    await expectLater(
      StoredOperationJournal(store).summaries(),
      throwsA(isA<AppFailure>()),
    );
  });

  test('実LocalStoreの送信前flush・再起動・履歴読み戻しを検証する', () async {
    final directory = await Directory.systemTemp.createTemp(
      'oco-journal-fixture-',
    );
    addTearDown(() async {
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final resolved = await directory.resolveSymbolicLinks();
      if (!resolved.startsWith(
        '$tempRoot${Platform.pathSeparator}oco-journal-fixture-',
      )) {
        throw StateError('検証用の一時ディレクトリ以外は削除しません。');
      }
      await Directory(resolved).delete(recursive: true);
    });
    final journal = StoredOperationJournal(
      FileLocalStore(() async => directory),
    );
    final gateway = DurableGateway(directory);
    final snapshots = <OperationReport>[];
    final result = await OperationService(gateway, journal).execute(
      plan(),
      'current',
      Cancellation(),
      noProgress,
      snapshots.add,
      operationId: 'durable',
    );
    expect(gateway.writes, 1);
    expect(snapshots.first.count(Outcome.pending), 2);
    expect(snapshots.first.rows.first.outcome, Outcome.pending);
    final restarted = StoredOperationJournal(
      FileLocalStore(() async => directory),
    );
    expect(
      (await restarted.find('durable'))!.count(Outcome.success),
      result.count(Outcome.success),
    );
    expect((await restarted.summaries()).items.single.finishedAt, isNotNull);
  });
}
