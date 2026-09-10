import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/platform/file_store.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('oco-store-io-');
  });
  tearDown(() => root.delete(recursive: true));

  test('置換・追記・読取が呼出し順に確定し一時ファイルを残さない', () async {
    final store = FileLocalStore(() async => root);
    final first = store.write('history', 'first');
    final append = store.append('history', '+second');
    final read = store.read('history');
    final last = store.write('history', 'last');
    await Future.wait([first, append, last]);
    expect(await read, 'first+second');
    expect(await store.read('history'), 'last');
    expect(await root.list().map((e) => e.uri.pathSegments.last).toList(), [
      'history.data',
    ]);
  });

  test('別キーの保存は遅い保存に巻き込まれない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var lookups = 0;
    final store = FileLocalStore(() async {
      if (++lookups == 1) {
        started.complete();
        await release.future;
      }
      return root;
    });
    final slow = store.write('slow', 'one');
    await started.future;
    try {
      await store.write('other', 'two').timeout(const Duration(seconds: 2));
      expect(await store.read('other'), 'two');
    } finally {
      release.complete();
      await slow;
    }
  });

  test('保存先取得の失敗後も同じキーへの次の書込みを続ける', () async {
    var attempts = 0;
    final store = FileLocalStore(() async {
      if (++attempts == 1) throw const FileSystemException('試験用失敗');
      return root;
    });
    final first = store.write('setting', 'lost');
    final checked = expectLater(first, throwsA(isA<FileSystemException>()));
    final next = store.write('setting', 'saved');
    await checked;
    await next;
    expect(await store.read('setting'), 'saved');
  });

  test('置換失敗では一時ファイルだけを片付け元の対象を残す', () async {
    final destination = await Directory('${root.path}/setting.data').create();
    final marker = File('${destination.path}/keep');
    await marker.writeAsString('keep');
    final store = FileLocalStore(() async => root);
    await expectLater(
      store.write('setting', 'new'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await marker.readAsString(), 'keep');
    expect((await root.list().toList()).length, 1);
    await destination.delete(recursive: true);
    await store.write('setting', 'recovered');
    expect(await store.read('setting'), 'recovered');
  });

  test('別インスタンスの同時置換も一時ファイルを共有しない', () async {
    final first = FileLocalStore(() async => root);
    final second = FileLocalStore(() async => root);
    final values = List.generate(20, (i) => '$i:${'x' * 10000}');
    await Future.wait([
      for (var i = 0; i < values.length; i++)
        (i.isEven ? first : second).write('shared', values[i]),
    ]);
    // 複数インスタンス間の順序保証ではなく、混在・欠落・一時名衝突の防止。
    expect(values, contains(await first.read('shared')));
    expect((await root.list().toList()).length, 1);
  });

  test('CSVの拡張子と一覧の形式を維持し危険な保存名を拒否する', () async {
    final store = FileLocalStore(() async => root);
    await store.write('result_1_csv', 'csv');
    await store.write('operation_1', 'journal');
    expect(await File('${root.path}/result_1_csv.csv').readAsString(), 'csv');
    expect(await store.keys('operation_'), ['operation_1']);
    for (final key in ['', '../escape', '/absolute', 'a/b', 'a\nb', 'a\n']) {
      await expectLater(store.write(key, 'no'), throwsA(isA<AppFailure>()));
    }
  });
}
