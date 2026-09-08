import 'dart:typed_data';

abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> save(String token);
  Future<void> delete();
}

abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> append(String key, String value);
  Future<List<String>> keys(String prefix);
}

abstract interface class ExportSink {
  Future<String?> export(String name, Uint8List bytes);
}
