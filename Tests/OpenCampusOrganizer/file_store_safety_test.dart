import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/platform/file_store.dart';

void main() {
  test('同じキーへの書込みは呼出し順を守る', () async {
    final root = await Directory.systemTemp.createTemp('oco-store-order-');
    addTearDown(() => root.delete(recursive: true));
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
    final first = store.write('setting', 'first');
    await started.future;
    final last = store.write('setting', 'last');
    await Future<void>.delayed(Duration.zero);
    final lookupsWhileBlocked = lookups;
    // 旧実装では二番目が先に完了する条件を確定させてから一番目を解放する。
    if (lookupsWhileBlocked > 1) await last;
    release.complete();
    await Future.wait([first, last]);
    expect(lookupsWhileBlocked, 1);
    expect(await store.read('setting'), 'last');
  });

  test(
    '予測可能な一時パスのリンクをたどって別ファイルを上書きしない',
    () async {
      final root = await Directory.systemTemp.createTemp('oco-store-link-');
      addTearDown(() => root.delete(recursive: true));
      final data = await Directory('${root.path}/data').create();
      final unrelated = File('${root.path}/unrelated.txt');
      await unrelated.writeAsString('keep');
      final planted = Link('${data.path}/setting.data.tmp');
      await planted.create(unrelated.path);
      final store = FileLocalStore(() async => data);
      await store.write('setting', 'new');
      expect(await unrelated.readAsString(), 'keep');
      expect(await store.read('setting'), 'new');
      expect(await planted.exists(), isTrue);
    },
    skip: Platform.isWindows ? 'Windowsのリンク作成権限に依存しない' : false,
  );
}
