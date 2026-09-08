import '../../../core/failure.dart';
import '../domain/gateway.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';

// 本番の接続処理とは別の、通信しないサンプル。
class DemoGateway implements DiscordGateway {
  static const guild = Guild('100000000000000001', 'OCスタッフ');
  static const roleId = '100000000000000002';
  static const channelId = '100000000000000003';
  final _roles = <String, Set<String>>{};
  int mutations = 0;
  final _sampleTime = DateTime.now().toUtc();
  List<Member> get people => List.generate(8, (i) {
    final id = '20000000000000000$i';
    final names = [
      '青木 はるか',
      '石川 蓮',
      '小野 ひなた',
      '加藤 颯太',
      '佐藤 美月',
      '高橋 悠真',
      '中村 凛',
      '山田 葵',
    ];
    return Member(
      id,
      'oc_staff_${i + 1}',
      nickname: names[i],
      roles: _roles.putIfAbsent(id, () => i == 1 || i == 4 ? {roleId} : {}),
    );
  });
  @override
  Future<BotIdentity> connect(String token, Cancellation cancel) async {
    cancel.check();
    return const BotIdentity(
      '100000000000000004',
      'OCOアシスタント',
      '100000000000000004',
      membersIntent: true,
      contentIntent: true,
    );
  }

  @override
  Future<List<Guild>> guilds(Cancellation cancel) async {
    cancel.check();
    return [guild];
  }

  @override
  Future<GuildContext> context(
    Guild guild,
    Cancellation cancel, {
    bool includeChannels = true,
  }) async {
    cancel.check();
    return GuildContext(
      guild,
      '100000000000000099',
      Member(
        '100000000000000004',
        'OCOアシスタント',
        bot: true,
        roles: {'100000000000000005'},
      ),
      [
        Role(guild.id, '@everyone', 0, permissions: viewChannel | readHistory),
        Role(roleId, '参加確定', 2),
        Role('100000000000000006', '運営スタッフ', 3),
        Role('100000000000000005', 'OCOアシスタント', 10, permissions: manageRoles),
      ],
      [
        Channel(channelId, '参加連絡', category: 'オープンキャンパス'),
        Channel('100000000000000007', 'スタッフ連絡', category: '運営'),
      ],
    );
  }

  @override
  Future<List<Message>> messages(
    String channelId,
    String? before,
    Cancellation cancel,
  ) async {
    await cancel.wait(const Duration(milliseconds: 300));
    final boundary = before == null ? null : BigInt.parse(before);
    return List.generate(18, (i) {
          final at = _sampleTime.subtract(Duration(hours: i + 1));
          final id =
              BigInt.from(at.millisecondsSinceEpoch - 1420070400000) << 22;
          return Message(
            id.toString(),
            channelId,
            people[i % people.length],
            at,
            content: i % 2 == 0 ? '次回のオープンキャンパスに参加します。' : '当日は受付を担当します。',
          );
        })
        .where(
          (message) => boundary == null || BigInt.parse(message.id) < boundary,
        )
        .toList();
  }

  @override
  Future<Member?> member(
    String guildId,
    String userId,
    Cancellation cancel,
  ) async {
    cancel.check();
    return people.where((m) => m.id == userId).firstOrNull;
  }

  @override
  Future<List<Member>> members(
    String guildId,
    String? after,
    Cancellation cancel,
  ) async {
    cancel.check();
    return after == null ? people : [];
  }

  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    await cancel.wait(const Duration(milliseconds: 160));
    mutations++;
    if (action == RoleAction.add) {
      _roles[userId]!.add(roleId);
    } else {
      _roles[userId]!.remove(roleId);
    }
  }

  @override
  void disconnect() {}
}
