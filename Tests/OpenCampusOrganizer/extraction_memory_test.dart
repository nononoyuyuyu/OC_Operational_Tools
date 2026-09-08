import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

class GeneratedMembers extends FakeGateway {
  GeneratedMembers(this.pages, {this.failPage});
  final int pages;
  final int? failPage;
  int requested = 0;
  @override
  Future<List<Member>> members(
    String guildId,
    String? after,
    Cancellation cancel,
  ) async {
    cancel.check();
    final page = requested++;
    if (page == failPage) throw const AppFailure('fixture failure');
    if (page >= pages) return [];
    return List.generate(
      1000,
      (i) => Member(
        '${100 + page * 1000 + i}',
        'student${page * 1000 + i}',
        roles: i == 0 ? {'2'} : {'3', '4', '5'},
      ),
    );
  }
}

void main() {
  test('順不同の日時と重複を1パス集計し最初・最後を保つ', () async {
    final earliest = start.add(const Duration(hours: 1));
    final latest = start.add(const Duration(hours: 3));
    final g = FakeGateway()
      ..messagePages = [
        [
          Message('105', '4', alice, latest),
          Message('103', '4', alice, earliest),
          Message('104', '4', alice, start.add(const Duration(hours: 2))),
          Message('103', '4', alice, earliest),
          Message('102', '4', me, earliest),
        ],
      ];
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    final activity = result.users.single;
    expect(activity.count, 3);
    expect(activity.first, earliest);
    expect(activity.last, latest);
    expect(result.excludedBots, 1);
    expect(result.messages.map((m) => m.id), ['103', '104', '105']);
    expect(
      result.messages.every((m) => identical(m.author, activity.member)),
      isTrue,
    );
  });
  test('最小投稿数未満の投稿もCSV用に残し現在の名前を照合する', () async {
    final g = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    g.people[alice.id] = Member(alice.id, 'current', nickname: '現在の名前');
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(minimum: 2), bot, Cancellation(), noProgress);
    expect(result.users, isEmpty);
    expect(result.messages.single.author.displayName, '現在の名前');
    expect(g.memberCalls, 1);
  });
  test('複数ページでも投稿者別の件数・上下限を保つ', () async {
    final g = FakeGateway();
    final people = List.generate(10, (i) => Member('${100 + i}', 'user$i'));
    for (final m in people) {
      g.people[m.id] = m;
    }
    g.messagePages = List.generate(
      3,
      (page) => List.generate(
        100,
        (i) => Message(
          '${1000 - page * 100 - i}',
          '4',
          people[i % 10],
          start.add(Duration(minutes: page * 100 + i)),
        ),
      ),
    );
    final result = await ExtractionService(
      g,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.users, hasLength(10));
    expect(result.messages, hasLength(300));
    for (final user in result.users) {
      expect(user.count, 30);
    }
    expect(result.messages.first.at, start);
    expect(result.messages.last.at, start.add(const Duration(minutes: 299)));
  });
  test('一括解除は全ページ確認し、対象外メンバーを結果に保持しない', () async {
    final g = GeneratedMembers(5);
    var scanned = 0;
    final result = await ExtractionService(g).removalTargets(
      guild,
      '2',
      bot,
      Cancellation(),
      (_, done, _) => scanned = done,
    );
    expect(result, hasLength(5));
    expect(result.every((m) => m.roles.contains('2')), isTrue);
    expect(scanned, 5000);
    expect(g.requested, 6);
    print(
      'MEMBER_SCAN scanned=$scanned retained=${result.length} pages=${g.requested}',
    );
  });
  test('解除プレビュー途中のエラーは部分結果を公開しない', () async {
    final g = GeneratedMembers(5, failPage: 2);
    await expectLater(
      ExtractionService(
        g,
      ).removalTargets(guild, '2', bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(g.writes, 0);
  });
  test('対象が少なくても解除プレビューの全走査量を制限する', () async {
    final g = GeneratedMembers(101);
    await expectLater(
      ExtractionService(
        g,
      ).removalTargets(guild, '2', bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(g.requested, 101);
    expect(g.writes, 0);
  });
  test('後続ページでロールを失った重複メンバーは対象から除く', () async {
    final g = FakeGateway()
      ..memberPages = [
        [bob, ...List.generate(999, (i) => Member('${100 + i}', 'other'))],
        [Member(bob.id, bob.username), Member('1200', 'last')],
      ];
    final result = await ExtractionService(
      g,
    ).removalTargets(guild, '2', bot, Cancellation(), noProgress);
    expect(result, isEmpty);
  });
}
