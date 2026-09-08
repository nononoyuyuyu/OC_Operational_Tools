import 'models.dart';

/// ループの終了と、全対象についての正常完了を区別する。
/// 中止・未送信・結果未確認が残る操作を自動終了対象にしない。
extension OperationCompletion on OperationReport {
  bool get completedSuccessfully =>
      finishedAt != null &&
      rows.every(
        (row) =>
            row.outcome == Outcome.success || row.outcome == Outcome.skipped,
      );

  String get completionMessage {
    final unprocessed = count(Outcome.pending) + count(Outcome.unprocessed);
    final uncertain = count(Outcome.inFlight) + count(Outcome.uncertain);
    return '${plan.actionLabel}処理を終了しました。'
        '成功 ${count(Outcome.success)}人・'
        'スキップ ${count(Outcome.skipped)}人・'
        '失敗 ${count(Outcome.failed)}人・'
        '未処理 $unprocessed人・結果未確認 $uncertain人';
  }
}
