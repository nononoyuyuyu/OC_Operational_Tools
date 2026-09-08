import '../ports.dart';

class MemoryStore implements LocalStore, CredentialStore {
  final _data = <String, String>{};
  String? _credential;
  @override
  Future<String?> read([String? key]) async =>
      key == null ? _credential : _data[key];
  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> append(String key, String value) async {
    _data[key] = (_data[key] ?? '') + value;
  }

  @override
  Future<List<String>> keys(String prefix) async =>
      _data.keys.where((k) => k.startsWith(prefix)).toList();
  @override
  Future<void> save(String token) async {
    _credential = token;
  }

  @override
  Future<void> delete() async {
    _credential = null;
  }
}
