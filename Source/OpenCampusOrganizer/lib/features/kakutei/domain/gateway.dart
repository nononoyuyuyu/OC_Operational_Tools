import '../../../core/failure.dart';
import 'models.dart';
import 'operation_summary.dart';

abstract interface class DiscordGateway {
  Future<BotIdentity> connect(String token, Cancellation cancel);
  Future<List<Guild>> guilds(Cancellation cancel);
  Future<GuildContext> context(
    Guild guild,
    Cancellation cancel, {
    bool includeChannels = true,
  });
  Future<List<Message>> messages(
    String channelId,
    String? before,
    Cancellation cancel,
  );
  Future<Member?> member(String guildId, String userId, Cancellation cancel);
  Future<List<Member>> members(
    String guildId,
    String? after,
    Cancellation cancel,
  );
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  );
  void disconnect();
}

abstract interface class OperationJournal {
  Future<void> save(OperationReport report);
  Future<List<OperationReport>> load();
}

/// 永続履歴の要約取得と詳細取得を分離する追加機能。旧Journalも引き続き利用可能。
abstract interface class IndexedOperationJournal implements OperationJournal {
  Future<OperationHistoryPage> summaries({int offset = 0, int limit = 30});
  Future<OperationReport?> find(String id);
  bool get autoSaveCsv;
  Future<void> setAutoSaveCsv(bool enabled);
}

typedef Progress = void Function(String message, int done, int? total);
