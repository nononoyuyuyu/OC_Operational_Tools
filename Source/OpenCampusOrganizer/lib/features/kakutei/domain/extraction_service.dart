import '../../../core/failure.dart';
import 'gateway.dart';
import 'models.dart';
import 'permissions.dart';

class ExtractionService {
  const ExtractionService(
    this.gateway, {
    this.maxScannedMessages = 100000,
    this.maxMessagePages = 1001,
  }) : assert(maxScannedMessages > 0),
       assert(maxMessagePages > 0);
  final DiscordGateway gateway;
  final int maxScannedMessages;
  final int maxMessagePages;

  Future<Extraction> extract(
    Guild guild,
    Conditions conditions,
    BotIdentity bot,
    Cancellation cancel,
    Progress progress,
  ) async {
    conditions.validate();
    if (conditions.guildId != guild.id) {
      throw const AppFailure('サーバーを選択し直してください。');
    }
    final context = await gateway.context(guild, cancel);
    requireReadable(context, conditions.channelId);
    context.role(conditions.roleId);
    if ((conditions.includeContent || conditions.includeAttachments) &&
        !bot.contentIntent) {
      throw const AppFailure(
        '本文・添付URLの取得にはMessage Content Intentが必要です。Developer Portalで有効にして再接続してください。',
      );
    }
    final at = DateTime.now().toUtc();
    final end = conditions.end ?? at;
    final messages = <Message>[];
    final groups = <String, _ActivityAccumulator>{};
    final seen = <String>{};
    // beforeは排他的。終了日時と同じミリ秒の投稿も含めるため次のミリ秒を使う。
    const discordEpoch = 1420070400000;
    final endMillis = end.millisecondsSinceEpoch - discordEpoch;
    String? before = endMillis >= 0
        ? (BigInt.from(endMillis + 1) << 22).toString()
        : null;
    var excludedBots = 0;
    var matchedMessages = 0;
    var scannedMessages = 0;
    var messagePages = 0;
    var potentialMissingContent = false;
    var hasContent = false;
    var reachedStart = false;
    while (!reachedStart) {
      cancel.check();
      if (messagePages >= maxMessagePages) {
        throw const AppFailure('投稿の取得ページ数が上限に達しました。期間を短くして再度抽出してください。');
      }
      final page = await gateway.messages(conditions.channelId, before, cancel);
      messagePages++;
      if (page.isEmpty) break;
      scannedMessages += page.length;
      if (scannedMessages > maxScannedMessages) {
        throw AppFailure(
          '走査した投稿が$maxScannedMessages件を超えました。期間を短くして再度抽出してください。',
        );
      }
      final next = page
          .map((m) => BigInt.parse(m.id))
          .reduce((a, b) => a < b ? a : b)
          .toString();
      if (before != null && BigInt.parse(next) >= BigInt.parse(before)) {
        throw const AppFailure('履歴の続きが取得できないため中止しました。再度抽出してください。');
      }
      for (final m in page) {
        if (!seen.add(m.id)) continue;
        if (m.at.isBefore(conditions.start)) {
          reachedStart = true;
          continue;
        }
        if (m.at.isAfter(end)) continue;
        if (conditions.excludeBots && m.author.bot) {
          excludedBots++;
          continue;
        }
        potentialMissingContent |=
            m.type == 0 &&
            m.content.isEmpty &&
            m.attachments.isEmpty &&
            !m.hasEmbed;
        hasContent |= m.content.isNotEmpty;
        final group = groups.putIfAbsent(
          m.author.id,
          () => _ActivityAccumulator(m.author, m.at),
        );
        group.add(m.at);
        matchedMessages++;
        // One original author per user, rather than one Member per message.
        if (conditions.retainMessages) {
          messages.add(
            Message(
              m.id,
              m.channelId,
              group.original,
              m.at,
              content: conditions.includeContent ? m.content : '',
              attachments: conditions.includeAttachments
                  ? m.attachments
                  : const [],
              hasEmbed: m.hasEmbed,
              type: m.type,
            ),
          );
        }
      }
      before = next;
      progress('投稿を取得中', matchedMessages, null);
      if (matchedMessages > 100000) {
        throw const AppFailure('投稿が100,000件を超えました。期間を短くして再度抽出してください。');
      }
      if (page.length < 100) break;
    }
    seen.clear();
    if (conditions.includeContent &&
        matchedMessages > 0 &&
        !hasContent &&
        potentialMissingContent) {
      throw const AppFailure(
        '本文を取得できていない可能性があります。Message Content Intentを確認し、再接続してください。',
      );
    }
    if (!conditions.retainMessages) {
      groups.removeWhere((_, group) => group.count < conditions.minimum);
    }
    var resolvedCount = 0;
    // Bound large-server scans; users not found still receive individual lookup.
    if (bot.membersIntent && groups.length >= 8) {
      String? after;
      for (var pageNumber = 0; pageNumber < 4; pageNumber++) {
        cancel.check();
        List<Member> page;
        try {
          page = await gateway.members(guild.id, after, cancel);
        } on AppFailure catch (error) {
          if (error.status == 403) break;
          rethrow;
        }
        if (page.isEmpty) break;
        final next = page
            .map((m) => BigInt.parse(m.id))
            .reduce((a, b) => a > b ? a : b)
            .toString();
        if (after != null && BigInt.parse(next) <= BigInt.parse(after)) {
          throw const AppFailure('メンバー一覧の続きを取得できませんでした。再度抽出してください。');
        }
        for (final member in page) {
          final group = groups[member.id];
          if (group == null) continue;
          if (group.resolved == null) resolvedCount++;
          group.resolved = member;
        }
        progress('メンバーを照合中', resolvedCount, groups.length);
        if (resolvedCount == groups.length || page.length < 1000) break;
        after = next;
      }
    }
    for (final group in groups.values) {
      cancel.check();
      if (group.resolved != null) continue;
      final original = group.original;
      group.resolved =
          await gateway.member(guild.id, original.id, cancel) ??
          Member(
            original.id,
            original.username,
            globalName: original.globalName,
            bot: original.bot,
            present: false,
          );
      progress('メンバーを照合中', ++resolvedCount, groups.length);
    }
    final users = <Activity>[];
    for (final group in groups.values) {
      if (group.count < conditions.minimum) continue;
      final member = group.resolved!;
      users.add(
        Activity(
          member,
          group.count,
          group.first,
          group.last,
          member.roles.contains(conditions.roleId),
        ),
      );
    }
    users.sort((a, b) {
      final order = a.member.displayName.compareTo(b.member.displayName);
      return order != 0
          ? order
          : BigInt.parse(a.member.id).compareTo(BigInt.parse(b.member.id));
    });
    // Replace progressively in the private working list. Avoid keeping a
    // second complete Message graph alive; Extraction still copies the list
    // at the immutable public boundary. Full desktop CSV semantics remain.
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      messages[i] = Message(
        m.id,
        m.channelId,
        groups[m.author.id]!.resolved!,
        m.at,
        content: m.content,
        attachments: m.attachments,
        hasEmbed: m.hasEmbed,
        type: m.type,
      );
    }
    messages.sort((a, b) => a.at.compareTo(b.at));
    cancel.check();
    return Extraction(
      conditions,
      messages,
      users,
      excludedBots: excludedBots,
      messageCount: matchedMessages,
      at: at,
    );
  }

  Future<List<Member>> removalTargets(
    Guild guild,
    String roleId,
    BotIdentity bot,
    Cancellation cancel,
    Progress progress, {
    GuildContext? verifiedContext,
  }) async {
    if (!bot.membersIntent) {
      throw const AppFailure(
        '一括解除にはServer Members Intentが必要です。Developer Portalで有効にして再接続してください。',
      );
    }
    requireManageable(
      verifiedContext ??
          await gateway.context(guild, cancel, includeChannels: false),
      roleId,
    );
    final targets = <String, Member>{};
    var scannedMembers = 0;
    String? after;
    while (true) {
      cancel.check();
      final page = await gateway.members(guild.id, after, cancel);
      if (page.isEmpty) break;
      scannedMembers += page.length;
      if (scannedMembers > 100000) {
        throw const AppFailure('走査したメンバーが100,000件を超えたため中止しました。');
      }
      final next = page
          .map((m) => BigInt.parse(m.id))
          .reduce((a, b) => a > b ? a : b)
          .toString();
      if (after != null && BigInt.parse(next) <= BigInt.parse(after)) {
        throw const AppFailure('全メンバーの取得を確認できないため中止しました。');
      }
      for (final member in page) {
        if (member.roles.contains(roleId)) {
          targets[member.id] = member;
        } else {
          // A repeated member can have changed roles between pages.
          targets.remove(member.id);
        }
      }
      after = next;
      progress('ロール保有者を確認中', scannedMembers, null);
      if (page.length < 1000) break;
    }
    cancel.check();
    return targets.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }
}

class _ActivityAccumulator {
  _ActivityAccumulator(this.original, DateTime at) : first = at, last = at;
  final Member original;
  Member? resolved;
  int count = 0;
  DateTime first, last;

  void add(DateTime at) {
    count++;
    if (at.isBefore(first)) first = at;
    if (at.isAfter(last)) last = at;
  }
}
