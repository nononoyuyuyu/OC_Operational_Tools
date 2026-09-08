import 'dart:io';
import 'package:path_provider/path_provider.dart';

// 旧版データの検出にだけ使う固定識別子。画面・新規保存には使用しない。
const legacyProductName = 'OC運営用総合ツール';
const legacyStorageDirectory = 'oc_operations';
const legacyCredentialKey = 'oc_operations.discord.bot_token.v1';
const organizerStorageDirectory = 'open_campus_organizer';
const _migrationMarker = '.oco_storage_migrated_v1';
Future<Directory>? _supportDirectory;

Future<Directory> organizerSupportDirectory() =>
    _supportDirectory ??= () async {
      final root = await getApplicationSupportDirectory();
      if (Platform.isWindows) {
        await migrateLegacyWindowsStorage(
          root,
          Directory('${root.parent.path}/$legacyProductName'),
        );
      }
      return root;
    }();

/// 旧Windows版の通常データと暗号化済み資格情報をコピーする。
/// 元データを残し、新名称側に存在するファイルは上書きしない。
Future<void> migrateLegacyWindowsStorage(
  Directory current,
  Directory legacy,
) async {
  final marker = File('${current.path}/$_migrationMarker');
  if (await marker.exists()) return;
  await current.create(recursive: true);
  final previousData = Directory('${legacy.path}/$legacyStorageDirectory/v1');
  if (await FileSystemEntity.type(previousData.path, followLinks: false) ==
      FileSystemEntityType.directory) {
    final nextData = await Directory(
      '${current.path}/$organizerStorageDirectory/v1',
    ).create(recursive: true);
    await for (final entry in previousData.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!RegExp(r'^[a-z0-9_]+\.(data|csv)$').hasMatch(name)) continue;
      await _copyIfMissing(entry, File('${nextData.path}/$name'));
    }
  }
  // DPAPIで暗号化されたまま移す。移行処理では復号しない。
  final previousCredentials = File('${legacy.path}/flutter_secure_storage.dat');
  if (await FileSystemEntity.type(
        previousCredentials.path,
        followLinks: false,
      ) ==
      FileSystemEntityType.file) {
    await _copyIfMissing(
      previousCredentials,
      File('${current.path}/flutter_secure_storage.dat'),
    );
  }
  // 完了後は旧資格情報を再取り込みしない。Token削除後の復活も防ぐ。
  await marker.writeAsString('1', flush: true);
}

Future<void> _copyIfMissing(File source, File destination) async {
  if (await destination.exists()) return;
  final temporary = File('${destination.path}.migration.tmp');
  await source.copy(temporary.path);
  if (await destination.exists()) {
    await temporary.delete();
    return;
  }
  await temporary.rename(destination.path);
}
