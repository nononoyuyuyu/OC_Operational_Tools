/// 各ツールが共通の履歴画面に渡す表示用の要約。詳細と保存形式はツール側が所有する。
class ToolActivity {
  const ToolActivity({
    required this.id,
    required this.at,
    required this.action,
    required this.subject,
    required this.context,
    required this.result,
    this.sample = false,
  });
  final String id;
  final DateTime at;
  final String action;
  final String subject;
  final String context;
  final String result;
  final bool sample;
}
