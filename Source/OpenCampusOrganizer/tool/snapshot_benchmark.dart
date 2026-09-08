// dart run tool/snapshot_benchmark.dart <baseline|current> <人数>
// 旧List.unmodifiable + 全行集計と、経路共有したOperationReportを別プロセスで比較する。
// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/features/kakutei/domain/models.dart';
import '../lib/features/kakutei/domain/operation_rows.dart';

void main(List<String> args) {
  if (args.length != 2 || !['baseline', 'current'].contains(args[0])) {
    throw ArgumentError('baseline/current と人数を指定してください');
  }
  final count = int.parse(args[1]);
  final values = List.generate(
    count,
    (i) => OperationRow(Member('$i', 'fixture $i'), Outcome.pending, ''),
  );
  var shared = OperationRows(values);
  final plan = RolePlan(
    guild: const Guild('1', 'fixture'),
    role: Role('2', 'role', 1),
    action: RoleAction.add,
    targets: values.map((r) => r.member).toList(),
    fingerprint: 'fixture',
    createdAt: DateTime.utc(2026),
  );
  final construction = Stopwatch(), counts = Stopwatch();
  var checksum = 0;
  final startRss = ProcessInfo.currentRss;
  for (var step = 0; step < count * 2; step++) {
    final index = step ~/ 2;
    final row = OperationRow(
      values[index].member,
      step.isEven ? Outcome.inFlight : Outcome.success,
      '',
    );
    construction.start();
    if (args[0] == 'baseline') {
      values[index] = row;
      final snapshot = List<OperationRow>.unmodifiable(values);
      construction.stop();
      counts.start();
      for (final outcome in Outcome.values) {
        checksum += snapshot.where((r) => r.outcome == outcome).length;
      }
    } else {
      shared = shared.updated(index, row);
      final report = OperationReport(
        id: 'fixture',
        plan: plan,
        rows: shared,
        startedAt: plan.createdAt,
      );
      construction.stop();
      counts.start();
      for (final outcome in Outcome.values) {
        checksum += report.count(outcome);
      }
    }
    counts.stop();
  }
  if (checksum != count * count * 2) throw StateError('集計が一致しません');
  stdout.writeln(
    jsonEncode({
      'mode': args[0],
      'count': count,
      'snapshots': count * 2,
      'constructionUs': construction.elapsedMicroseconds,
      'countsUs': counts.elapsedMicroseconds,
      'checksum': checksum,
      'startRss': startRss,
      'maxRss': ProcessInfo.maxRss,
    }),
  );
}
