import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/platform/legacy_storage_migration.dart';
import 'package:open_campus_organizer/core/platform/native_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory previous;
  late Directory current;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('oco-branding-fixture-');
    previous = await Directory('${fixture.path}/previous').create();
    current = await Directory('${fixture.path}/current').create();
  });
  tearDown(() async {
    final tempRoot = Directory.systemTemp.absolute.path;
    if (!fixture.absolute.path.startsWith(
      '$tempRoot${Platform.pathSeparator}',
    )) {
      throw StateError('テスト用ディレクトリの範囲が不正です。');
    }
    await fixture.delete(recursive: true);
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('旧版の設定・履歴と暗号化済みバイト列を移し、元データを保持する', () async {
    final source = await Directory(
      '${previous.path}/$legacyStorageDirectory/v1',
    ).create(recursive: true);
    await File('${source.path}/app_v1_appearance.data').writeAsString('sage');
    await File(
      '${source.path}/kakutei_v1_operation_1.data',
    ).writeAsString('fixture-report');
    await File(
      '${source.path}/kakutei_v1_operation_1_csv.csv',
    ).writeAsString('fixture-csv');
    await File('${source.path}/unknown.tmp').writeAsString('unfinished');
    final encryptedFixture = [0, 1, 255, 30];
    await File(
      '${previous.path}/flutter_secure_storage.dat',
    ).writeAsBytes(encryptedFixture);
    await migrateLegacyWindowsStorage(current, previous);
    final destination = Directory(
      '${current.path}/$organizerStorageDirectory/v1',
    );
    expect(
      await File('${destination.path}/app_v1_appearance.data').readAsString(),
      'sage',
    );
    expect(
      await File(
        '${destination.path}/kakutei_v1_operation_1.data',
      ).readAsString(),
      'fixture-report',
    );
    expect(
      await File(
        '${destination.path}/kakutei_v1_operation_1_csv.csv',
      ).readAsString(),
      'fixture-csv',
    );
    expect(await File('${destination.path}/unknown.tmp').exists(), isFalse);
    expect(
      await File('${current.path}/flutter_secure_storage.dat').readAsBytes(),
      encryptedFixture,
    );
    expect(
      await File('${previous.path}/flutter_secure_storage.dat').readAsBytes(),
      encryptedFixture,
    );
    expect(
      await File('${source.path}/app_v1_appearance.data').readAsString(),
      'sage',
    );
  });

  test('新名称側の設定を上書きせず、完了後に削除した資格情報も復活させない', () async {
    final source = await Directory(
      '${previous.path}/$legacyStorageDirectory/v1',
    ).create(recursive: true);
    final destination = await Directory(
      '${current.path}/$organizerStorageDirectory/v1',
    ).create(recursive: true);
    await File('${source.path}/app_v1_appearance.data').writeAsString('sage');
    await File(
      '${destination.path}/app_v1_appearance.data',
    ).writeAsString('orange');
    await File(
      '${previous.path}/flutter_secure_storage.dat',
    ).writeAsBytes([1, 2, 3]);
    await migrateLegacyWindowsStorage(current, previous);
    expect(
      await File('${destination.path}/app_v1_appearance.data').readAsString(),
      'orange',
    );
    await File('${current.path}/flutter_secure_storage.dat').delete();
    await migrateLegacyWindowsStorage(current, previous);
    expect(
      await File('${current.path}/flutter_secure_storage.dat').exists(),
      isFalse,
    );
  });

  test('移行先が作れない場合は未完了とし、問題解消後に再試行できる', () async {
    final source = await Directory(
      '${previous.path}/$legacyStorageDirectory/v1',
    ).create(recursive: true);
    await File('${source.path}/app_v1_appearance.data').writeAsString('sage');
    final blocker = File('${current.path}/$organizerStorageDirectory');
    await blocker.writeAsString('fixture-conflict');
    await expectLater(
      migrateLegacyWindowsStorage(current, previous),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await File('${current.path}/.oco_storage_migrated_v1').exists(),
      isFalse,
    );
    expect(await blocker.readAsString(), 'fixture-conflict');
    await blocker.delete();
    await migrateLegacyWindowsStorage(current, previous);
    expect(
      await File(
        '${current.path}/$organizerStorageDirectory/v1/app_v1_appearance.data',
      ).readAsString(),
      'sage',
    );
  });

  test('資格情報の旧キーを新キーへ移し、削除後は読み戻さない', () async {
    FlutterSecureStorage.setMockInitialValues({
      legacyCredentialKey: 'fixture-only',
    });
    final credentials = NativeCredentials(prepareStorage: () async => current);
    expect(await credentials.read(), 'fixture-only');
    expect(
      await const FlutterSecureStorage().read(key: legacyCredentialKey),
      isNull,
    );
    await credentials.delete();
    expect(await credentials.read(), isNull);
  });
}
