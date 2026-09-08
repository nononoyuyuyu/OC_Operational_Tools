import 'ports.dart';

class ScopedStore implements LocalStore {
  ScopedStore(this.store, this.namespace) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(namespace)) {
      throw ArgumentError.value(namespace, 'namespace');
    }
  }
  final LocalStore store;
  final String namespace;
  String _key(String key) => '${namespace}_$key';
  @override
  Future<String?> read(String key) => store.read(_key(key));
  @override
  Future<void> write(String key, String value) => store.write(_key(key), value);
  @override
  Future<void> append(String key, String value) =>
      store.append(_key(key), value);
  @override
  Future<List<String>> keys(String prefix) async => (await store.keys(
    _key(prefix),
  )).map((key) => key.substring(namespace.length + 1)).toList();
}
