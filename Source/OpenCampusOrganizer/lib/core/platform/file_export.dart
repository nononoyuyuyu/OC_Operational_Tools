import 'dart:ui';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../ports.dart';

class FileExport implements ExportSink {
  @override
  Future<String?> export(String name, Uint8List bytes) async {
    final file = XFile.fromData(bytes, mimeType: 'text/csv', name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      return 'ダウンロードを開始しました。';
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [name],
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? null
          : '共有メニューにCSVを渡しました。';
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return null;
    await file.saveTo(location.path);
    return '保存しました: ${location.path}';
  }
}
