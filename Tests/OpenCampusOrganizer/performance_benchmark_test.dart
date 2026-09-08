import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_api.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';
import 'package:open_campus_organizer/features/kakutei/domain/extraction_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/operation_service.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'support.dart';

// HTTP回数を同じ架空の50人で比較する。時間は測らず、実Discordへは接続しない。
// 旧版比較時のみ --dart-define=OC_BENCHMARK_BASELINE=true を指定する。
void main() {
  const baseline = bool.fromEnvironment('OC_BENCHMARK_BASELINE');
  for (final action in ['extract', 'add', 'remove']) {
    test('HTTP回数ベンチマーク $action', () async {
      var calls = 0;
      var channels = 0;
      final removing = action == 'remove';
      final people = List.generate(
        50,
        (i) => Member('${1000 + i}', 'member$i', roles: removing ? {'2'} : {}),
      );
      Map<String, Object> memberJson(Member m) => {
        'user': {'id': m.id, 'username': m.username, 'bot': m.bot},
        'roles': m.roles.toList(),
      };
      final transport = DiscordTransport(
        client: MockClient((request) async {
          calls++;
          final path = request.url.path;
          if (request.method != 'GET') return http.Response('', 204);
          Object body;
          if (path == '/api/v10/users/@me') {
            body = {'id': '9', 'username': 'Bot', 'bot': true};
          } else if (path == '/api/v10/applications/@me') {
            body = {'id': '9', 'flags': (1 << 15)};
          } else if (path == '/api/v10/guilds/1') {
            body = {
              'id': '1',
              'name': guild.name,
              'owner_id': '99',
              'roles': [
                {
                  'id': '1',
                  'name': '@everyone',
                  'position': 0,
                  'permissions': '66560',
                },
                {
                  'id': '2',
                  'name': targetRole.name,
                  'position': 2,
                  'permissions': '0',
                },
                {
                  'id': '3',
                  'name': 'Bot',
                  'position': 10,
                  'permissions': '268435456',
                },
              ],
            };
          } else if (path == '/api/v10/guilds/1/channels') {
            channels++;
            body = [
              {'id': '4', 'name': '連絡', 'type': 0, 'permission_overwrites': []},
            ];
          } else if (path == '/api/v10/guilds/1/members/9') {
            body = memberJson(me);
          } else if (path == '/api/v10/guilds/1/members') {
            body = people.map(memberJson).toList();
          } else if (path == '/api/v10/channels/4/messages') {
            if (!baseline) {
              final cursor = BigInt.parse(
                request.url.queryParameters['before']!,
              );
              expect(
                cursor >> 22,
                BigInt.from(
                  conditions().end!.millisecondsSinceEpoch - 1420070400000 + 1,
                ),
              );
            }
            body = people.indexed
                .map(
                  (item) => {
                    'id': '${5000 + item.$1}',
                    'author': memberJson(item.$2)['user'],
                    'timestamp': start.toIso8601String(),
                    'type': 0,
                    'content': '',
                    'attachments': [],
                  },
                )
                .toList();
          } else if (path.startsWith('/api/v10/guilds/1/members/')) {
            body = memberJson(
              people.firstWhere((m) => path.endsWith('/${m.id}')),
            );
          } else {
            throw StateError('未定義のテスト経路');
          }
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
        wait: (_, c) async => c.check(),
      );
      addTearDown(transport.dispose);
      final api = DiscordApi(transport);
      final identity = await api.connect('fixture-only', Cancellation());
      calls = 0;
      if (action == 'extract') {
        final result = await ExtractionService(
          api,
        ).extract(guild, conditions(), identity, Cancellation(), noProgress);
        expect(result.users.length, 50);
        expect(calls, baseline ? 54 : 5);
      } else {
        final service = OperationService(api, FakeJournal());
        final result =
            await Function.apply(
                  service.execute,
                  [
                    plan(
                      action: removing ? RoleAction.remove : RoleAction.add,
                      targets: people,
                    ),
                    'current',
                    Cancellation(),
                    noProgress,
                    (OperationReport _) {},
                  ],
                  {
                    #removalAcknowledged: removing,
                    if (baseline && removing)
                      #roleNameConfirmation: targetRole.name,
                  },
                )
                as OperationReport;
        expect(result.count(Outcome.success), 50);
        expect(calls, baseline ? 253 : 106);
        expect(channels, baseline ? 51 : 0);
      }
      // ignore: avoid_print
      print(
        'HTTP_BENCHMARK ${baseline ? '0.1.1' : '0.2.0'} $action people=50 requests=$calls channels=$channels',
      );
    });
  }
}
