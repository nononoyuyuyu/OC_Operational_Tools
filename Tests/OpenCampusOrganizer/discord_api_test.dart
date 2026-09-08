import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_api.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'support.dart';

// RESTのMessage構造ではmemberは必須ではない。すべて架空の値を使用する。
// https://docs.discord.com/developers/resources/message#message-object
const restMessage = <String, dynamic>{
  'id': '100',
  'channel_id': '4',
  'author': {'id': '10', 'username': 'alice', 'global_name': '表示名'},
  'content': '参加します',
  'timestamp': '2026-01-01T12:00:00+00:00',
  'edited_timestamp': null,
  'tts': false,
  'mention_everyone': false,
  'mentions': [],
  'mention_roles': [],
  'attachments': [],
  'embeds': [],
  'pinned': false,
  'type': 0,
};

http.Response jsonResponse(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

DiscordTransport messageTransport(Map<String, dynamic> message) =>
    DiscordTransport(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v10/channels/4/messages');
        return jsonResponse([message]);
      }),
      wait: (_, cancel) async => cancel.check(),
    )..authenticate('fixture-only');

void main() {
  for (final variant in ['省略', 'null', '空オブジェクト']) {
    test('REST投稿のmemberが$variantでも投稿者を読み取れる', () async {
      final message = Map<String, dynamic>.of(restMessage);
      if (variant == 'null') message['member'] = null;
      if (variant == '空オブジェクト') message['member'] = <String, dynamic>{};
      final transport = messageTransport(message);
      addTearDown(transport.dispose);

      final messages = await DiscordApi(
        transport,
      ).messages('4', null, Cancellation());
      expect(messages.single.author.id, '10');
      expect(messages.single.author.displayName, '表示名');
      expect(messages.single.author.roles, isEmpty);
      expect(messages.single.content, '参加します');
      expect(messages.single.at, DateTime.utc(2026, 1, 1, 12));
    });
  }

  test('投稿の部分memberにuserがなくてもauthorと組み合わせられる', () async {
    final transport = messageTransport({
      ...restMessage,
      'member': {
        'nick': 'サーバー表示名',
        'roles': ['2'],
      },
    });
    addTearDown(transport.dispose);
    final messages = await DiscordApi(
      transport,
    ).messages('4', null, Cancellation());
    expect(messages.single.author.id, '10');
    expect(messages.single.author.displayName, 'サーバー表示名');
    expect(messages.single.author.roles, {'2'});
  });

  test('memberの異常な型を空のメンバー情報として採用しない', () async {
    final transport = messageTransport({...restMessage, 'member': []});
    addTearDown(transport.dispose);
    await expectLater(
      DiscordApi(transport).messages('4', null, Cancellation()),
      throwsA(isA<AppFailure>()),
    );
  });

  test('必須のauthorが欠けた投稿は採用しない', () async {
    final message = Map<String, dynamic>.of(restMessage)..remove('author');
    final transport = messageTransport(message);
    addTearDown(transport.dispose);
    await expectLater(
      DiscordApi(transport).messages('4', null, Cancellation()),
      throwsA(isA<AppFailure>()),
    );
  });

  test('REST投稿を抽出した後にメンバーAPIで表示名と保有ロールを照合する', () async {
    final paths = <String>[];
    final transport = DiscordTransport(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        final path = request.url.path;
        paths.add(path);
        final body = switch (path) {
          '/api/v10/users/@me' => {'id': '9', 'username': 'Bot', 'bot': true},
          '/api/v10/applications/@me' => {'id': '9', 'flags': 0},
          '/api/v10/guilds/1' => {
            'id': '1',
            'name': 'テストサーバー',
            'owner_id': '99',
            'roles': [
              {
                'id': '1',
                'name': '@everyone',
                'position': 0,
                'permissions': '66560',
              },
              {'id': '2', 'name': '参加確定', 'position': 2, 'permissions': '0'},
              {
                'id': '3',
                'name': 'Bot',
                'position': 10,
                'permissions': '268435456',
              },
            ],
          },
          '/api/v10/guilds/1/members/9' => {
            'user': {'id': '9', 'username': 'Bot', 'bot': true},
            'nick': null,
            'roles': ['3'],
          },
          '/api/v10/guilds/1/channels' => [
            {'id': '4', 'name': '連絡', 'type': 0, 'permission_overwrites': []},
          ],
          '/api/v10/channels/4/messages' => [restMessage],
          '/api/v10/guilds/1/members/10' => {
            'user': restMessage['author'],
            'nick': '照合後の表示名',
            'roles': ['2'],
          },
          _ => throw StateError('未定義のテスト経路'),
        };
        return jsonResponse(body);
      }),
      wait: (_, cancel) async => cancel.check(),
    );
    addTearDown(transport.dispose);
    final api = DiscordApi(transport);
    final identity = await api.connect('fixture-only', Cancellation());
    final result = await ExtractionService(
      api,
    ).extract(guild, conditions(), identity, Cancellation(), noProgress);
    expect(result.users.single.member.displayName, '照合後の表示名');
    expect(result.users.single.hasRole, isTrue);
    expect(result.messages.single.author.nickname, '照合後の表示名');
    expect(result.users.single.count, 1);
    expect(paths.last, '/api/v10/guilds/1/members/10');
  });
}
