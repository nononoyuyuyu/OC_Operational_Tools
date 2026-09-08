import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'legacy_storage_migration.dart';
import 'file_store.dart';
import '../ports.dart';

class NativeStore extends FileLocalStore {
  NativeStore() : super(_directory);
  static Future<Directory> _directory() async {
    final root = await organizerSupportDirectory();
    return Directory('${root.path}/$organizerStorageDirectory/v1');
  }
}

class NativeCredentials implements CredentialStore {
  NativeCredentials({Future<Directory> Function()? prepareStorage})
    : _prepareStorage = prepareStorage ?? organizerSupportDirectory;
  final _storage = const FlutterSecureStorage();
  final Future<Directory> Function() _prepareStorage;
  static const _key = 'open_campus_organizer.discord.bot_token.v1';
  @override
  Future<String?> read() async {
    await _prepareStorage();
    final saved = await _storage.read(key: _key);
    if (saved != null) return saved;
    final previous = await _storage.read(key: legacyCredentialKey);
    if (previous != null) {
      await _storage.write(key: _key, value: previous);
      await _storage.delete(key: legacyCredentialKey);
    }
    return previous;
  }

  @override
  Future<void> save(String token) async {
    await _prepareStorage();
    await _storage.write(key: _key, value: token);
    await _storage.delete(key: legacyCredentialKey);
  }

  @override
  Future<void> delete() async {
    await _prepareStorage();
    await _storage.delete(key: _key);
    await _storage.delete(key: legacyCredentialKey);
  }
}

LocalStore createLocalStore() => NativeStore();
CredentialStore createCredentialStore() => NativeCredentials();
