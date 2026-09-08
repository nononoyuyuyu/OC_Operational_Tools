import '../domain/models.dart';

Map<String, dynamic> encodeConditions(Conditions c) => {
  'guildId': c.guildId, 'channelId': c.channelId, 'roleId': c.roleId,
  'start': c.start.toIso8601String(),
  // 再取得するたびに「現在まで」の範囲が広がらないよう固定する。
  'end': (c.end ?? DateTime.now().toUtc()).toIso8601String(),
  'excludeBots': c.excludeBots, 'includeContent': c.includeContent,
  'includeAttachments': c.includeAttachments, 'minimum': c.minimum,
  'retainMessages': c.retainMessages,
};

Conditions decodeConditions(Map<String, dynamic> data) => Conditions(
  guildId: data['guildId'] as String,
  channelId: data['channelId'] as String,
  roleId: data['roleId'] as String,
  start: DateTime.parse(data['start'] as String),
  end: DateTime.parse(data['end'] as String),
  excludeBots: data['excludeBots'] as bool,
  includeContent: data['includeContent'] as bool,
  includeAttachments: data['includeAttachments'] as bool,
  retainMessages: data['retainMessages'] as bool? ?? true,
  minimum: data['minimum'] as int,
);

Map<String, dynamic> encodePlan(RolePlan p) => {
  'guildId': p.guild.id,
  'guildName': p.guild.name,
  'roleId': p.role.id,
  'roleName': p.role.name,
  'rolePosition': p.role.position,
  'rolePermissions': p.role.permissions.toString(),
  'roleManaged': p.role.managed,
  'action': p.action.name,
  'fingerprint': p.fingerprint,
  'createdAt': p.createdAt.toIso8601String(),
  'targets': p.targets
      .map(
        (m) => {
          'id': m.id,
          'username': m.username,
          'globalName': m.globalName,
          'nickname': m.nickname,
          'bot': m.bot,
          'present': m.present,
          'roles': m.roles.toList(),
        },
      )
      .toList(),
};

RolePlan decodePlan(Map<String, dynamic> data) => RolePlan(
  guild: Guild(data['guildId'] as String, data['guildName'] as String),
  role: Role(
    data['roleId'] as String,
    data['roleName'] as String,
    data['rolePosition'] as int,
    permissions: BigInt.parse(data['rolePermissions'] as String),
    managed: data['roleManaged'] as bool,
  ),
  action: RoleAction.values.byName(data['action'] as String),
  fingerprint: data['fingerprint'] as String,
  createdAt: DateTime.parse(data['createdAt'] as String),
  targets: (data['targets'] as List).map((raw) {
    final m = raw as Map<String, dynamic>;
    return Member(
      m['id'] as String,
      m['username'] as String,
      globalName: m['globalName'] as String,
      nickname: m['nickname'] as String,
      bot: m['bot'] as bool,
      present: m['present'] as bool,
      roles: (m['roles'] as List).cast<String>().toSet(),
    );
  }).toList(),
);
