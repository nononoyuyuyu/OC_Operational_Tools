import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/failure.dart';
import '../../../core/pending_task.dart';
import '../../../core/task_host.dart';
import '../../../core/ports.dart';
import '../../../core/platform/memory_store.dart';
import '../data/demo_gateway.dart';
import '../data/operation_journal.dart';
import '../data/saved_settings.dart';
import '../data/recovery_payload.dart';
import '../domain/csv.dart';
import '../domain/extraction_service.dart';
import '../domain/gateway.dart';
import '../domain/jst.dart';
import '../domain/models.dart';
import '../domain/operation_completion.dart';
import '../domain/operation_service.dart';
import '../domain/operation_summary.dart';
import '../domain/permissions.dart';
part 'kakutei_recovery.dart';

class KakuteiController extends ChangeNotifier {
  KakuteiController({
    required DiscordGateway gateway,
    required this.credentials,
    required this.journal,
    required this.exports,
    this.settingsStore,
    this.taskStore,
    this.taskHost = const NoopTaskHost(),
    this.retryWait,
    this.demoOnly = false,
  }) : _realGateway = gateway,
       _gateway = gateway;
  final DiscordGateway _realGateway;
  DiscordGateway _gateway;
  final CredentialStore credentials;
  final OperationJournal journal;
  final ExportSink exports;
  final KakuteiSettingsStore? settingsStore;
  final PendingTaskStore? taskStore;
  final TaskHost taskHost;
  final Future<void> Function(Duration, Cancellation)? retryWait;
  PendingTask? pendingTask;
  bool waitingForConnection = false;
  bool _taskStorageHealthy = true;
  Completer<void>? _runCompletion;
  String? _ephemeralId;
  SavedKakuteiSettings settings = const SavedKakuteiSettings();
  int settingsRevision = 0;
  bool _rememberSettings = false;
  bool _settingsReadFailed = false, _restoredSettings = false;
  int _settingsSession = 0;
  Future<void> pendingSettings = Future.value();
  final bool demoOnly;
  final _demoJournal = StoredOperationJournal(MemoryStore());
  Cancellation? _cancel;
  bool _disposed = false;
  bool busy = false;
  bool connecting = false;
  int feedbackRevision = 0;
  bool initialized = false;
  bool demo = false;
  String? error;
  String? notice;
  String progress = '';
  int done = 0;
  int? total;
  BotIdentity? bot;
  List<Guild> guilds = const [];
  GuildContext? guildContext;
  String? channelId;
  String? roleId;
  Extraction? extraction;
  RolePlan? removalPlan;
  OperationReport? latestReport;
  List<OperationSummary> history = const [];
  int historyTotal = 0, _historyEpoch = 0;
  bool historyLoading = false;
  bool get hasMoreHistory => history.length < historyTotal;
  bool savedCredential = false;
  int _revision = 0;
  int? _extractionRevision;
  int? _removalRevision;
  bool get connected => bot != null;
  String get status => demo
      ? 'サンプル'
      : connected
      ? '接続済み'
      : '未接続';
  Guild? get selectedGuild => guildContext?.guild;
  Role? get selectedRole => roleId == null
      ? null
      : guildContext?.roles.where((r) => r.id == roleId).firstOrNull;
  Channel? get selectedChannel => channelId == null
      ? null
      : guildContext?.channels.where((c) => c.id == channelId).firstOrNull;
  List<Channel> get readableChannels => guildContext == null
      ? []
      : guildContext!.channels
            .where(
              (c) => hasPermission(
                channelPermissions(guildContext!, c),
                viewChannel,
              ),
            )
            .toList();
  OperationJournal get _journal => demo ? _demoJournal : journal;
  bool get supportsCsvBackup => _journal is IndexedOperationJournal;
  bool get autoSaveCsv =>
      _journal is IndexedOperationJournal &&
      (_journal as IndexedOperationJournal).autoSaveCsv;
  Future<void> setAutoSaveCsv(bool enabled) => _run((_) async {
    final source = _journal;
    if (source is IndexedOperationJournal) await source.setAutoSaveCsv(enabled);
  });

  Future<OperationHistoryPage> _historyPage(
    OperationJournal source,
    int offset,
  ) async {
    if (source is IndexedOperationJournal) {
      return source.summaries(offset: offset);
    }
    final reports = await source.load();
    return OperationHistoryPage(
      reports.skip(offset).take(30).map(OperationSummary.fromReport).toList(),
      reports.length,
    );
  }

  Future<void> _reloadHistory() async {
    final epoch = ++_historyEpoch;
    final source = _journal;
    historyLoading = true;
    try {
      final page = await _historyPage(source, 0);
      if (!_disposed && epoch == _historyEpoch && identical(source, _journal)) {
        history = page.items;
        historyTotal = page.total;
      }
    } finally {
      if (epoch == _historyEpoch) historyLoading = false;
    }
  }

  Future<void> loadMoreHistory() async {
    if (historyLoading || !hasMoreHistory || _disposed) return;
    final epoch = _historyEpoch;
    final source = _journal;
    historyLoading = true;
    _notify();
    try {
      final page = await _historyPage(source, history.length);
      if (!_disposed && epoch == _historyEpoch && identical(source, _journal)) {
        history = List.unmodifiable([...history, ...page.items]);
        historyTotal = page.total;
      }
    } catch (e) {
      if (epoch == _historyEpoch) showError(failureMessage(e));
    } finally {
      if (epoch == _historyEpoch) historyLoading = false;
      _notify();
    }
  }

  Future<OperationReport?> _readJournalReport(
    String id,
    OperationJournal source,
  ) async => source is IndexedOperationJournal
      ? source.find(id)
      : (await source.load()).where((report) => report.id == id).firstOrNull;

  Future<OperationReport?> loadReport(String id) async =>
      latestReport?.id == id ? latestReport : _readJournalReport(id, _journal);
  String get _fingerprint =>
      '$_revision|${selectedGuild?.id}|$channelId|$roleId|${demo ? 'demo' : 'live'}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(
    Future<void> Function(Cancellation) action, {
    String? taskTitle,
    bool closeEligible = false,
  }) async {
    if (busy || _disposed) return;
    busy = true;
    final completion = Completer<void>();
    _runCompletion = completion;
    feedbackRevision++;
    error = null;
    notice = null;
    done = 0;
    total = null;
    progress = '準備中';
    final cancel = Cancellation();
    _cancel = cancel;
    _notify();
    try {
      if (taskTitle != null) {
        _ephemeralId = 'sample_${DateTime.now().microsecondsSinceEpoch}';
        await taskHost.start(_ephemeralId!, taskTitle);
      }
      await action(cancel);
    } on TaskSuspended {
      notice = '処理を停止しました。';
    } catch (e) {
      error = failureMessage(e);
    } finally {
      if (_ephemeralId != null) {
        try {
          await taskHost.finish(
            _ephemeralId!,
            error ?? notice ?? '処理を停止しました。',
            closeEligible:
                closeEligible &&
                error == null &&
                !cancel.isSuspended &&
                !cancel.isCancelled,
            failed: error != null,
          );
        } catch (_) {
          error = '処理結果の通知を表示できませんでした。';
        }
        _ephemeralId = null;
      }
      busy = false;
      _cancel = null;
      completion.complete();
      _runCompletion = null;
      _notify();
    }
  }

  void _progress(String text, int done, int? total) {
    progress = text;
    this.done = done;
    this.total = total;
    if (pendingTask != null) {
      taskHost.update(pendingTask!.id, text, done, total);
    } else if (_ephemeralId != null) {
      taskHost.update(_ephemeralId!, text, done, total);
    }
    _notify();
  }

  void cancel() {
    _cancel?.cancel();
    progress = '現在の処理を確認して停止中';
    _notify();
  }

  void clearMessage() {
    error = null;
    notice = null;
    _notify();
  }

  void showNotice(String message) {
    if (busy || _disposed) return;
    feedbackRevision++;
    error = null;
    notice = message;
    _notify();
  }

  void showError(String message) {
    if (busy || _disposed) return;
    feedbackRevision++;
    notice = null;
    error = message;
    _notify();
  }

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    if (demoOnly) {
      await startDemo();
      return;
    }
    await _run((cancel) async {
      try {
        pendingTask = await taskStore?.load();
        await _reloadHistory();
      } catch (_) {
        _taskStorageHealthy = false;
        rethrow;
      }
      final token = await credentials.read();
      savedCredential = token != null;
      if (token != null) {
        await _connect(token, cancel, remember: true);
        _saveSettings(initial: true);
      }
    });
    await resumePending();
  }

  Future<void> _connect(
    String token,
    Cancellation cancel, {
    bool remember = false,
  }) async {
    _rememberSettings = false;
    _settingsReadFailed = false;
    _restoredSettings = false;
    _clearConnection();
    connecting = true;
    _notify();
    try {
      final identity = await _gateway.connect(token, cancel);
      final available = await _gateway.guilds(cancel);
      SavedKakuteiSettings? restored;
      if (remember && !demo) {
        try {
          restored = await settingsStore?.load(identity.id);
        } catch (_) {
          _settingsReadFailed = true;
          error = '前回の設定を読み込めませんでした。';
        }
      }
      settings = restored ?? const SavedKakuteiSettings();
      _restoredSettings = restored != null;
      if (settings.input.start == null) {
        final input = settings.input;
        settings = settings.withInput(
          ExtractionInput(
            start: formatJst(DateTime.now().subtract(const Duration(days: 7))),
            end: input.end,
            minimum: input.minimum,
            excludeBots: input.excludeBots,
            includeContent: input.includeContent,
            includeAttachments: input.includeAttachments,
          ),
        );
      }
      settingsRevision++;
      final chosen = settings.guildId == null
          ? available.firstOrNull
          : available
                .where((guild) => guild.id == settings.guildId)
                .firstOrNull;
      GuildContext? context;
      if (chosen != null) {
        context = await _gateway.context(chosen, cancel);
      }
      cancel.check();
      bot = identity;
      guilds = List.unmodifiable(available);
      guildContext = context;
      _selectDefaults(selection: settings.selections[chosen?.id]);
      _rememberSettings = remember;
      if (settings.guildId != null && chosen == null && available.isNotEmpty) {
        notice = '前回のサーバーが見つかりません。サーバーを選択してください。';
      }
      if (available.isEmpty) notice = 'Botが参加しているサーバーがありません。招待URLを使って追加してください。';
    } catch (_) {
      _gateway.disconnect();
      _clearConnection();
      rethrow;
    } finally {
      connecting = false;
    }
  }

  Future<void> connect(String token, {required bool remember}) =>
      _run((cancel) async {
        if (demoOnly) throw const AppFailure('この画面はサンプル専用です。');
        demo = false;
        _gateway = _realGateway;
        await _connect(token, cancel, remember: remember);
        await _reloadHistory();
        if (remember) {
          await credentials.save(token.trim());
          savedCredential = true;
          _saveSettings(initial: true);
        } else {
          await credentials.delete();
          savedCredential = false;
        }
      }).then((_) async {
        if (connected) await resumePending(force: true);
      });

  Future<void> startDemo() => _run((cancel) async {
    _gateway.disconnect();
    demo = true;
    _gateway = DemoGateway();
    await _connect('', cancel);
    await _reloadHistory();
  });

  void _clearConnection() {
    _settingsSession++;
    bot = null;
    guilds = const [];
    guildContext = null;
    channelId = null;
    roleId = null;
    invalidate();
    latestReport = null;
  }

  Future<void> disconnect({bool forget = false}) => _run((cancel) async {
    _gateway.disconnect();
    _clearConnection();
    demo = false;
    _gateway = _realGateway;
    if (forget) {
      await credentials.delete();
      savedCredential = false;
    }
    await _reloadHistory();
  });
  Future<void> deleteCredential() => _run((cancel) async {
    await credentials.delete();
    savedCredential = false;
    notice = '保存済みTokenを削除しました。';
  });

  void _selectDefaults({GuildSelection? selection}) {
    channelId = selection == null
        ? readableChannels.firstOrNull?.id
        : readableChannels
              .where((channel) => channel.id == selection.channelId)
              .firstOrNull
              ?.id;
    roleId = selection == null
        ? guildContext?.roles
              .where((r) => roleBlockReason(guildContext!, r) == null)
              .firstOrNull
              ?.id
        : guildContext?.roles
              .where(
                (role) =>
                    role.id == selection.roleId && role.id != selectedGuild?.id,
              )
              .firstOrNull
              ?.id;
    invalidate();
  }

  Future<void> selectGuild(String id) => _run((cancel) async {
    invalidate();
    guildContext = null;
    channelId = null;
    roleId = null;
    final guild = guilds.firstWhere((g) => g.id == id);
    guildContext = await _gateway.context(guild, cancel);
    _selectDefaults(selection: settings.selections[id]);
    _saveSettings();
  });
  Future<void> refresh() => _run((cancel) async {
    final guild = selectedGuild;
    invalidate();
    // 失敗時に古い一覧で再実行できないよう、先に選択を無効にする。
    final oldChannel = channelId;
    final oldRole = roleId;
    guildContext = null;
    channelId = null;
    roleId = null;
    guilds = List.unmodifiable(await _gateway.guilds(cancel));
    final chosen =
        guilds.where((g) => g.id == guild?.id).firstOrNull ??
        guilds.firstOrNull;
    if (chosen == null) return;
    guildContext = await _gateway.context(chosen, cancel);
    channelId =
        readableChannels.where((c) => c.id == oldChannel).firstOrNull?.id ??
        readableChannels.firstOrNull?.id;
    roleId = guildContext!.roles.where((r) => r.id == oldRole).firstOrNull?.id;
  });
  void selectChannel(String? id) {
    if (busy) return;
    channelId = id;
    invalidate();
    _saveSettings();
  }

  void selectRole(String? id) {
    if (busy) return;
    roleId = id;
    invalidate();
    _saveSettings();
  }

  void updateInput(ExtractionInput input) {
    if (busy) return;
    settings = settings.withInput(input);
    invalidate();
    _saveSettings();
  }

  void _saveSettings({bool initial = false}) {
    if (initial && (_settingsReadFailed || _restoredSettings)) return;
    if (selectedGuild != null) {
      settings = settings.select(selectedGuild!.id, channelId, roleId);
    }
    if (!_rememberSettings ||
        !savedCredential ||
        demo ||
        bot == null ||
        settingsStore == null) {
      return;
    }
    final session = _settingsSession;
    pendingSettings = settingsStore!.save(bot!.id, settings).catchError((
      Object _,
    ) {
      if (!_disposed && session == _settingsSession) {
        feedbackRevision++;
        error = '設定を保存できませんでした。';
        _notify();
      }
    });
  }

  Future<void> checkPermissions() => _run((cancel) async {
    if (selectedGuild == null || channelId == null || roleId == null) {
      throw const AppFailure('チャンネルとロールを選択してください。');
    }
    final context = await _gateway.context(selectedGuild!, cancel);
    requireReadable(context, channelId!);
    requireManageable(context, roleId!);
    notice = 'チャンネル閲覧・履歴取得・ロール管理・ロール階層を確認しました。';
  });
  void invalidate() {
    _revision++;
    _extractionRevision = null;
    _removalRevision = null;
    extraction = null;
    removalPlan = null;
    _notify();
  }

  Future<void> extract(Conditions conditions) => taskStore != null && !demo
      ? _startExtractionTask(conditions)
      : _extractOnce(conditions);

  Future<void> _extractOnce(Conditions conditions) => _run((cancel) async {
    invalidate();
    if (bot == null || selectedGuild == null) {
      throw const AppFailure('Discordに接続してください。');
    }
    if (conditions.channelId != channelId ||
        conditions.roleId != roleId ||
        conditions.guildId != selectedGuild!.id) {
      throw const AppFailure('選択中の条件を確認してください。');
    }
    final revision = _revision;
    final result = await ExtractionService(
      _gateway,
    ).extract(selectedGuild!, conditions, bot!, cancel, _progress);
    if (revision != _revision) throw const AppFailure('条件が変更されました。再度確認してください。');
    extraction = result;
    _extractionRevision = revision;
    notice = '${result.users.length}人の対象者を確認しました。';
  }, taskTitle: '対象者の確認');

  RolePlan additionPlan() {
    final result = extraction;
    if (busy ||
        result == null ||
        _extractionRevision != _revision ||
        selectedRole == null) {
      throw const AppFailure('対象者を再確認してください。');
    }
    requireManageable(guildContext!, roleId!);
    return RolePlan(
      guild: selectedGuild!,
      role: selectedRole!,
      action: RoleAction.add,
      targets: result.users.map((u) => u.member).toList(),
      fingerprint: _fingerprint,
      createdAt: result.at,
    );
  }

  Future<void> previewRemoval() => taskStore != null && !demo
      ? _startRemovalPreviewTask()
      : _previewRemovalOnce();

  Future<void> _previewRemovalOnce() => _run((cancel) async {
    removalPlan = null;
    _removalRevision = null;
    if (selectedGuild == null || selectedRole == null || bot == null) {
      throw const AppFailure('サーバーとロールを選択してください。');
    }
    final revision = _revision;
    final context = await _gateway.context(
      selectedGuild!,
      cancel,
      includeChannels: false,
    );
    requireManageable(context, roleId!);
    final targets = await ExtractionService(_gateway).removalTargets(
      selectedGuild!,
      roleId!,
      bot!,
      cancel,
      _progress,
      verifiedContext: context,
    );
    if (revision != _revision) throw const AppFailure('条件が変更されました。再確認してください。');
    removalPlan = RolePlan(
      guild: context.guild,
      role: context.role(roleId!),
      action: RoleAction.remove,
      targets: targets,
      fingerprint: _fingerprint,
      createdAt: DateTime.now().toUtc(),
    );
    _removalRevision = revision;
  }, taskTitle: '解除対象者の確認');

  Future<void> execute(RolePlan plan, {bool acknowledged = false}) =>
      taskStore != null && !demo
      ? _startOperationTask(plan, acknowledged)
      : _executeOnce(plan, acknowledged: acknowledged);

  void _setOperationFeedback(OperationReport report, Cancellation cancel) {
    notice = report.completionMessage;
    if (!report.completedSuccessfully &&
        !cancel.isCancelled &&
        !cancel.isSuspended) {
      error = notice;
    }
  }

  Future<void> _executeOnce(RolePlan plan, {bool acknowledged = false}) => _run(
    (cancel) async {
      if (plan.action == RoleAction.add && _extractionRevision != _revision ||
          plan.action == RoleAction.remove && _removalRevision != _revision) {
        throw const AppFailure('対象者を再確認してください。');
      }
      final fingerprint = _fingerprint;
      try {
        final report = await OperationService(_gateway, _journal).execute(
          plan,
          fingerprint,
          cancel,
          _progress,
          (value) {
            latestReport = value;
            _notify();
          },
          removalAcknowledged: acknowledged,
        );
        latestReport = report;
        _setOperationFeedback(report, cancel);
        await _reloadHistory();
      } finally {
        invalidate();
      }
    },
    taskTitle: '確定ロールの操作',
    closeEligible: true,
  );

  Future<void> exportUsers() => _run((cancel) async {
    final result = _validExtraction();
    notice = await exports.export(
      'users_${result.at.microsecondsSinceEpoch}.csv',
      usersCsv(result),
    );
  });
  Future<void> exportMessages() => _run((cancel) async {
    final result = _validExtraction();
    if (!result.conditions.retainMessages) {
      throw const AppFailure('投稿データは保存していません。PCで対象者を確認してください。');
    }
    notice = await exports.export(
      'messages_${result.at.microsecondsSinceEpoch}.csv',
      messagesCsv(result),
    );
  });
  Future<void> exportReport(OperationReport report) => _run((cancel) async {
    notice = await exports.export(
      'role_${report.plan.action.name}_${report.id}.csv',
      operationsCsv(report),
    );
  });
  Extraction _validExtraction() {
    if (extraction == null || _extractionRevision != _revision) {
      throw const AppFailure('対象者を再確認してください。');
    }
    return extraction!;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    _gateway.disconnect();
    _realGateway.disconnect();
    super.dispose();
  }
}
