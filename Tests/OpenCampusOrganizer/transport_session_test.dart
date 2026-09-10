import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';

void main() {
  for (final parallel in [false, true]) {
    test('再接続で古い読取グループを拒否する: parallel=$parallel', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final transport = DiscordTransport(
        parallelReads: parallel,
        client: MockClient((_) async {
          calls++;
          if (!started.isCompleted) started.complete();
          await release.future;
          return http.Response('{}', 200);
        }),
      )..authenticate('fixture-only');
      addTearDown(transport.dispose);
      final group = transport.readBatch([
        '/guilds/1',
        '/guilds/1/roles',
      ], Cancellation());
      final checked = expectLater(group, throwsA(isA<AppFailure>()));
      await started.future;
      await Future<void>.delayed(Duration.zero);
      final before = calls;
      transport.disconnect();
      transport.authenticate('fixture-only');
      release.complete();
      await checked;
      expect(calls, before);
      expect(calls, parallel ? 2 : 1);
    });
  }

  test('送信済みの更新の成功は再接続や中止で未処理へ戻さない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        started.complete();
        await release.future;
        return http.Response('', 204);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final cancel = Cancellation();
    final request = transport.request(
      'PUT',
      '/guilds/1/members/2/roles/3',
      cancel,
    );
    await started.future;
    cancel.cancel();
    transport.disconnect();
    transport.authenticate('fixture-only');
    release.complete();
    expect(await request, isNull);
    expect(calls, 1);
  });

  test('待機中に呼出し元がクエリを変更しても送信条件を変えない', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final queries = <Map<String, String>>[];
    final transport = DiscordTransport(
      client: MockClient((request) async {
        queries.add(request.url.queryParameters);
        if (queries.length == 1) {
          started.complete();
          await release.future;
        }
        return http.Response('{}', 200);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final first = transport.request('GET', '/users/@me', Cancellation());
    await started.future;
    final query = {'before': '123', 'limit': '100'};
    final next = transport.request(
      'GET',
      '/channels/1/messages',
      Cancellation(),
      query: query,
    );
    query['before'] = '999';
    release.complete();
    await Future.wait([first, next]);
    expect(queries.last, {'before': '123', 'limit': '100'});
  });

  test('破棄した接続は再認証できず待機要求も送らない', () async {
    var calls = 0;
    final transport = DiscordTransport(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    )..authenticate('fixture-only');
    final request = transport.request('GET', '/users/@me', Cancellation());
    transport.dispose();
    transport.dispose();
    expect(
      () => transport.authenticate('fixture-only'),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(request, throwsA(isA<AppFailure>()));
    expect(calls, 0);
  });
}
