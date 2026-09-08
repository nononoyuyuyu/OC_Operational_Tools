import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

void main() {
  final people = List.generate(
    12,
    (i) => Member('${10000 + i}', 'member$i', roles: i == 0 ? {'2'} : {}),
  );
  FakeGateway fixture() => FakeGateway()
    ..people.addEntries(people.map((m) => MapEntry(m.id, m)))
    ..messagePages = [
      people.indexed
          .map((item) => Message('${50000 + item.$1}', '4', item.$2, start))
          .toList(),
    ];

  test('複数投稿者は一覧1回で現在の名前とロールを照合する', () async {
    final g = fixture()..memberPages = [people];
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.users.length, 12);
    expect(result.users.first.hasRole, isTrue);
    expect(g.membersCalls, 1);
    expect(g.memberCalls, 0);
  });
  test('一覧から見つからない投稿者も個別照会し、退出を決めつけない', () async {
    final g = fixture()..memberPages = [people.take(11).toList()];
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.users.every((u) => u.member.present), isTrue);
    expect(g.memberCalls, 1);
  });
  test('一覧が403なら個別照合に切り替える', () async {
    final g = fixture()..failMemberPage = 0;
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.users.length, 12);
    expect(g.membersCalls, 1);
    expect(g.memberCalls, 12);
  });
  test('Intentなしでは一覧取得せず個別照合する', () async {
    final g = fixture();
    const limited = BotIdentity(
      '9',
      'Bot',
      '9',
      membersIntent: false,
      contentIntent: true,
    );
    await ExtractionService(
      g,
    ).extract(guild, conditions(), limited, Cancellation(), noProgress);
    expect(g.membersCalls, 0);
    expect(g.memberCalls, 12);
  });
  test('大規模サーバーの照合は4ページで個別照会に切り替える', () async {
    final g = fixture()
      ..memberPages = List.generate(
        5,
        (p) => List.generate(
          1000,
          (i) => Member('${100000 + p * 1000 + i}', 'unrelated'),
        ),
      );
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.users.every((u) => u.member.present), isTrue);
    expect(g.membersCalls, 4);
    expect(g.memberCalls, 12);
  });
  test('一覧のカーソルが進まない場合は不完全な結果を返さない', () async {
    final page = List.generate(
      1000,
      (i) => Member('${100000 + i}', 'unrelated'),
    );
    final g = fixture()..memberPages = [page, page];
    await expectLater(
      ExtractionService(
        g,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
  });
  test('短い処理でも20人ごとにロール設定を照合する', () async {
    final targets = List.generate(50, (i) => Member('${100 + i}', 'target$i'));
    final g = FakeGateway()
      ..people.addEntries(targets.map((m) => MapEntry(m.id, m)));
    final time = DateTime.now();
    final result = await OperationService(g, FakeJournal(), now: () => time)
        .execute(
          plan(targets: targets),
          'current',
          Cancellation(),
          noProgress,
          (_) {},
        );
    expect(result.count(Outcome.success), 50);
    expect(g.contextCalls, 3);
    expect(g.memberCalls, 50);
  });
  test('更新をDiscordが403で拒否したら残りを送信しない', () async {
    final g = FakeGateway()..writeError = const AppFailure('権限不足', status: 403);
    final result = await OperationService(
      g,
      FakeJournal(),
    ).execute(plan(), 'current', Cancellation(), noProgress, (_) {});
    expect(g.writes, 1);
    expect(result.count(Outcome.failed), 1);
    expect(result.count(Outcome.unprocessed), 1);
  });
}
