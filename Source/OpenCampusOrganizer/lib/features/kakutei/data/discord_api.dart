import '../../../core/failure.dart';
import '../domain/gateway.dart';
import '../domain/models.dart';
import 'discord_transport.dart';

typedef Json = Map<String, dynamic>;

class DiscordApi implements DiscordGateway {
  DiscordApi(this.transport);
  final DiscordTransport transport;
  BotIdentity? _bot;
  String _id(String value) {
    if (!RegExp(r'^[1-9]\d{0,19}$').hasMatch(value)) {
      throw const AppFailure('Discord IDが正しくありません。');
    }
    return value;
  }

  Json _object(Object? value) {
    if (value is! Json) throw const AppFailure('Discordの応答形式が正しくありません。');
    return value;
  }

  List<Json> _list(Object? value) {
    if (value is! List) throw const AppFailure('Discordの一覧を読み取れませんでした。');
    return value.map(_object).toList();
  }

  Future<Json> _get(String path, Cancellation cancel) async =>
      _object(await transport.request('GET', path, cancel));

  @override
  Future<BotIdentity> connect(String token, Cancellation cancel) async {
    disconnect();
    transport.authenticate(token);
    try {
      final user = await _get('/users/@me', cancel);
      if (user['bot'] != true) throw const AppFailure('BotのTokenを使用してください。');
      final app = await _get('/applications/@me', cancel);
      final flags = (app['flags'] as num?)?.toInt() ?? 0;
      _bot = BotIdentity(
        _id(user['id'] as String),
        user['username'] as String,
        _id(app['id'] as String),
        membersIntent: (flags & ((1 << 14) | (1 << 15))) != 0,
        contentIntent: (flags & ((1 << 18) | (1 << 19))) != 0,
      );
      return _bot!;
    } catch (_) {
      disconnect();
      rethrow;
    }
  }

  @override
  Future<List<Guild>> guilds(Cancellation cancel) async {
    final result = <String, Guild>{};
    String? after;
    while (true) {
      final page = _list(
        await transport.request(
          'GET',
          '/users/@me/guilds',
          cancel,
          query: {'limit': '200', 'after': ?after},
        ),
      );
      for (final g in page) {
        final id = _id(g['id'] as String);
        result[id] = Guild(id, g['name'] as String);
      }
      if (page.length < 200) break;
      final next = page
          .map((g) => BigInt.parse(g['id'] as String))
          .reduce((a, b) => a > b ? a : b)
          .toString();
      if (after != null && BigInt.parse(next) <= BigInt.parse(after)) {
        throw const AppFailure('サーバー一覧を取得できませんでした。');
      }
      after = next;
    }
    return result.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Member _member(Json value, {Json? user}) {
    final u = user ?? _object(value['user']);
    return Member(
      _id(u['id'] as String),
      (u['username'] as String?) ?? '',
      globalName: (u['global_name'] as String?) ?? '',
      nickname: (value['nick'] as String?) ?? '',
      bot: u['bot'] == true,
      roles: ((value['roles'] as List?) ?? []).cast<String>().toSet(),
    );
  }

  @override
  Future<GuildContext> context(
    Guild guild,
    Cancellation cancel, {
    bool includeChannels = true,
  }) async {
    final identity = _bot;
    if (identity == null) throw const AppFailure('Discordに接続してください。');
    final prefix = '/guilds/${_id(guild.id)}';
    final responses = await transport.readBatch([
      prefix,
      '$prefix/members/${_id(identity.id)}',
      if (includeChannels) '$prefix/channels',
    ], cancel);
    cancel.check();
    if (!identical(identity, _bot)) {
      throw const AppFailure('接続が変更されました。再接続してください。');
    }
    final value = _object(responses[0]);
    final me = _member(_object(responses[1]));
    final roles =
        _list(value['roles'])
            .map(
              (r) => Role(
                _id(r['id'] as String),
                r['name'] as String,
                (r['position'] as num).toInt(),
                permissions: BigInt.parse(r['permissions'] as String),
                managed: r['managed'] == true,
              ),
            )
            .toList()
          ..sort((a, b) => b.position.compareTo(a.position));
    if (!includeChannels) {
      return GuildContext(
        Guild(guild.id, value['name'] as String),
        value['owner_id'] as String,
        me,
        roles,
        const [],
      );
    }
    final rawChannels = _list(responses[2]);
    final categories = {
      for (final c in rawChannels.where((c) => c['type'] == 4))
        c['id']: c['name'],
    };
    final channels =
        rawChannels
            .where((c) => c['type'] == 0 && c['name'] != null)
            .map(
              (c) => Channel(
                _id(c['id'] as String),
                c['name'] as String,
                category: (categories[c['parent_id']] as String?) ?? '',
                overwrites: _list(c['permission_overwrites'] ?? [])
                    .map(
                      (o) => Overwrite(
                        o['id'] as String,
                        (o['type'] as num).toInt(),
                        BigInt.parse(o['allow'] as String),
                        BigInt.parse(o['deny'] as String),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    return GuildContext(
      Guild(guild.id, value['name'] as String),
      value['owner_id'] as String,
      me,
      roles,
      channels,
    );
  }

  @override
  Future<Member?> member(
    String guildId,
    String userId,
    Cancellation cancel,
  ) async {
    try {
      return _member(
        await _get('/guilds/${_id(guildId)}/members/${_id(userId)}', cancel),
      );
    } on AppFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Member>> members(
    String guildId,
    String? after,
    Cancellation cancel,
  ) async => _list(
    await transport.request(
      'GET',
      '/guilds/${_id(guildId)}/members',
      cancel,
      query: {'limit': '1000', if (after != null) 'after': _id(after)},
    ),
  ).map((m) => _member(m)).toList();

  @override
  Future<List<Message>> messages(
    String channelId,
    String? before,
    Cancellation cancel,
  ) async =>
      _list(
            await transport.request(
              'GET',
              '/channels/${_id(channelId)}/messages',
              cancel,
              query: {
                'limit': '100',
                if (before != null) 'before': _id(before),
              },
            ),
          )
          .map(
            (m) => Message(
              _id(m['id'] as String),
              channelId,
              // RESTの投稿ではmemberが省略される。空値もJSONオブジェクトの型を保つ。
              _member(
                _object(m['member'] ?? const <String, dynamic>{}),
                user: _object(m['author']),
              ),
              DateTime.parse(m['timestamp'] as String).toUtc(),
              content: (m['content'] as String?) ?? '',
              attachments: _list(
                m['attachments'] ?? [],
              ).map((a) => a['url'] as String).toList(),
              hasEmbed: ((m['embeds'] as List?) ?? []).isNotEmpty,
              type: (m['type'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    await transport.request(
      action == RoleAction.add ? 'PUT' : 'DELETE',
      '/guilds/${_id(guildId)}/members/${_id(userId)}/roles/${_id(roleId)}',
      cancel,
    );
  }

  @override
  void disconnect() {
    _bot = null;
    transport.disconnect();
  }
}
