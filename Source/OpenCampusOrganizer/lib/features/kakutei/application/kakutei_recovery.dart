part of 'kakutei_controller.dart';

extension KakuteiRecovery on KakuteiController {
  bool get hasPendingTask => pendingTask != null;

  void _checkNewTask() {
    if (!_taskStorageHealthy) {
      throw const AppFailure('再開用の記録を読み取れないため、新しい処理を開始できません。');
    }
    if (pendingTask != null) {
      throw const AppFailure('再開待ちの処理があります。設定から再開するか取り消してください。');
    }
    if (bot == null || selectedGuild == null) {
      throw const AppFailure('Discordに接続してください。');
    }
  }

  PendingTask _task(String kind, Map<String, dynamic> payload) => PendingTask(
    id: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
    botId: bot!.id,
    kind: kind,
    payload: payload,
  );

  Future<void> _startExtractionTask(Conditions conditions) =>
      _run((cancel) async {
        _checkNewTask();
        conditions.validate();
        if (conditions.guildId != selectedGuild!.id ||
            conditions.channelId != channelId ||
            conditions.roleId != roleId) {
          throw const AppFailure('選択中の条件を確認してください。');
        }
        invalidate();
        await _persistNewTask(
          _task('extract', encodeConditions(conditions)),
          cancel,
        );
      });

  Future<void> _startRemovalPreviewTask() => _run((cancel) async {
    _checkNewTask();
    if (selectedRole == null) throw const AppFailure('対象ロールを選択してください。');
    removalPlan = null;
    _removalRevision = null;
    await _persistNewTask(
      _task('preview', {'guildId': selectedGuild!.id, 'roleId': roleId}),
      cancel,
    );
  });

  Future<void> _startOperationTask(RolePlan plan, bool acknowledged) =>
      _run((cancel) async {
        _checkNewTask();
        if (plan.fingerprint != _fingerprint ||
            DateTime.now().toUtc().difference(plan.createdAt) >
                const Duration(minutes: 10) ||
            (plan.action == RoleAction.add
                    ? _extractionRevision
                    : _removalRevision) !=
                _revision) {
          throw const AppFailure('対象者を再確認してください。');
        }
        if (plan.action == RoleAction.remove && !acknowledged) {
          throw const AppFailure('解除の対象と注意事項を確認し、チェックを入れてください。');
        }
        final task = _task('operation', {
          'plan': encodePlan(plan),
          'acknowledged': acknowledged,
        });
        // 再開先の履歴を先に確定する。ここまでではDiscordへ更新を送らない。
        await journal.save(
          OperationReport(
            id: task.id,
            plan: plan,
            rows: plan.targets
                .map((m) => OperationRow(m, Outcome.pending, ''))
                .toList(),
            startedAt: DateTime.now().toUtc(),
          ),
        );
        await _persistNewTask(task, cancel);
      });

  Future<void> _persistNewTask(PendingTask task, Cancellation cancel) async {
    await taskStore!.save(task);
    pendingTask = task;
    await _performPending(task, cancel);
  }

  Future<void> resumePending({bool force = false}) async {
    if (busy) await _runCompletion?.future;
    final task = pendingTask;
    if (task == null || busy || _disposed || demo || (task.blocked && !force)) {
      return;
    }
    await _run((cancel) => _performPending(task, cancel));
  }

  Future<void> suspendTasks() async {
    _cancel?.suspend();
    await _runCompletion?.future;
    await pendingSettings;
  }

  Future<void> discardPending() async {
    if (busy) {
      cancel();
      return;
    }
    final task = pendingTask;
    if (task == null) return;
    await _run((_) async {
      await _recordCancellation(task);
      await taskStore!.save(null);
      pendingTask = null;
      notice = '再開待ちの処理を取り消しました。';
    });
  }

  Future<void> _recordCancellation(PendingTask task) async {
    if (task.kind != 'operation') return;
    final report = await _readJournalReport(task.id, journal);
    if (report == null || report.finishedAt != null) return;
    await journal.save(
      OperationReport(
        id: report.id,
        plan: report.plan,
        startedAt: report.startedAt,
        finishedAt: DateTime.now().toUtc(),
        rows: report.rows
            .map(
              (r) =>
                  r.outcome == Outcome.pending ||
                      r.outcome == Outcome.unprocessed
                  ? OperationRow(
                      r.member,
                      Outcome.unprocessed,
                      '利用者が処理を中止しました。',
                    )
                  : r,
            )
            .toList(),
      ),
    );
    await _reloadHistory();
    latestReport = await _readJournalReport(task.id, journal);
  }

  Future<void> _prepareTask(PendingTask task, Cancellation cancel) async {
    if (bot == null) {
      final token = await credentials.read();
      if (token == null) throw const AppFailure('処理を再開するには、同じBotで接続してください。');
      await _connect(token, cancel, remember: true);
    }
    if (bot!.id != task.botId) {
      throw const AppFailure('処理を承認したBotと接続中のBotが異なります。元のBotで接続してください。');
    }
    final payload = task.kind == 'operation'
        ? task.payload['plan'] as Map<String, dynamic>
        : task.payload;
    final guildId = payload['guildId'] as String;
    final guild = guilds.where((g) => g.id == guildId).firstOrNull;
    if (guild == null) throw const AppFailure('処理対象のサーバーにアクセスできません。');
    guildContext = await _gateway.context(guild, cancel);
    roleId = payload['roleId'] as String;
    if (task.kind == 'extract') channelId = payload['channelId'] as String;
  }

  Future<void> _attemptTask(PendingTask task, Cancellation cancel) async {
    await _prepareTask(task, cancel);
    cancel.check();
    waitingForConnection = false;
    switch (task.kind) {
      case 'extract':
        final conditions = decodeConditions(task.payload);
        // 保存タスクを実行条件の正とし、画面にも同じ条件を表示する。
        // 永続設定への保存可否は従来の「保存する」選択に従う。
        settings = settings
            .withInput(
              ExtractionInput(
                start: formatJst(conditions.start),
                end: conditions.end == null ? '' : formatJst(conditions.end!),
                minimum: conditions.minimum.toString(),
                excludeBots: conditions.excludeBots,
                includeContent: conditions.includeContent,
                includeAttachments: conditions.includeAttachments,
              ),
            )
            .select(
              conditions.guildId,
              conditions.channelId,
              conditions.roleId,
            );
        settingsRevision++;
        invalidate();
        _saveSettings();
        extraction = await ExtractionService(
          _gateway,
        ).extract(selectedGuild!, conditions, bot!, cancel, _progress);
        _extractionRevision = _revision;
        notice = '${extraction!.users.length}人の対象者を確認しました。';
      case 'preview':
        final targets = await ExtractionService(_gateway).removalTargets(
          selectedGuild!,
          roleId!,
          bot!,
          cancel,
          _progress,
          verifiedContext: guildContext,
        );
        removalPlan = RolePlan(
          guild: selectedGuild!,
          role: selectedRole!,
          action: RoleAction.remove,
          targets: targets,
          fingerprint: _fingerprint,
          createdAt: DateTime.now().toUtc(),
        );
        _removalRevision = _revision;
        notice = '${targets.length}人の解除対象を確認しました。';
      case 'operation':
        final plan = decodePlan(task.payload['plan'] as Map<String, dynamic>);
        final saved = await _readJournalReport(task.id, journal);
        if (saved == null) {
          throw const AppFailure('再開先の操作履歴が見つかりません。Discordの状態を確認してください。');
        }
        latestReport = await OperationService(_gateway, journal).execute(
          plan,
          plan.fingerprint,
          cancel,
          _progress,
          (report) {
            latestReport = report;
            _notify();
          },
          removalAcknowledged: task.payload['acknowledged'] == true,
          operationId: task.id,
          resume: saved,
          resumable: true,
        );
        await _reloadHistory();
        _setOperationFeedback(latestReport!, cancel);
        invalidate();
      default:
        throw const AppFailure('この種類の処理は再開できません。');
    }
  }

  Future<void> _performPending(PendingTask task, Cancellation cancel) async {
    var finished = false;
    var failed = false;
    var attempt = 0;
    try {
      pendingTask = task.withBlocked(false);
      await taskStore!.save(pendingTask);
      await taskHost.start(
        task.id,
        task.kind == 'operation' ? '確定ロールの操作' : '対象者の確認',
      );
      while (true) {
        cancel.check();
        try {
          await _attemptTask(task, cancel);
          cancel.check();
          // 非再試行エラーの終了記録は片付けるが、正常完了とは扱わない。
          failed =
              task.kind == 'operation' &&
              latestReport?.completedSuccessfully != true;
          await taskStore!.save(null);
          pendingTask = null;
          finished = true;
          break;
        } on AppFailure catch (failure) {
          if (!failure.retryable) rethrow;
          waitingForConnection = true;
          pendingTask = task.withBlocked(false);
          await taskStore!.save(pendingTask);
          final seconds = [2, 5, 10, 30][attempt.clamp(0, 3)];
          attempt++;
          final delay = failure.retryAfter ?? Duration(seconds: seconds);
          _progress('接続復帰を待っています', done, total);
          await (retryWait?.call(delay, cancel) ?? cancel.wait(delay));
        }
      }
    } on TaskSuspended {
      notice = '処理を保存しました。次回起動時に再開します。';
    } on Cancelled {
      await _recordCancellation(task);
      await taskStore!.save(null);
      pendingTask = null;
      notice = '処理を中止しました。';
    } catch (failure) {
      failed = true;
      error = failureMessage(failure);
      pendingTask = task.withBlocked(true);
      await taskStore!.save(pendingTask);
    } finally {
      waitingForConnection = false;
      await taskHost.finish(
        task.id,
        error ?? notice ?? '処理を停止しました。',
        closeEligible: finished && !failed && task.kind == 'operation',
        failed: failed,
      );
    }
  }
}
