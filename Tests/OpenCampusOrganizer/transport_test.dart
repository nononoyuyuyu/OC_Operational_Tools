import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_api.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';

void main() {
  test('制限されていない要求に固定80msの待機を入れない', () async {
    final waits = <Duration>[];
    final transport = DiscordTransport(
      client: MockClient((_) async => http.Response('{}', 200)),
      wait: (d, c) async {
        c.check();
        waits.add(d);
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    for (var i = 0; i < 3; i++) {
      await transport.request(
        'GET',
        '/guilds/1/members/${10 + i}',
        Cancellation(),
      );
    }
    expect(waits, isEmpty);
  });
  test('制限は同じバケットで待ち、別のサーバーを不要に待たせない', () async {
    var time = DateTime.utc(2026);
    final waits = <Duration>[];
    final transport = DiscordTransport(
      now: () => time,
      client: MockClient(
        (_) async => http.Response(
          '{}',
          200,
          headers: {
            'x-ratelimit-bucket': 'members',
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset-after': '1',
          },
        ),
      ),
      wait: (d, c) async {
        c.check();
        waits.add(d);
        time = time.add(d);
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await transport.request('GET', '/guilds/1/members/10', Cancellation());
    await transport.request('GET', '/guilds/2/members/10', Cancellation());
    expect(waits, isEmpty);
    time = time.add(const Duration(milliseconds: 800));
    await transport.request('GET', '/guilds/1/members/11', Cancellation());
    expect(waits.single.inMilliseconds, 250);
  });
  test('過去1秒の全体要求数を40回に制限する', () async {
    var time = DateTime.utc(2026);
    final sent = <DateTime>[];
    final transport = DiscordTransport(
      now: () => time,
      client: MockClient((_) async {
        sent.add(time);
        return http.Response('{}', 200);
      }),
      wait: (d, c) async {
        c.check();
        time = time.add(d);
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    for (var i = 0; i < 85; i++) {
      await transport.request(
        'GET',
        '/guilds/1/members/${10 + i}',
        Cancellation(),
      );
    }
    expect(
      sent[40].difference(sent[0]).inMilliseconds,
      greaterThanOrEqualTo(1000),
    );
    expect(
      sent[80].difference(sent[40]).inMilliseconds,
      greaterThanOrEqualTo(1000),
    );
  });
  test('制限待機中の取消では次のHTTP要求を送らない', () async {
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          '{}',
          200,
          headers: {
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset-after': '1',
          },
        );
      }),
      wait: (_, c) async {
        c.cancel();
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await transport.request('GET', '/users/@me', Cancellation());
    await expectLater(
      transport.request('GET', '/users/@me', Cancellation()),
      throwsA(isA<Cancelled>()),
    );
    expect(calls, 1);
  });
  test('globalの429は再試行前に指定時間待ち、待機要求にも適用する', () async {
    var time = DateTime.utc(2026);
    final sent = <DateTime>[];
    final transport = DiscordTransport(
      now: () => time,
      client: MockClient((_) async {
        sent.add(time);
        return sent.length == 1
            ? http.Response('{"global":true,"retry_after":1}', 429)
            : http.Response('{}', 200);
      }),
      wait: (d, c) async {
        c.check();
        time = time.add(d);
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await Future.wait([
      transport.request('GET', '/users/@me', Cancellation()),
      transport.request('GET', '/guilds/1', Cancellation()),
    ]);
    expect(sent.length, 3);
    expect(
      sent[1].difference(sent[0]).inMilliseconds,
      greaterThanOrEqualTo(1000),
    );
    expect(sent[2].isBefore(sent[1]), isFalse);
  });
  test('429はサーバー指定の待ち時間後に再試行する', () async {
    var calls = 0;
    final waits = <Duration>[];
    final transport = DiscordTransport(
      client: MockClient((request) async {
        expect(request.url.host, 'discord.com');
        expect(request.followRedirects, isFalse);
        return ++calls == 1
            ? http.Response(
                '{"retry_after":0.25}',
                429,
                headers: {'retry-after': '0.5'},
              )
            : http.Response('[]', 200);
      }),
      wait: (duration, cancel) async {
        cancel.check();
        waits.add(duration);
      },
    )..authenticate('fixture-only');
    await transport.request('GET', '/users/@me/guilds', Cancellation());
    expect(calls, 2);
    expect(waits.last.inMilliseconds, greaterThanOrEqualTo(500));
    transport.dispose();
  });
  test('更新時の通信失敗を自動再試行せず、例外の本文も漏らさない', () async {
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        throw Exception('秘密の応答');
      }),
    )..authenticate('fixture-only');
    await expectLater(
      transport.request('PUT', '/guilds/1/members/2/roles/3', Cancellation()),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.uncertain, '未確認', isTrue)
            .having((e) => e.message, '秘密を表示しない', isNot(contains('秘密'))),
      ),
    );
    expect(calls, 1);
    transport.dispose();
  });
  test('403のレスポンスに含まれる機密文字列を公開しない', () async {
    final transport = DiscordTransport(
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode('{"message":"秘密"}'), 403),
      ),
    )..authenticate('fixture-only');
    await expectLater(
      transport.request('GET', '/users/@me', Cancellation()),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.status, '状態', 403)
            .having((e) => e.message, '本文', isNot(contains('秘密'))),
      ),
    );
    transport.dispose();
  });
  test('要求を直列化し、待機中の取消では送信しない', () async {
    final gate = Completer<void>();
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        await gate.future;
        return http.Response('{}', 200);
      }),
      wait: (_, cancel) async => cancel.check(),
    )..authenticate('fixture-only');
    final first = transport.request('GET', '/users/@me', Cancellation());
    final cancel = Cancellation();
    final second = transport.request('GET', '/users/@me', cancel);
    final cancelled = expectLater(second, throwsA(isA<Cancelled>()));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    cancel.cancel();
    gate.complete();
    await first;
    await cancelled;
    expect(calls, 1);
    transport.dispose();
  });
  test('接続世代が変わった待機要求を実行しない', () async {
    final transport = DiscordTransport(
      client: MockClient((_) async => http.Response('{}', 200)),
    )..authenticate('fixture-one');
    final result = transport.request('GET', '/users/@me', Cancellation());
    transport.authenticate('fixture-two');
    await expectLater(result, throwsA(isA<AppFailure>()));
    transport.dispose();
  });
  test('Botの確認・ApplicationのIntentフラグを読み取る', () async {
    final paths = <String>[];
    final transport = DiscordTransport(
      client: MockClient((r) async {
        paths.add(r.url.path);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/users/@me')
                ? {'id': '9', 'username': 'Bot', 'bot': true}
                : {'id': '9', 'flags': (1 << 15) | (1 << 19)},
          ),
          200,
        );
      }),
      wait: (_, c) async => c.check(),
    );
    final bot = await DiscordApi(
      transport,
    ).connect('fixture-only', Cancellation());
    expect(bot.membersIntent, isTrue);
    expect(bot.contentIntent, isTrue);
    expect(paths, ['/api/v10/users/@me', '/api/v10/applications/@me']);
    expect(bot.inviteUrl.queryParameters['permissions'], '268502016');
    transport.dispose();
  });
}
