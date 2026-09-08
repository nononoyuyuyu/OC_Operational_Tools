import 'dart:convert';
import 'dart:typed_data';
import 'jst.dart';
import 'models.dart';

String csvCell(Object? value, {bool identifier = false}) {
  var text = value?.toString() ?? '';
  // 先頭の不可視文字・空白の後にある数式も無害化する。IDはExcelの丸めを防ぐ。
  final probe = text.replaceFirst(
    RegExp(r'^[\s\u0000-\u0020\u007f-\u009f\u200b-\u200f\ufeff]+'),
    '',
  );
  if (identifier ||
      RegExp(r'^[=+@\-＝＋＠－]').hasMatch(probe) ||
      RegExp(r'^[\t\r\n]').hasMatch(text)) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

Uint8List _encode(List<String> headers, Iterable<List<String>> rows) {
  // Keep only one text batch (plus the current row), not every row and a
  // second full CSV string. The final byte buffer is required by ExportSink.
  final bytes = BytesBuilder(copy: false)..add(const [0xef, 0xbb, 0xbf]);
  final batch = StringBuffer();
  void flush() {
    if (batch.isEmpty) return;
    bytes.add(utf8.encode(batch.toString()));
    batch.clear();
  }

  void line(String value) {
    batch.write(value);
    batch.write('\r\n');
    if (batch.length >= 32768) flush();
  }

  line(headers.map((v) => csvCell(v)).join(','));
  for (final row in rows) {
    line(row.join(','));
  }
  flush();
  return bytes.takeBytes();
}

List<String> _member(Member m) => [
  csvCell(m.id, identifier: true),
  csvCell(m.displayName),
  csvCell(m.nickname),
  csvCell(m.username),
  csvCell(m.globalName),
];
const _memberHeaders = [
  'user_id',
  'display_name',
  'server_nickname',
  'username',
  'global_name',
];

Uint8List usersCsv(Extraction extraction) => _encode(
  [
    ..._memberHeaders,
    'message_count',
    'first_message_at_jst',
    'last_message_at_jst',
    'has_target_role',
    'is_member',
  ],
  extraction.users.map(
    (u) => [
      ..._member(u.member),
      csvCell(u.count),
      csvCell(formatJst(u.first, seconds: true)),
      csvCell(formatJst(u.last, seconds: true)),
      csvCell(u.hasRole),
      csvCell(u.member.present),
    ],
  ),
);

Uint8List messagesCsv(Extraction extraction) => _encode(
  [
    'message_id',
    ..._memberHeaders,
    'created_at_jst',
    'content',
    'attachment_urls',
    'jump_url',
  ],
  extraction.messages.map(
    (m) => [
      csvCell(m.id, identifier: true),
      ..._member(m.author),
      csvCell(formatJst(m.at, seconds: true)),
      csvCell(extraction.conditions.includeContent ? m.content : ''),
      csvCell(
        extraction.conditions.includeAttachments ? m.attachments.join(' ') : '',
      ),
      csvCell(
        'https://discord.com/channels/${extraction.conditions.guildId}/${m.channelId}/${m.id}',
      ),
    ],
  ),
);

Uint8List operationsCsv(OperationReport report) => _encode(
  [
    'operation_id',
    'guild_id',
    'role_id',
    'role_name',
    ..._memberHeaders,
    'action',
    'result',
    'reason',
  ],
  report.rows.map(
    (r) => [
      csvCell(report.id, identifier: true),
      csvCell(report.plan.guild.id, identifier: true),
      csvCell(report.plan.role.id, identifier: true),
      csvCell(report.plan.role.name),
      ..._member(r.member),
      csvCell(report.plan.action.name),
      csvCell(outcomeLabel(r.outcome)),
      csvCell(r.reason),
    ],
  ),
);
