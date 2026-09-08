import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/features/kakutei/data/operation_journal.dart';
import 'package:open_campus_organizer/features/kakutei/domain/csv.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/jst.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/permissions.dart';
import 'support.dart';

void main() {
  group('日時・権限', () {
    test('日本時間を端末のタイムゾーンに依存せず往復する', () {
      expect(parseJst('2026/01/01 09:00'), DateTime.utc(2026));
      expect(formatJst(DateTime.utc(2025, 12, 31, 15)), '2026/01/01 00:00');
      expect(parseJst('2024/02/29 00:00').isUtc, isTrue);
    });
    for (final date in [
      '2026/02/29 12:00',
      '2026/04/31 12:00',
      '2026/01/01 24:00',
      '2026/01/01 12:60',
      '2026/1/1 0:00',
    ]) {
      test(
        '不正な日時を拒否する: $date',
        () => expect(() => parseJst(date), throwsA(isA<AppFailure>())),
      );
    }
    test('ロールの許可よりメンバー個別の拒否が優先する', () {
      final c = contextWith(
        overwrites: [
          Overwrite('1', 0, BigInt.zero, viewChannel),
          Overwrite('3', 0, viewChannel, BigInt.zero),
          Overwrite('9', 1, BigInt.zero, readHistory),
        ],
      );
      expect(
        hasPermission(channelPermissions(c, c.channel('4')), viewChannel),
        isTrue,
      );
      expect(() => requireReadable(c, '4'), throwsA(isA<AppFailure>()));
    });
    test('保護ロール・同順位以上のロールを拒否する', () {
      final c = contextWith();
      expect(roleBlockReason(c, targetRole), isNull);
      for (final role in [
        Role('1', '@everyone', 0),
        Role('5', '管理', 1, permissions: administrator),
        Role('6', '連携', 1, managed: true),
        Role('7', '同順位', 10),
        Role('8', '上位', 11),
      ]) {
        expect(roleBlockReason(c, role), isNotNull);
      }
    });
    test('管理者権限はチャンネルの上書きを迂回する', () {
      final c = GuildContext(
        guild,
        '99',
        me,
        [
          Role('1', '@everyone', 0),
          Role('3', '管理', 10, permissions: administrator),
        ],
        [
          Channel(
            '4',
            '連絡',
            overwrites: [
              Overwrite('9', 1, BigInt.zero, viewChannel | readHistory),
            ],
          ),
        ],
      );
      expect(() => requireReadable(c, '4'), returnsNormally);
    });
  });
  group('投稿者抽出', () {
    test('日時の両端を含め、Botを除外し、同名をIDで区別する', () async {
      final g = FakeGateway()
        ..messagePages = [
          [
            Message('106', '4', alice, start.add(const Duration(days: 2))),
            Message('105', '4', alice, start.add(const Duration(days: 1))),
            Message('104', '4', bob, start.add(const Duration(hours: 2))),
            Message('103', '4', alice, start),
            Message('103', '4', alice, start),
            Message('102', '4', me, start),
            Message(
              '101',
              '4',
              alice,
              start.subtract(const Duration(seconds: 1)),
            ),
          ],
        ];
      final result = await ExtractionService(
        g,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress);
      expect(result.messages.length, 3);
      expect(result.users.length, 2);
      expect(result.excludedBots, 1);
      expect(result.users.first.count, 2);
      expect(result.users.last.hasRole, isTrue);
    });
    test('最小投稿数をメンバーに適用し、投稿CSV用一覧は保持する', () async {
      final g = FakeGateway()
        ..messagePages = [
          [
            Message('101', '4', alice, start),
            Message('102', '4', bob, start),
            Message('103', '4', alice, start),
          ],
        ];
      final result = await ExtractionService(
        g,
      ).extract(guild, conditions(minimum: 2), bot, Cancellation(), noProgress);
      expect(result.users.single.member.id, alice.id);
      expect(result.messages.length, 3);
    });
    test('本文・添付URLを指定しない場合はメモリの結果にも保持しない', () async {
      final g = FakeGateway()
        ..messagePages = [
          [
            Message(
              '101',
              '4',
              alice,
              start,
              content: '本文',
              attachments: ['https://example.com/a'],
            ),
          ],
        ];
      final result = await ExtractionService(
        g,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress);
      expect(result.messages.single.content, isEmpty);
      expect(result.messages.single.attachments, isEmpty);
    });
    test('Intent不足の場合は添付URLのみでも取得を止める', () async {
      const missing = BotIdentity(
        '9',
        'Bot',
        '9',
        membersIntent: false,
        contentIntent: false,
      );
      final g = FakeGateway();
      await expectLater(
        ExtractionService(g).extract(
          guild,
          conditions(attachments: true),
          missing,
          Cancellation(),
          noProgress,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(g.messagePage, 0);
    });
    test('本文欠落と照合失敗を不完全な成功にしない', () async {
      final g = FakeGateway()
        ..messagePages = [
          [Message('101', '4', alice, start)],
        ];
      await expectLater(
        ExtractionService(g).extract(
          guild,
          conditions(content: true),
          bot,
          Cancellation(),
          noProgress,
        ),
        throwsA(isA<AppFailure>()),
      );
      g.messagePage = 0;
      g.lookupError = const AppFailure('照合失敗');
      await expectLater(
        ExtractionService(
          g,
        ).extract(guild, conditions(), bot, Cancellation(), noProgress),
        throwsA(isA<AppFailure>()),
      );
    });
    test('ページカーソルが進まない場合は終了する', () async {
      final page = List.generate(
        100,
        (i) => Message('${1000 + i}', '4', alice, start),
      );
      final g = FakeGateway()..messagePages = [page, page];
      await expectLater(
        ExtractionService(
          g,
        ).extract(guild, conditions(), bot, Cancellation(), noProgress),
        throwsA(isA<AppFailure>()),
      );
    });
    test('解除対象の取得は全ページ成功するまで公開しない', () async {
      final g = FakeGateway()
        ..memberPages = [
          List.generate(
            1000,
            (i) => Member('${100 + i}', 'member', roles: {'2'}),
          ),
        ]
        ..failMemberPage = 1;
      await expectLater(
        ExtractionService(
          g,
        ).removalTargets(guild, '2', bot, Cancellation(), noProgress),
        throwsA(isA<AppFailure>()),
      );
      expect(g.writes, 0);
    });
    test('解除対象を全ページから抽出する', () async {
      final g = FakeGateway()
        ..memberPages = [
          List.generate(
            1000,
            (i) => Member('${100 + i}', 'member', roles: i == 1 ? {'2'} : {}),
          ),
          [
            Member('5000', 'last', roles: {'2'}),
          ],
        ];
      final result = await ExtractionService(
        g,
      ).removalTargets(guild, '2', bot, Cancellation(), noProgress);
      expect(result.map((m) => m.id).toSet(), {'101', '5000'});
    });
  });
  group('ロール操作', () {
    test('古い条件・期限切れは一件も更新しない', () async {
      final g = FakeGateway();
      final service = OperationService(g, FakeJournal());
      await expectLater(
        service.execute(plan(), 'stale', Cancellation(), noProgress, (_) {}),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.execute(
          plan(at: DateTime.now().subtract(const Duration(minutes: 11))),
          'current',
          Cancellation(),
          noProgress,
          (_) {},
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(g.writes, 0);
    });
    test('解除は注意事項へのチェックが必要で、ロール名入力は不要', () async {
      final g = FakeGateway();
      final service = OperationService(g, FakeJournal());
      await expectLater(
        service.execute(
          plan(action: RoleAction.remove),
          'current',
          Cancellation(),
          noProgress,
          (_) {},
          removalAcknowledged: false,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(g.writes, 0);
      final result = await service.execute(
        plan(action: RoleAction.remove),
        'current',
        Cancellation(),
        noProgress,
        (_) {},
        removalAcknowledged: true,
      );
      expect(result.count(Outcome.success), 1);
    });
    test('付与済みをスキップし、送信前の記録を必ず残す', () async {
      final g = FakeGateway();
      final journal = FakeJournal();
      g.onWrite = () =>
          expect(journal.reports.last.rows.first.outcome, Outcome.inFlight);
      final result = await OperationService(
        g,
        journal,
      ).execute(plan(), 'current', Cancellation(), noProgress, (_) {});
      expect(g.writes, 1);
      expect(result.count(Outcome.success), 1);
      expect(result.count(Outcome.skipped), 1);
    });
    test('中止後は残りを未処理として記録する', () async {
      final cancel = Cancellation();
      final g = FakeGateway()..onWrite = cancel.cancel;
      final result = await OperationService(
        g,
        FakeJournal(),
      ).execute(plan(), 'current', cancel, noProgress, (_) {});
      expect(result.count(Outcome.success), 1);
      expect(result.count(Outcome.unprocessed), 1);
      expect(g.writes, 1);
    });
    test('送信後の通信失敗は未確認で記録し、後続を止める', () async {
      final g = FakeGateway()
        ..writeError = const AppFailure('通信失敗', uncertain: true);
      final result = await OperationService(
        g,
        FakeJournal(),
      ).execute(plan(), 'current', Cancellation(), noProgress, (_) {});
      expect(result.count(Outcome.uncertain), 1);
      expect(result.count(Outcome.unprocessed), 1);
      expect(g.writes, 1);
    });
    test('初期記録・送信前記録の保存に失敗したら更新しない', () async {
      for (final failAt in [0, 1]) {
        final g = FakeGateway();
        await expectLater(
          OperationService(
            g,
            FakeJournal()..failAt = failAt,
          ).execute(plan(), 'current', Cancellation(), noProgress, (_) {}),
          throwsA(isA<AppFailure>()),
        );
        expect(g.writes, 0);
      }
    });
    test('実行中に対象ロールの設定が変わったら停止する', () async {
      final g = FakeGateway();
      var time = DateTime.now();
      g.onMember = () => time = time.add(const Duration(seconds: 5));
      g.onContext = () {
        if (g.contextCalls == 2)
          g.contextValue = contextWith(role: Role('2', '変更後', 2));
      };
      final result = await OperationService(
        g,
        FakeJournal(),
        now: () => time,
      ).execute(plan(), 'current', Cancellation(), noProgress, (_) {});
      expect(g.writes, 0);
      expect(result.count(Outcome.failed), 1);
      expect(result.count(Outcome.unprocessed), 1);
    });
  });
  group('CSVと永続記録', () {
    test('数式・空白や不可視文字・引用符・改行を安全化する', () {
      for (final value in [
        '=1+1',
        ' +cmd',
        '\u200b@SUM(1)',
        '\t=1',
        '\r\n-1',
        '＝1',
      ]) {
        expect(csvCell(value).startsWith('"\''), isTrue);
      }
      expect(csvCell('a,"b"\nc'), '"a,""b""\nc"');
      expect(
        csvCell('123456789123456789', identifier: true),
        '"\'123456789123456789"',
      );
    });
    test('UTF-8 BOMと表示名・日本時間を出力する', () {
      final bytes = usersCsv(
        Extraction(
          conditions(),
          [],
          [Activity(alice, 1, start, start, false)],
          excludedBots: 0,
          at: start,
        ),
      );
      expect(bytes.take(3), [239, 187, 191]);
      final text = utf8.decode(bytes);
      expect(text, contains('display_name'));
      expect(text, contains('2026/01/01 09:00'));
      expect(text, contains('同じ名前'));
    });
    test('追記途中で終了しても直前の送信中を未確認として復元する', () async {
      final store = MemoryStore();
      final journal = StoredOperationJournal(store);
      final p = plan();
      await journal.save(
        OperationReport(
          id: '1',
          plan: p,
          rows: [OperationRow(alice, Outcome.pending, '')],
          startedAt: start,
        ),
      );
      await journal.save(
        OperationReport(
          id: '1',
          plan: p,
          rows: [OperationRow(alice, Outcome.inFlight, '')],
          startedAt: start,
        ),
      );
      await store.append('operation_1', '{"updates":');
      final recovered = await StoredOperationJournal(store).load();
      expect(recovered.single.rows.single.outcome, Outcome.uncertain);
    });
    test('自動保存を選択した場合、終了時に結果CSVを保存する', () async {
      final store = MemoryStore();
      final journal = StoredOperationJournal(store);
      await journal.setAutoSaveCsv(true);
      await OperationService(
        FakeGateway(),
        journal,
      ).execute(plan(), 'current', Cancellation(), noProgress, (_) {});
      final csv = await store.keys('result_');
      expect(csv.length, 1);
      expect(await store.read(csv.single), contains('成功'));
      expect(
        (await StoredOperationJournal(store).load()).single.finishedAt,
        isNotNull,
      );
    });
    test('未知の記録形式を黙って無視しない', () async {
      final store = MemoryStore();
      await store.write('operation_1', '{"schema":99}\n');
      await expectLater(
        StoredOperationJournal(store).load(),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
