import 'package:flutter/material.dart';
import '../../core/tool_module.dart';
import '../../core/tool_activity.dart';
import '../../core/tool_status.dart';
import 'application/kakutei_controller.dart';
import 'domain/models.dart';
import 'domain/operation_summary.dart';
import 'presentation/connection_panel.dart';
import 'presentation/history_panel.dart';
import 'presentation/kakutei_page.dart';
import 'presentation/operation_feedback.dart';

class KakuteiModule implements ToolModule, PagedActivityModule {
  KakuteiModule(this.controller);
  final KakuteiController controller;
  @override
  String get id => 'kakutei';
  @override
  String get title => '確定ロール';
  @override
  String get description => 'Discordの投稿から対象者を確認し、ロールを付与・解除します。';
  @override
  IconData get icon => Icons.people_alt_outlined;
  @override
  Listenable get changes => controller;
  @override
  String get status => controller.status;
  @override
  bool get connected => controller.connected;
  @override
  bool get busy => controller.busy;
  @override
  ToolConnection get connection => ToolConnection(
    service: 'Discord',
    state: controller.connecting || controller.waitingForConnection
        ? ToolConnectionState.connecting
        : controller.demo && controller.connected
        ? ToolConnectionState.sample
        : controller.connected
        ? ToolConnectionState.connected
        : ToolConnectionState.disconnected,
  );
  @override
  ToolFeedback? get feedback {
    final c = controller;
    final message = c.busy
        ? '${c.progress}${c.done > 0 ? ' · ${c.done}${c.total == null ? '件' : ' / ${c.total}'}' : ''}'
        : c.error ?? c.notice;
    if (message == null) return null;
    return ToolFeedback(
      sourceId: id,
      revision: c.feedbackRevision,
      message: message,
      working: c.busy,
      error: !c.busy && c.error != null,
      progress: c.total == null || c.total == 0 ? null : c.done / c.total!,
      dismiss: c.clearMessage,
      cancel: c.busy ? c.cancel : null,
    );
  }

  @override
  int get activityTotal => controller.historyTotal;
  @override
  bool get hasMoreActivities => controller.hasMoreHistory;
  @override
  Future<void> loadMoreActivities() => controller.loadMoreHistory();
  @override
  List<ToolActivity> get activities =>
      [
            if (controller.latestReport != null)
              OperationSummary.fromReport(controller.latestReport!),
            ...controller.history.where(
              (report) => report.id != controller.latestReport?.id,
            ),
          ]
          .map(
            (report) => ToolActivity(
              id: report.id,
              at: report.startedAt,
              action: 'ロールを${report.actionLabel}',
              subject: report.role.name,
              context: report.guild.name,
              sample: controller.demo,
              result:
                  '${report.finishedAt == null ? '未完了 · ' : ''}'
                  '成功 ${report.count(Outcome.success)}人 · '
                  'スキップ ${report.count(Outcome.skipped)}人 · '
                  '失敗 ${report.count(Outcome.failed)}人 · '
                  '未確認 ${report.count(Outcome.uncertain) + report.count(Outcome.inFlight)}人 · '
                  '未処理 ${report.count(Outcome.unprocessed) + report.count(Outcome.pending)}人',
            ),
          )
          .toList();
  @override
  Widget buildPage() => KakuteiPage(controller: controller);
  @override
  Widget buildSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConnectionPanel(controller: controller),
      if (controller.supportsCsvBackup)
        SwitchListTile(
          title: const Text('結果CSVを自動保存'),
          subtitle: const Text('操作終了時に、履歴と同じ保存先へCSVも保存します。'),
          value: controller.autoSaveCsv,
          onChanged: controller.busy ? null : controller.setAutoSaveCsv,
        ),
      if (controller.hasPendingTask && !controller.busy)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('再開待ちの処理があります'),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => controller.resumePending(force: true),
                      child: const Text('再開'),
                    ),
                    TextButton(
                      onPressed: controller.discardPending,
                      child: const Text('取り消す'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  @override
  Widget buildActivityFeedback() => OperationFeedback(controller: controller);
  @override
  Widget buildActivityDetails(String id) =>
      LazyReportDetails(id: id, controller: controller);
  @override
  Future<void> initialize() => controller.initialize();
  @override
  void dispose() => controller.dispose();
}
