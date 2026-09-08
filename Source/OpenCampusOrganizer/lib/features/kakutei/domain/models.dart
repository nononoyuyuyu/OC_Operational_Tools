import '../../../core/failure.dart';
import 'operation_rows.dart';

class Guild {
  const Guild(this.id, this.name);
  final String id;
  final String name;
}

class Role {
  Role(
    this.id,
    this.name,
    this.position, {
    BigInt? permissions,
    this.managed = false,
  }) : permissions = permissions ?? BigInt.zero;
  final String id;
  final String name;
  final int position;
  final BigInt permissions;
  final bool managed;
}

class Overwrite {
  const Overwrite(this.id, this.type, this.allow, this.deny);
  final String id;
  final int type;
  final BigInt allow;
  final BigInt deny;
}

class Channel {
  Channel(
    this.id,
    this.name, {
    this.category = '',
    this.type = 0,
    List<Overwrite> overwrites = const [],
  }) : overwrites = List.unmodifiable(overwrites);
  final String id;
  final String name;
  final String category;
  final int type;
  final List<Overwrite> overwrites;
  String get label => '${category.isEmpty ? '' : '$category / '}#$name · $id';
}

class Member {
  Member(
    this.id,
    this.username, {
    this.globalName = '',
    this.nickname = '',
    this.bot = false,
    this.present = true,
    Set<String> roles = const {},
  }) : roles = Set.unmodifiable(roles);
  final String id;
  final String username;
  final String globalName;
  final String nickname;
  final bool bot;
  final bool present;
  final Set<String> roles;
  String get displayName => nickname.trim().isNotEmpty
      ? nickname
      : globalName.trim().isNotEmpty
      ? globalName
      : username;
}

class BotIdentity {
  const BotIdentity(
    this.id,
    this.name,
    this.applicationId, {
    required this.membersIntent,
    required this.contentIntent,
  });
  final String id;
  final String name;
  final String applicationId;
  final bool membersIntent;
  final bool contentIntent;
  Uri get inviteUrl => Uri.https('discord.com', '/oauth2/authorize', {
    'client_id': applicationId,
    'scope': 'bot',
    'permissions': '268502016',
  });
}

class GuildContext {
  GuildContext(
    this.guild,
    this.ownerId,
    this.me,
    List<Role> roles,
    List<Channel> channels,
  ) : roles = List.unmodifiable(roles),
      channels = List.unmodifiable(channels);
  final Guild guild;
  final String ownerId;
  final Member me;
  final List<Role> roles;
  final List<Channel> channels;
  Role role(String id) => roles.firstWhere(
    (r) => r.id == id,
    orElse: () => throw const AppFailure('対象ロールが見つかりません。一覧を更新してください。'),
  );
  Channel channel(String id) => channels.firstWhere(
    (c) => c.id == id,
    orElse: () => throw const AppFailure('対象チャンネルが見つかりません。一覧を更新してください。'),
  );
}

class Message {
  Message(
    this.id,
    this.channelId,
    this.author,
    this.at, {
    this.content = '',
    List<String> attachments = const [],
    this.hasEmbed = false,
    this.type = 0,
  }) : attachments = List.unmodifiable(attachments);
  final String id;
  final String channelId;
  final Member author;
  final DateTime at;
  final String content;
  final List<String> attachments;
  final bool hasEmbed;
  final int type;
}

class Conditions {
  Conditions({
    required this.guildId,
    required this.channelId,
    required this.roleId,
    required DateTime start,
    DateTime? end,
    this.excludeBots = true,
    this.includeContent = false,
    this.includeAttachments = false,
    this.retainMessages = true,
    this.minimum = 1,
  }) : start = start.toUtc(),
       end = end?.toUtc();
  final String guildId;
  final String channelId;
  final String roleId;
  final DateTime start;
  final DateTime? end;
  final bool excludeBots;
  final bool includeContent;
  final bool includeAttachments;
  final bool retainMessages;
  final int minimum;
  String get fingerprint => [
    guildId,
    channelId,
    roleId,
    start.toIso8601String(),
    end?.toIso8601String(),
    excludeBots,
    includeContent,
    includeAttachments,
    retainMessages,
    minimum,
  ].join('|');
  void validate() {
    if ([guildId, channelId, roleId].any((s) => s.isEmpty)) {
      throw const AppFailure('サーバー、チャンネル、対象ロールを選択してください。');
    }
    if (minimum < 1 || minimum > 100000) {
      throw const AppFailure('最小投稿数は1〜100,000で指定してください。');
    }
    if (end != null && end!.isBefore(start)) {
      throw const AppFailure('終了日時は開始日時以降にしてください。');
    }
    if (start.isAfter(DateTime.now())) {
      throw const AppFailure('開始日時は現在以前にしてください。');
    }
  }
}

class Activity {
  const Activity(this.member, this.count, this.first, this.last, this.hasRole);
  final Member member;
  final int count;
  final DateTime first;
  final DateTime last;
  final bool hasRole;
  String get planned => !member.present
      ? '退出済み'
      : hasRole
      ? '付与済み'
      : '付与予定';
}

class Extraction {
  Extraction(
    this.conditions,
    List<Message> messages,
    List<Activity> users, {
    required this.excludedBots,
    required this.at,
    int? messageCount,
  }) : messages = List.unmodifiable(messages),
       users = List.unmodifiable(users),
       messageCount = messageCount ?? messages.length;
  final Conditions conditions;
  final List<Message> messages;
  final List<Activity> users;
  final int messageCount;
  final int excludedBots;
  final DateTime at;
}

enum RoleAction { add, remove }

enum Outcome {
  pending,
  inFlight,
  success,
  skipped,
  failed,
  unprocessed,
  uncertain,
}

class OperationRow {
  const OperationRow(this.member, this.outcome, this.reason);
  final Member member;
  final Outcome outcome;
  final String reason;
}

class RolePlan {
  RolePlan({
    required this.guild,
    required this.role,
    required this.action,
    required List<Member> targets,
    required this.fingerprint,
    required this.createdAt,
  }) : targets = List.unmodifiable(targets);
  final Guild guild;
  final Role role;
  final RoleAction action;
  final List<Member> targets;
  final String fingerprint;
  final DateTime createdAt;
  String get actionLabel => action == RoleAction.add ? '付与' : '解除';
}

class OperationReport {
  OperationReport({
    required this.id,
    required this.plan,
    required List<OperationRow> rows,
    required this.startedAt,
    this.finishedAt,
  }) : rows = OperationRows(rows);
  final String id;
  final RolePlan plan;
  final OperationRows rows;
  final DateTime startedAt;
  final DateTime? finishedAt;
  int count(Outcome outcome) => rows.count(outcome);
}

String outcomeLabel(Outcome outcome) => switch (outcome) {
  Outcome.pending => '未処理',
  Outcome.inFlight => '結果未確認',
  Outcome.success => '成功',
  Outcome.skipped => 'スキップ',
  Outcome.failed => '失敗',
  Outcome.unprocessed => '未処理',
  Outcome.uncertain => '結果未確認',
};
