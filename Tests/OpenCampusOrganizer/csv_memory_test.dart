import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/features/kakutei/domain/csv.dart';
import 'package:open_campus_organizer/features/kakutei/domain/jst.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import '../../Source/OpenCampusOrganizer/tool/csv_benchmark.dart' as reference;
import 'support.dart';

List<String> memberCells(Member member) => [
  csvCell(member.id, identifier: true),
  csvCell(member.displayName),
  csvCell(member.nickname),
  csvCell(member.username),
  csvCell(member.globalName),
];
const memberHeaders = [
  'user_id',
  'display_name',
  'server_nickname',
  'username',
  'global_name',
];

void main() {
  for (final count in [0, 1, 511, 8000]) {
    test('操作CSV $count行のBOM・全バイトが旧実装と一致する', () {
      final report = reference.fixtureReport(count);
      expect(operationsCsv(report), reference.legacyOperationsCsv(report));
    });
  }
  test('投稿CSVの日本語・絵文字・引用符・改行・数式対策を維持する', () {
    final person = Member('10', '=SUM(1)', nickname: '　＝式\n"😀"');
    final messages = List.generate(
      600,
      (i) => Message(
        '${1000 + i}',
        '4',
        person,
        start,
        content: '\u200B=1+1\r\n引用"符" 😀',
        attachments: ['https://example.invalid/fixture'],
      ),
    );
    for (final include in [false, true]) {
      final result = Extraction(
        conditions(content: include, attachments: include),
        messages,
        const [],
        excludedBots: 0,
        at: start,
      );
      final expected = reference.legacyEncode(
        [
          'message_id',
          ...memberHeaders,
          'created_at_jst',
          'content',
          'attachment_urls',
          'jump_url',
        ],
        messages.map(
          (m) => [
            csvCell(m.id, identifier: true),
            ...memberCells(m.author),
            csvCell(formatJst(m.at, seconds: true)),
            csvCell(include ? m.content : ''),
            csvCell(include ? m.attachments.join(' ') : ''),
            csvCell('https://discord.com/channels/1/${m.channelId}/${m.id}'),
          ],
        ),
      );
      expect(messagesCsv(result), expected);
    }
  });
  test('対象者CSVの空データと日時・真偽値の表現を維持する', () {
    for (final users in [
      <Activity>[],
      [Activity(alice, 2, start, start, false)],
    ]) {
      final result = Extraction(
        conditions(),
        const [],
        users,
        excludedBots: 0,
        at: start,
      );
      final expected = reference.legacyEncode(
        [
          ...memberHeaders,
          'message_count',
          'first_message_at_jst',
          'last_message_at_jst',
          'has_target_role',
          'is_member',
        ],
        users.map(
          (u) => [
            ...memberCells(u.member),
            csvCell(u.count),
            csvCell(formatJst(u.first, seconds: true)),
            csvCell(formatJst(u.last, seconds: true)),
            csvCell(u.hasRole),
            csvCell(u.member.present),
          ],
        ),
      );
      expect(usersCsv(result), expected);
    }
  });
}
