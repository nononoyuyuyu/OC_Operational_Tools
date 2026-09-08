import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/recovery_payload.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

Conditions onlyUsers({int minimum = 2}) => Conditions(
  guildId: '1',
  channelId: '4',
  roleId: '2',
  start: start,
  minimum: minimum,
  retainMessages: false,
);

void main() {
  test('投稿非保持でも集計を維持し、下限未満のメンバーを照会しない', () async {
    final gateway = FakeGateway()
      ..messagePages = [
        [
          Message('103', '4', alice, start.add(const Duration(minutes: 2))),
          Message('102', '4', bob, start),
          Message('101', '4', alice, start),
        ],
      ];
    final result = await ExtractionService(
      gateway,
    ).extract(guild, onlyUsers(), bot, Cancellation(), noProgress);
    expect(result.messages, isEmpty);
    expect(result.messageCount, 3);
    expect(result.users.single.member.id, alice.id);
    expect(result.users.single.count, 2);
    expect(result.users.single.first, start);
    expect(result.users.single.last, start.add(const Duration(minutes: 2)));
    expect(gateway.memberCalls, 1);
  });

  test('全員が下限未満ならメンバーを照会せず、走査件数だけを残す', () async {
    final gateway = FakeGateway()
      ..messagePages = [
        [Message('100', '4', alice, start)],
      ];
    final result = await ExtractionService(
      gateway,
    ).extract(guild, onlyUsers(), bot, Cancellation(), noProgress);
    expect(result.users, isEmpty);
    expect(result.messages, isEmpty);
    expect(result.messageCount, 1);
    expect(gateway.memberCalls, 0);
  });

  test('投稿を保持しなくても除外前の走査上限を適用する', () async {
    final gateway = FakeGateway()
      ..messagePages = [
        List.generate(100, (i) => Message('${300 - i}', '4', me, start)),
        [Message('100', '4', alice, start)],
      ];
    await expectLater(
      ExtractionService(
        gateway,
        maxScannedMessages: 100,
      ).extract(guild, onlyUsers(), bot, Cancellation(), noProgress),
      throwsA(isA<AppFailure>()),
    );
    expect(gateway.memberCalls, 0);
  });

  test('保存した非保持条件を再開し、旧形式は投稿保持を維持する', () {
    final payload = encodeConditions(onlyUsers());
    expect(decodeConditions(payload).retainMessages, isFalse);
    payload.remove('retainMessages');
    expect(decodeConditions(payload).retainMessages, isTrue);
    expect(conditions().retainMessages, isTrue);
  });
}
