// 架空データ専用。指定した新規ディレクトリへ保存し、測定資料として残す。
// operations <人数> <新規保存先> / seed <履歴件数> <新規保存先>
// history <indexed|legacy> <seedで作成した保存先>
// 旧版のlibへ同じスクリプトとFileLocalStoreを配置すると同一条件で比較できる。
// パッケージ設定のない旧ソース展開先でも実行するため、相対importを使う。
// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/core/failure.dart';
import '../lib/core/ports.dart';
import '../lib/core/platform/file_store.dart';
import '../lib/features/kakutei/data/operation_journal.dart';
import '../lib/features/kakutei/domain/gateway.dart';
import '../lib/features/kakutei/domain/models.dart';
import '../lib/features/kakutei/domain/operation_service.dart';
import '../lib/features/kakutei/domain/permissions.dart';

class CountedStore implements LocalStore {
  CountedStore(this.root) : files = FileLocalStore(() async => root);
  final Directory root;
  final FileLocalStore files;
  int reads = 0, primaryReads = 0, summaryReads = 0, writes = 0, appends = 0;
  @override
  Future<String?> read(String key) {
    reads++;
    if (key.startsWith('operation_')) primaryReads++;
    if (key.startsWith('history_summary_')) summaryReads++;
    return files.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writes++;
    return files.write(key, value);
  }

  @override
  Future<void> append(String key, String value) {
    appends++;
    return files.append(key, value);
  }

  @override
  Future<List<String>> keys(String prefix) => files.keys(prefix);
  Future<int> bytes() async {
    var total = 0;
    await for (final file in root.list()) {
      if (file is File) total += await file.length();
    }
    return total;
  }
}

const guild = Guild('1', '架空サーバー');
final role = Role('2', '参加確定', 2);
Member member(int i) => Member('${1000 + i}', '架空メンバー $i');
RolePlan plan(int count) => RolePlan(
  guild: guild,
  role: role,
  action: RoleAction.add,
  targets: List.generate(count, member),
  fingerprint: 'fixture',
  createdAt: DateTime.now().toUtc(),
);

class FixtureGateway implements DiscordGateway {
  int sends = 0;
  @override
  Future<GuildContext> context(
    Guild guild,
    Cancellation cancel, {
    bool includeChannels = true,
  }) async => GuildContext(
    guild,
    '99',
    Member('9', 'fixture bot', bot: true, roles: {'3'}),
    [
      Role('1', '@everyone', 0),
      role,
      Role('3', 'Bot', 10, permissions: manageRoles),
    ],
    [],
  );
  @override
  Future<Member?> member(
    String guildId,
    String userId,
    Cancellation cancel,
  ) async => Member(userId, '架空メンバー ${int.parse(userId) - 1000}');
  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    sends++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main(List<String> args) async {
  if (args.length != 3 ||
      !['operations', 'seed', 'history'].contains(args[0])) {
    throw ArgumentError(
      'operations/seed <件数> <新規保存先> または history <indexed|legacy> <保存先>',
    );
  }
  final mode = args[0];
  final root = Directory(args[2]).absolute;
  if (mode != 'history') {
    if (await root.exists()) throw StateError('保存先は新規ディレクトリにしてください。');
    await root.create(recursive: true);
  } else if (!await root.exists()) {
    throw StateError('測定用履歴がありません。');
  }
  final store = CountedStore(root);
  final journal = StoredOperationJournal(store);
  final startRss = ProcessInfo.currentRss;
  final elapsed = Stopwatch()..start();
  final extra = <String, Object?>{};
  if (mode == 'operations') {
    final count = int.parse(args[1]);
    final gateway = FixtureGateway();
    final ui = Stopwatch();
    var snapshots = 0, checksum = 0;
    OperationReport? first;
    final report = await OperationService(gateway, journal).execute(
      plan(count),
      'fixture',
      Cancellation(),
      (_, _, _) {},
      (value) {
        first ??= value;
        snapshots++;
        ui.start();
        for (final outcome in Outcome.values) {
          checksum += value.count(outcome);
        }
        ui.stop();
      },
      operationId: 'fixture',
    );
    if (first!.count(Outcome.pending) != count ||
        report.count(Outcome.success) != count ||
        gateway.sends != count) {
      throw StateError('スナップショット不整合');
    }
    extra.addAll({
      'count': count,
      'snapshots': snapshots,
      'uiCountUs': ui.elapsedMicroseconds,
      'checksum': checksum,
      'sends': gateway.sends,
    });
  } else if (mode == 'seed') {
    final count = int.parse(args[1]);
    final p = plan(500);
    final rows = p.targets
        .map((m) => OperationRow(m, Outcome.success, ''))
        .toList();
    for (var i = 0; i < count; i++) {
      final at = DateTime.utc(2026).add(Duration(minutes: i));
      await journal.save(
        OperationReport(
          id: '$i',
          plan: p,
          rows: rows,
          startedAt: at,
          finishedAt: at,
        ),
      );
    }
    extra.addAll({'count': count, 'rowsPerHistory': 500});
  } else {
    if (args[1] == 'legacy') {
      final reports = await journal.load();
      extra.addAll({
        'total': reports.length,
        'retainedRows': reports.fold<int>(0, (sum, r) => sum + r.rows.length),
        'firstId': reports.first.id,
      });
    } else if (args[1] == 'indexed') {
      // 旧版との比較時にも同じスクリプトをコンパイルできるよう能力を動的に選択する。
      final dynamic indexed = journal;
      final dynamic page = await indexed.summaries();
      extra.addAll({
        'total': page.total,
        'summaries': page.items.length,
        'retainedRows': 0,
        'firstId': page.items.first.id,
      });
    } else {
      throw ArgumentError('indexed または legacy を指定してください。');
    }
  }
  elapsed.stop();
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'variant': args[1],
      ...extra,
      'elapsedUs': elapsed.elapsedMicroseconds,
      'startRss': startRss,
      'maxRss': ProcessInfo.maxRss,
      'reads': store.reads,
      'primaryReads': store.primaryReads,
      'summaryReads': store.summaryReads,
      'writes': store.writes,
      'appends': store.appends,
      'diskBytes': await store.bytes(),
      'directory': root.path,
    }),
  );
}
