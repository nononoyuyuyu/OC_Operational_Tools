import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_rows.dart';

void main() {
  test('経路共有した更新でも旧スナップショットと順序・集計・差分を保つ', () {
    for (final size in [1, 31, 32, 33, 65, 513]) {
      final values = List.generate(
        size,
        (i) => OperationRow(Member('$i', 'member $i'), Outcome.pending, ''),
      );
      var rows = OperationRows(values);
      final original = rows;
      final random = Random(211);
      for (var step = 0; step < 1000; step++) {
        final previous = rows;
        final index = random.nextInt(size);
        final row = OperationRow(
          values[index].member,
          Outcome.values[step % Outcome.values.length],
          '$step',
        );
        rows = rows.updated(index, row);
        values[index] = row;
        expect(rows.changedIndexes(previous), [index]);
        expect(rows.toList(), values);
        expect(previous[index], isNot(same(row)));
        for (final outcome in Outcome.values) {
          expect(
            rows.count(outcome),
            values.where((row) => row.outcome == outcome).length,
          );
        }
      }
      expect(original.every((row) => row.outcome == Outcome.pending), isTrue);
      expect(rows.changedIndexes(OperationRows(values)), isEmpty);
      expect(() => rows[0] = values[0], throwsUnsupportedError);
      expect(() => rows.add(values[0]), throwsUnsupportedError);
      expect(() => rows.updated(size, values[0]), throwsRangeError);
      expect(() => rows[-1], throwsRangeError);
      expect(OperationRows(rows), same(rows));
    }
  });
  test('空一覧と複数行更新を扱い、人数の食い違いを拒否する', () {
    final empty = OperationRows([]);
    expect(empty.changedIndexes(OperationRows([])), isEmpty);
    expect(empty.count(Outcome.success), 0);
    final rows = OperationRows(
      List.generate(
        100,
        (i) => OperationRow(Member('$i', 'm$i'), Outcome.pending, ''),
      ),
    );
    final changed = rows
        .updated(99, OperationRow(rows[99].member, Outcome.success, ''))
        .updated(1, OperationRow(rows[1].member, Outcome.failed, 'reason'));
    expect(changed.changedIndexes(rows), [1, 99]);
    expect(() => changed.changedIndexes(empty), throwsArgumentError);
  });
}
