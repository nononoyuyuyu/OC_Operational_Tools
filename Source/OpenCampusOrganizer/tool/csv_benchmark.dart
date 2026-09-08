import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:open_campus_organizer/features/kakutei/domain/csv.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';

// Reference of the encoder at 3f69968, used only for byte-equivalence tests
// and a synthetic benchmark. Never called by the application.
Uint8List legacyEncode(List<String> headers, Iterable<List<String>> rows) =>
    Uint8List.fromList([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode(
        [
          headers.map((v) => csvCell(v)).join(','),
          ...rows.map((r) => r.join(',')),
          '',
        ].join('\r\n'),
      ),
    ]);

Uint8List legacyOperationsCsv(OperationReport report) => legacyEncode(
  [
    'operation_id',
    'guild_id',
    'role_id',
    'role_name',
    'user_id',
    'display_name',
    'server_nickname',
    'username',
    'global_name',
    'action',
    'result',
    'reason',
  ],
  report.rows.map(
    (r) => [
      csvCell(report.id, identifier: true),
      csvCell(report.plan.guild.id, identifier: true),
      csvCell(report.plan.role.id, identifier: true),
      csvCell(report.plan.role.name),
      csvCell(r.member.id, identifier: true),
      csvCell(r.member.displayName),
      csvCell(r.member.nickname),
      csvCell(r.member.username),
      csvCell(r.member.globalName),
      csvCell(report.plan.action.name),
      csvCell(outcomeLabel(r.outcome)),
      csvCell(r.reason),
    ],
  ),
);

OperationReport fixtureReport(int count) {
  final people = List.generate(
    count,
    (i) => Member('${100 + i}', 'student$i', globalName: '学生 $i 😀'),
  );
  final at = DateTime.utc(2026, 1, 1);
  final plan = RolePlan(
    guild: const Guild('1', 'fixture'),
    role: Role('2', '確認', 2),
    action: RoleAction.add,
    targets: people,
    fingerprint: 'fixture',
    createdAt: at,
  );
  final reason = List.filled(32, '確認, "済"\r\n😀').join();
  return OperationReport(
    id: 'fixture',
    plan: plan,
    startedAt: at,
    finishedAt: at,
    rows: [
      for (final person in people) OperationRow(person, Outcome.failed, reason),
    ],
  );
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    final results = <Map<String, dynamic>>[];
    // Isolate process high-water marks; running both in one VM invalidates
    // peak-RSS comparisons because the first run contaminates the second.
    for (final mode in ['baseline', 'optimized']) {
      final child = await Process.run(Platform.resolvedExecutable, [
        Platform.script.toFilePath(),
        mode,
      ]);
      if (child.exitCode != 0) {
        throw StateError('CSV benchmark failed: ${child.stderr}');
      }
      final result =
          jsonDecode(child.stdout.toString().trim()) as Map<String, dynamic>;
      results.add(result);
      stdout.writeln(jsonEncode(result));
    }
    if (results[0]['csv_bytes'] != results[1]['csv_bytes'] ||
        results[0]['checksum32'] != results[1]['checksum32']) {
      throw StateError('Benchmark outputs differ');
    }
    return;
  }
  if (args.length != 1 || !['baseline', 'optimized'].contains(args.single)) {
    throw ArgumentError('Expected baseline or optimized');
  }
  final encode = args.single == 'baseline'
      ? legacyOperationsCsv
      : operationsCsv;
  final warmup = fixtureReport(50);
  for (var i = 0; i < 3; i++) {
    encode(warmup);
  }
  final report = fixtureReport(6000);
  final initialRss = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final bytes = encode(report);
  watch.stop();
  var checksum = 2166136261;
  for (final byte in bytes) {
    checksum = ((checksum ^ byte) * 16777619) & 0xffffffff;
  }
  stdout.writeln(
    jsonEncode({
      'benchmark': 'CSV encoding only; synthetic fixture; fresh Dart VM',
      'mode': args.single,
      'rows': report.rows.length,
      'csv_bytes': bytes.length,
      'checksum32': checksum,
      'elapsed_us': watch.elapsedMicroseconds,
      'initial_rss_bytes': initialRss,
      'max_rss_bytes': ProcessInfo.maxRss,
      'sdk': Platform.version.split('\n').first,
    }),
  );
}
