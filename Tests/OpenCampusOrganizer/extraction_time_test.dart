import 'date_field_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/domain/jst.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'controller_widget_test.dart' as fixtures;
import 'support.dart';

void main() {
  test('終了分の末尾は日付・年・うるう日の境界でも正しく扱う', () {
    for (final (input, next) in [
      ('2025/12/31 23:59', '2026/01/01 00:00'),
      ('2024/02/29 23:59', '2024/03/01 00:00'),
      ('2026/01/01 09:00', '2026/01/01 09:01'),
    ]) {
      final end = parseJstMinuteEnd(input);
      expect(end.add(const Duration(microseconds: 1)), parseJst(next));
      expect(formatJst(end), input);
      expect(end.isUtc, isTrue);
    }
    expect(
      () => parseJstMinuteEnd('2026/02/29 09:00'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => Conditions(
        guildId: '1',
        channelId: '4',
        roleId: '2',
        start: parseJst('2026/01/01 09:01'),
        end: parseJstMinuteEnd('2026/01/01 09:00'),
      ).validate(),
      throwsA(isA<AppFailure>()),
    );
  });
  testWidgets('同じ開始・終了分を入力すると、その分の投稿者を秒・端数まで抽出する', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TimeGateway(parseJst('2026/01/01 09:00'));
    final c = fixtures.controller(gateway);
    await c.connect('fixture-only', remember: false);
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    await restoreDateField(
      tester,
      find.widgetWithText(TextField, '開始日時（JST）'),
      '2026/01/01 09:00',
    );
    await restoreDateField(
      tester,
      find.widgetWithText(TextField, '終了日時（任意）'),
      '2026/01/01 09:00',
    );
    await tester.tap(find.byKey(const ValueKey('extract-users')));
    await tester.pumpAndSettle();
    expect(c.error, isNull);
    expect(c.extraction!.users.map((u) => u.member.id).toSet(), {
      '4001',
      '4002',
      '4003',
    });
    expect(c.extraction!.messages.length, 3);
    expect(gateway.firstBefore, _snowflake(parseJst('2026/01/01 09:01'), 0));
    await restoreDateField(
      tester,
      find.widgetWithText(TextField, '終了日時（任意）'),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('extract-users')));
    await tester.pumpAndSettle();
    expect(c.extraction!.conditions.end, isNull);
    expect(c.extraction!.messages.length, 4, reason: '終了が空欄なら抽出開始時刻まで取得する');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

String _snowflake(DateTime at, int sequence) =>
    ((BigInt.from(at.millisecondsSinceEpoch - 1420070400000) << 22) +
            BigInt.from(sequence))
        .toString();

/// APIと同じbeforeの排他的境界で返し、取得段階の取りこぼしも検出する。
class _TimeGateway extends FakeGateway {
  _TimeGateway(DateTime minute) {
    final offsets = [-1, 0, 1, 59999999, 60000000];
    for (var i = 0; i < offsets.length; i++) {
      final member = Member('${4000 + i}', '投稿者 $i');
      final at = minute.add(Duration(microseconds: offsets[i]));
      people[member.id] = member;
      _messages.add(Message(_snowflake(at, i + 1), '4', member, at));
    }
    _messages.sort((a, b) => BigInt.parse(b.id).compareTo(BigInt.parse(a.id)));
  }
  final _messages = <Message>[];
  String? firstBefore;
  @override
  Future<List<Message>> messages(
    String channelId,
    String? before,
    Cancellation cancel,
  ) async {
    firstBefore ??= before;
    return _messages
        .where(
          (m) => before == null || BigInt.parse(m.id) < BigInt.parse(before),
        )
        .take(100)
        .toList();
  }
}
