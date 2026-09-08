import 'models.dart';

/// 履歴一覧に必要な値だけを保持し、対象者や投稿データは持たない。
class OperationSummary {
  OperationSummary({
    required this.id,
    required this.guild,
    required this.role,
    required this.action,
    required this.startedAt,
    required this.finishedAt,
    required List<int> counts,
  }) : counts = List.unmodifiable(counts);
  factory OperationSummary.fromReport(OperationReport report) =>
      OperationSummary(
        id: report.id,
        guild: report.plan.guild,
        role: report.plan.role,
        action: report.plan.action,
        startedAt: report.startedAt,
        finishedAt: report.finishedAt,
        counts: [for (final outcome in Outcome.values) report.count(outcome)],
      );
  final String id;
  final Guild guild;
  final Role role;
  final RoleAction action;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<int> counts;
  int count(Outcome outcome) => counts[outcome.index];
  String get actionLabel => action == RoleAction.add ? '付与' : '解除';
}

class OperationHistoryPage {
  OperationHistoryPage(List<OperationSummary> items, this.total)
    : items = List.unmodifiable(items);
  final List<OperationSummary> items;
  final int total;
}
