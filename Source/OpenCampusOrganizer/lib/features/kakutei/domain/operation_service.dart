import '../../../core/failure.dart';
import 'gateway.dart';
import 'models.dart';
import 'operation_rows.dart';
import 'permissions.dart';

class OperationService {
  const OperationService(this.gateway, this.journal, {this.now});
  final DiscordGateway gateway;
  final OperationJournal journal;
  final DateTime Function()? now;
  DateTime _now() => now?.call() ?? DateTime.now();

  Future<OperationReport> execute(
    RolePlan plan,
    String currentFingerprint,
    Cancellation cancel,
    Progress progress,
    void Function(OperationReport) changed, {
    bool removalAcknowledged = false,
    String? operationId,
    OperationReport? resume,
    bool resumable = false,
  }) async {
    if (plan.fingerprint != currentFingerprint ||
        (resume == null &&
            _now().difference(plan.createdAt) > const Duration(minutes: 10))) {
      throw const AppFailure('確認後に条件が変わったか、10分が経過しました。対象者を再確認してください。');
    }
    if (plan.action == RoleAction.remove && !removalAcknowledged) {
      throw const AppFailure('解除の対象と注意事項を確認し、チェックを入れてください。');
    }
    if (plan.targets.map((m) => m.id).toSet().length != plan.targets.length) {
      throw const AppFailure('対象者が重複しています。再確認してください。');
    }
    if (resume != null &&
        (resume.id != operationId ||
            resume.plan.guild.id != plan.guild.id ||
            resume.plan.role.id != plan.role.id ||
            resume.plan.action != plan.action ||
            resume.rows.length != plan.targets.length ||
            List.generate(
              plan.targets.length,
              (i) => resume.rows[i].member.id != plan.targets[i].id,
            ).any((v) => v))) {
      throw const AppFailure('再開する対象者と保存記録が一致しません。');
    }
    if (resume?.finishedAt != null) return resume!;
    var checkedAt = _now();
    await _checkRole(plan, cancel);
    var checkedTargets = 0;
    Future<void> ensureRole() async {
      // チャンネル一覧を毎人取り直さず、5秒または20人ごとに権限を再照合する。
      // 個々の更新権限はDiscord側でも検証され、拒否された時点で後続を止める。
      if (_now().difference(checkedAt) >= const Duration(seconds: 5) ||
          checkedTargets >= 20) {
        checkedAt = _now();
        await _checkRole(plan, cancel);
        checkedTargets = 0;
      }
    }

    final started = resume?.startedAt ?? DateTime.now().toUtc();
    final id = operationId ?? started.microsecondsSinceEpoch.toString();
    var rows = OperationRows(
      resume?.rows ??
          plan.targets.map((m) => OperationRow(m, Outcome.pending, '')),
    );
    void update(int index, OperationRow row) {
      rows = rows.updated(index, row);
    }

    OperationReport report({bool finished = false}) => OperationReport(
      id: id,
      plan: plan,
      rows: rows,
      startedAt: started,
      finishedAt: finished ? DateTime.now().toUtc() : null,
    );
    Future<void> persist({bool finished = false}) async {
      final value = report(finished: finished);
      changed(value);
      try {
        await journal.save(value);
      } catch (_) {
        throw const AppFailure(
          '操作記録を保存できないため処理を停止しました。結果未確認の対象はDiscordで確認してください。',
        );
      }
    }

    await persist();
    var stopReason = '';
    for (var i = 0; i < rows.length; i++) {
      if (cancel.isSuspended && !cancel.isCancelled) throw TaskSuspended();
      if ({
        Outcome.success,
        Outcome.skipped,
        Outcome.failed,
      }.contains(rows[i].outcome)) {
        continue;
      }
      final target = rows[i].member;
      if (cancel.isCancelled || stopReason.isNotEmpty) {
        update(
          i,
          OperationRow(
            target,
            Outcome.unprocessed,
            stopReason.isEmpty ? '利用者が処理を中止しました。' : stopReason,
          ),
        );
        continue;
      }
      var dispatched = false;
      try {
        final member = await gateway.member(plan.guild.id, target.id, cancel);
        cancel.check();
        await ensureRole();
        if (member == null) {
          update(i, OperationRow(target, Outcome.skipped, 'サーバーから退出済みです。'));
        } else if (member.roles.contains(plan.role.id) ==
            (plan.action == RoleAction.add)) {
          update(
            i,
            OperationRow(
              target,
              Outcome.skipped,
              plan.action == RoleAction.add ? '既にロールを持っています。' : '既にロールがありません。',
            ),
          );
        } else {
          update(i, OperationRow(member, Outcome.inFlight, '送信後の結果を確認中です。'));
          await persist();
          await ensureRole();
          dispatched = true;
          await gateway.setRole(
            plan.guild.id,
            target.id,
            plan.role.id,
            plan.action,
            cancel,
          );
          update(i, OperationRow(member, Outcome.success, ''));
        }
      } on Cancelled {
        update(i, OperationRow(target, Outcome.unprocessed, '利用者が処理を中止しました。'));
      } on TaskSuspended {
        rethrow;
      } on AppFailure catch (error) {
        // 記録失敗は続行しない。直前の記録がinFlightなら再起動時にも未確認となる。
        if (error.message.startsWith('操作記録を保存できない')) rethrow;
        if (resumable && error.retryable) {
          update(
            i,
            OperationRow(
              target,
              dispatched ? Outcome.uncertain : Outcome.pending,
              dispatched ? '接続復帰後にDiscordの状態を確認します。' : '接続復帰を待っています。',
            ),
          );
          await persist();
          rethrow;
        }
        update(
          i,
          OperationRow(
            target,
            dispatched && error.uncertain ? Outcome.uncertain : Outcome.failed,
            error.message,
          ),
        );
        stopReason = '直前の処理で問題が発生したため停止しました。';
      } catch (_) {
        update(
          i,
          OperationRow(
            target,
            dispatched ? Outcome.uncertain : Outcome.failed,
            '結果を確認できません。Discordの状態を確認してください。',
          ),
        );
        stopReason = '直前の処理で問題が発生したため停止しました。';
      }
      checkedTargets++;
      await persist();
      progress('ロールを${plan.actionLabel}中', i + 1, rows.length);
    }
    await persist(finished: true);
    return report(finished: true);
  }

  Future<void> _checkRole(RolePlan plan, Cancellation cancel) async {
    final context = await gateway.context(
      plan.guild,
      cancel,
      includeChannels: false,
    );
    requireManageable(context, plan.role.id);
    final current = context.role(plan.role.id);
    if (current.name != plan.role.name ||
        current.permissions != plan.role.permissions ||
        current.position != plan.role.position ||
        current.managed != plan.role.managed) {
      throw const AppFailure('対象ロールの設定が変更されました。対象者を再確認してください。');
    }
  }
}
