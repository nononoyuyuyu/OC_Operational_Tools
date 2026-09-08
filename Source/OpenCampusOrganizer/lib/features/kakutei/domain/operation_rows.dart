import 'dart:collection';
import 'models.dart';

/// 変更された葉とその経路だけをコピーする、不変の操作結果一覧。
/// 1人の更新は最大32行の葉とO(log N)個の節点を作り、旧スナップショットを保つ。
class OperationRows extends ListBase<OperationRow> {
  factory OperationRows(Iterable<OperationRow> rows) {
    if (rows is OperationRows) return rows;
    final values = rows.toList(growable: false);
    return OperationRows._(
      values.isEmpty ? null : _RowsNode.build(values, 0, values.length),
    );
  }
  OperationRows._(this._root);
  final _RowsNode? _root;
  @override
  int get length => _root?.length ?? 0;
  @override
  set length(int _) => throw UnsupportedError('操作結果は変更できません。');
  @override
  OperationRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _root!.at(index);
  }

  @override
  void operator []=(int index, OperationRow value) =>
      throw UnsupportedError('操作結果は変更できません。');
  @override
  Iterator<OperationRow> get iterator =>
      (_root?.values ?? const <OperationRow>[]).iterator;
  int count(Outcome outcome) => _root?.counts[outcome.index] ?? 0;
  OperationRows updated(int index, OperationRow value) {
    RangeError.checkValidIndex(index, this);
    return OperationRows._(_root!.updated(index, value));
  }

  Iterable<int> changedIndexes(OperationRows previous) {
    if (length != previous.length) throw ArgumentError('操作結果の人数が変わっています。');
    return _root == null ? const [] : _root.differences(previous._root!, 0);
  }
}

class _RowsNode {
  _RowsNode.leaf(List<OperationRow> values)
    : leaf = List.unmodifiable(values),
      left = null,
      right = null,
      length = values.length,
      counts = List.filled(Outcome.values.length, 0) {
    for (final row in values) {
      counts[row.outcome.index]++;
    }
  }
  _RowsNode.branch(_RowsNode a, _RowsNode b)
    : left = a,
      right = b,
      leaf = null,
      length = a.length + b.length,
      counts = List.generate(
        Outcome.values.length,
        (i) => a.counts[i] + b.counts[i],
      );
  static _RowsNode build(List<OperationRow> rows, int start, int end) {
    if (end - start <= 32) return _RowsNode.leaf(rows.sublist(start, end));
    final middle = start + (end - start) ~/ 2;
    return _RowsNode.branch(
      build(rows, start, middle),
      build(rows, middle, end),
    );
  }

  final List<OperationRow>? leaf;
  final _RowsNode? left, right;
  final int length;
  final List<int> counts;
  OperationRow at(int index) => leaf != null
      ? leaf![index]
      : index < left!.length
      ? left!.at(index)
      : right!.at(index - left!.length);
  Iterable<OperationRow> get values sync* {
    if (leaf != null) {
      yield* leaf!;
    } else {
      yield* left!.values;
      yield* right!.values;
    }
  }

  _RowsNode updated(int index, OperationRow value) {
    if (leaf != null) {
      if (identical(leaf![index], value)) return this;
      final next = List<OperationRow>.of(leaf!);
      next[index] = value;
      return _RowsNode.leaf(next);
    }
    return index < left!.length
        ? _RowsNode.branch(left!.updated(index, value), right!)
        : _RowsNode.branch(left!, right!.updated(index - left!.length, value));
  }

  Iterable<int> differences(_RowsNode previous, int offset) sync* {
    if (identical(this, previous)) return;
    if (leaf != null) {
      for (var i = 0; i < length; i++) {
        if (!identical(leaf![i], previous.leaf![i])) yield offset + i;
      }
    } else {
      yield* left!.differences(previous.left!, offset);
      yield* right!.differences(previous.right!, offset + left!.length);
    }
  }
}
