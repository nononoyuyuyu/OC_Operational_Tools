import '../../../core/failure.dart';

DateTime jstFields(DateTime utc) => utc.toUtc().add(const Duration(hours: 9));
String _two(int n) => n.toString().padLeft(2, '0');
String formatJst(DateTime utc, {bool seconds = false}) {
  final d = jstFields(utc);
  return '${d.year}/${_two(d.month)}/${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}${seconds ? ':${_two(d.second)}' : ''}';
}

DateTime parseJst(String input) {
  final m = RegExp(
    r'^(\d{4})[/-](\d{2})[/-](\d{2}) (\d{2}):(\d{2})$',
  ).firstMatch(input.trim());
  if (m == null) throw const AppFailure('日時は「2026/09/07 09:00」の形式で入力してください。');
  final n = List.generate(5, (i) => int.parse(m.group(i + 1)!));
  final value = DateTime.utc(n[0], n[1], n[2], n[3], n[4]);
  if (n[0] < 2015 ||
      n[0] > 2100 ||
      value.year != n[0] ||
      value.month != n[1] ||
      value.day != n[2] ||
      value.hour != n[3] ||
      value.minute != n[4]) {
    throw const AppFailure('実在する日時を入力してください（2015〜2100年）。');
  }
  return value.subtract(const Duration(hours: 9));
}

/// 分単位の終了入力は、その分の投稿を秒・小数秒まで含める。
/// 業務モデルのendは引き続き「含む最後の時刻」を表す。
DateTime parseJstMinuteEnd(String input) => parseJst(
  input,
).add(const Duration(minutes: 1)).subtract(const Duration(microseconds: 1));
