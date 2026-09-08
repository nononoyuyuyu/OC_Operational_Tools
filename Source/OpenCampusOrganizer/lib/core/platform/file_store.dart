import 'dart:io';
import '../failure.dart';
import '../ports.dart';

/// NativeStoreと実ファイル検証で共用する、保存先に依存しないファイルI/O。
class FileLocalStore implements LocalStore {
  FileLocalStore(this.directory);
  final Future<Directory> Function() directory;
  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(key)) {
      throw const AppFailure('保存名が正しくありません。');
    }
    final root = await directory();
    await root.create(recursive: true);
    return File('${root.path}/$key.${key.endsWith('_csv') ? 'csv' : 'data'}');
  }

  @override
  Future<String?> read(String key) async {
    final file = await _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> append(String key, String value) async {
    await (await _file(
      key,
    )).writeAsString(value, mode: FileMode.append, flush: true);
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final root = await directory();
    await root.create(recursive: true);
    return root
        .list()
        .where((e) => e is File)
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.startsWith(prefix) && n.endsWith('.data'))
        .map((n) => n.substring(0, n.length - 5))
        .toList();
  }
}
