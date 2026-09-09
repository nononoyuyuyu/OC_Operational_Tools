import 'dart:io';
import 'dart:math';
import '../failure.dart';
import '../ports.dart';

/// NativeStoreと実ファイル検証で共用する、保存先に依存しないファイルI/O。
class FileLocalStore implements LocalStore {
  FileLocalStore(this.directory);
  final Future<Directory> Function() directory;
  final _operations = <String, Future<void>>{};
  static final _random = Random.secure();

  // 同じキーの読取・置換・追記を呼出し順に実行する。別キーは互いに待たない。
  Future<T> _serial<T>(String key, Future<T> Function() action) {
    final next = (_operations[key] ?? Future<void>.value()).then(
      (_) => action(),
    );
    late final Future<void> tail;
    void release() {
      if (identical(_operations[key], tail)) _operations.remove(key);
    }

    tail = next.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _operations[key] = tail;
    return next;
  }

  Future<File> _file(String key) async {
    if (RegExp(r'^[a-z0-9_]+$').stringMatch(key) != key) {
      throw const AppFailure('保存名が正しくありません。');
    }
    final root = await directory();
    await root.create(recursive: true);
    return File('${root.path}/$key.${key.endsWith('_csv') ? 'csv' : 'data'}');
  }

  Future<File> _temporary(File destination) async {
    final dot = destination.path.lastIndexOf('.');
    final stem = destination.path.substring(0, dot);
    final extension = destination.path.substring(dot);
    for (var attempt = 0; attempt < 5; attempt++) {
      final nonce = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      // 既存のアンインストーラーが識別する「英小文字・数字・_ + .data/.csv.tmp」。
      final temp = File('${stem}_write_$nonce$extension.tmp');
      try {
        return await temp.create(exclusive: true);
      } on PathExistsException {
        // 他の書込みや既存リンクを上書きせず、別名で作り直す。
      }
    }
    throw const AppFailure('保存用の一時ファイルを作成できませんでした。');
  }

  @override
  Future<String?> read(String key) => _serial(key, () async {
    final file = await _file(key);
    return await file.exists() ? file.readAsString() : null;
  });

  @override
  Future<void> write(String key, String value) => _serial(key, () async {
    final file = await _file(key);
    final temp = await _temporary(file);
    try {
      await temp.writeAsString(value, flush: true);
      await temp.rename(file.path);
    } finally {
      // 自分が作成した一時ファイルだけを片付ける。元の保存ファイルには触れない。
      if (await temp.exists()) await temp.delete();
    }
  });

  @override
  Future<void> append(String key, String value) => _serial(key, () async {
    await (await _file(
      key,
    )).writeAsString(value, mode: FileMode.append, flush: true);
  });

  @override
  Future<List<String>> keys(String prefix) async {
    final root = await directory();
    await root.create(recursive: true);
    return root
        .list(followLinks: false)
        .where((e) => e is File)
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.startsWith(prefix) && n.endsWith('.data'))
        .map((n) => n.substring(0, n.length - 5))
        .toList();
  }
}
