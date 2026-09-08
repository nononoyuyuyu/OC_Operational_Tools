import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

List<Message> _page(int first, int length, Member author) =>
    List.generate(length, (i) => Message('${first - i}', '4', author, start));

void main() {
  test('除外Botも走査上限へ数え、部分結果を返さない', () async {
    final gateway = FakeGateway()
      ..messagePages = [_page(300, 100, me), _page(200, 100, me)];
    await expectLater(
      ExtractionService(
        gateway,
        maxScannedMessages: 100,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(gateway.messagePage, 2);
    expect(gateway.memberCalls, 0);
  });

  test('重複排除前の投稿数で走査上限を検査する', () async {
    final gateway = FakeGateway()
      ..messagePages = [
        _page(300, 100, alice),
        [Message('100', '4', alice, start), ..._page(300, 99, alice)],
      ];
    await expectLater(
      ExtractionService(
        gateway,
        maxScannedMessages: 150,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(gateway.memberCalls, 0);
  });

  test('走査上限と同数の最終ページは成功する', () async {
    final gateway = FakeGateway()..messagePages = [_page(300, 99, alice)];
    final result = await ExtractionService(
      gateway,
      maxScannedMessages: 99,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.messages, hasLength(99));
    expect(result.users.single.count, 99);
  });

  test('満杯の境界ページの後に空ページで終端を確認できる', () async {
    final gateway = FakeGateway()..messagePages = [_page(300, 100, alice), []];
    final result = await ExtractionService(
      gateway,
      maxScannedMessages: 100,
      maxMessagePages: 2,
    ).extract(guild, conditions(), bot, Cancellation(), noProgress);
    expect(result.messages, hasLength(100));
    expect(gateway.messagePage, 2);
  });

  test('ページ上限に到達したら次のネットワーク要求を送らない', () async {
    final gateway = FakeGateway()
      ..messagePages = [_page(300, 100, me), _page(200, 100, me)];
    await expectLater(
      ExtractionService(
        gateway,
        maxMessagePages: 1,
      ).extract(guild, conditions(), bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(gateway.messagePage, 1);
    expect(gateway.memberCalls, 0);
  });
}
