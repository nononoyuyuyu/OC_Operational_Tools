import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';

void main() {
  test('同じTokenで再接続しても古い待機中の更新要求を復活させない', () async {
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 204);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final request = transport.request(
      'PUT',
      '/guilds/1/members/2/roles/3',
      Cancellation(),
    );
    transport.disconnect();
    transport.authenticate('fixture-only');
    await expectLater(request, throwsA(isA<AppFailure>()));
    expect(calls, 0);
  });

  test('同じTokenの再接続前に送信した読取結果を公開しない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final transport = DiscordTransport(
      client: MockClient((_) async {
        started.complete();
        await release.future;
        return http.Response('{"old":true}', 200);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final request = transport.request('GET', '/users/@me', Cancellation());
    final checked = expectLater(request, throwsA(isA<AppFailure>()));
    await started.future;
    transport.disconnect();
    transport.authenticate('fixture-only');
    release.complete();
    await checked;
  });

  test('429の待機中に同じTokenで再接続しても古い要求を再送しない', () async {
    var calls = 0;
    late DiscordTransport transport;
    transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{"retry_after":1}', 429)
            : http.Response('{}', 200);
      }),
      wait: (_, cancel) async {
        cancel.check();
        transport.disconnect();
        transport.authenticate('fixture-only');
      },
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await expectLater(
      transport.request('GET', '/users/@me', Cancellation()),
      throwsA(isA<AppFailure>()),
    );
    expect(calls, 1);
  });

  for (final global in [false, true]) {
    test('最終429の待ち時間を次の要求にも適用する: global=$global', () async {
      var now = DateTime.utc(2026);
      final sent = <DateTime>[];
      final transport = DiscordTransport(
        now: () => now,
        client: MockClient((_) async {
          sent.add(now);
          return sent.length <= 6
              ? http.Response('{"retry_after":1,"global":$global}', 429)
              : http.Response('{}', 200);
        }),
        wait: (duration, cancel) async {
          cancel.check();
          now = now.add(duration);
        },
      )..authenticate('fixture-only');
      addTearDown(transport.dispose);
      await expectLater(
        transport.request('GET', '/users/@me', Cancellation()),
        throwsA(isA<AppFailure>().having((e) => e.status, '状態', 429)),
      );
      await transport.request(
        'GET',
        global ? '/guilds/1' : '/users/@me',
        Cancellation(),
      );
      expect(sent.length, 7);
      expect(
        sent.last.difference(sent[5]),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
    });
  }
}
