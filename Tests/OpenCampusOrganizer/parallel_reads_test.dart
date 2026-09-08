import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_api.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue, reason: 'Expected asynchronous fixture state');
}

void main() {
  for (final parallel in [false, true]) {
    test('contextの独立GET: parallel=$parallel', () async {
      var active = 0, peak = 0, calls = 0;
      var measuring = false;
      final transport = DiscordTransport(
        parallelReads: parallel,
        client: MockClient((r) async {
          if (measuring) {
            calls++;
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            active--;
          }
          final Object value = switch (r.url.path) {
            '/api/v10/users/@me' => {'id': '9', 'username': 'Bot', 'bot': true},
            '/api/v10/applications/@me' => {'id': '9', 'flags': 0},
            '/api/v10/guilds/1' => {
              'name': 'fixture',
              'owner_id': '99',
              'roles': [],
            },
            '/api/v10/guilds/1/members/9' => {
              'user': {'id': '9', 'username': 'Bot'},
              'roles': [],
            },
            '/api/v10/guilds/1/channels' => [],
            _ => throw StateError('Unexpected fixture path'),
          };
          return http.Response(jsonEncode(value), 200);
        }),
      );
      addTearDown(transport.dispose);
      final api = DiscordApi(transport);
      await api.connect('fixture-only', Cancellation());
      measuring = true;
      final watch = Stopwatch()..start();
      final context = await api.context(
        const Guild('1', 'fixture'),
        Cancellation(),
      );
      watch.stop();
      expect(context.me.id, '9');
      expect(context.guild.name, 'fixture');
      expect(calls, 3);
      expect(peak, parallel ? 3 : 1);
      print(
        'HTTP_CONTEXT parallel=$parallel calls=$calls peak=$peak elapsed_us=${watch.elapsedMicroseconds}',
      );
    });
  }

  test('読取グループが完了するまで更新を送らずFIFOを維持する', () async {
    final gate = Completer<void>();
    final sent = <String>[];
    final transport = DiscordTransport(
      client: MockClient((r) async {
        sent.add('${r.method} ${r.url.path}');
        if (sent.length <= 3) await gate.future;
        return http.Response(
          r.method == 'GET' ? '{}' : '',
          r.method == 'GET' ? 200 : 204,
        );
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final batch = transport.readBatch([
      '/guilds/1',
      '/guilds/1/channels',
      '/guilds/1/members/9',
    ], Cancellation());
    final write = transport.request(
      'PUT',
      '/guilds/1/members/10/roles/2',
      Cancellation(),
    );
    final read = transport.request('GET', '/users/@me', Cancellation());
    await until(() => sent.length == 3);
    expect(sent.every((s) => s.startsWith('GET')), isTrue);
    gate.complete();
    await Future.wait<Object?>([batch, write, read]);
    expect(sent[3], startsWith('PUT'));
    expect(sent[4], 'GET /api/v10/users/@me');
  });

  test('読取の一部が失敗しても他の読取終了前に更新を開始しない', () async {
    final gate = Completer<void>();
    var reads = 0, writes = 0;
    final transport = DiscordTransport(
      client: MockClient((r) async {
        if (r.method != 'GET') {
          writes++;
          return http.Response('', 204);
        }
        reads++;
        if (r.url.path.endsWith('/channels')) await gate.future;
        return http.Response('{}', r.url.path.endsWith('/1') ? 403 : 200);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final failed = expectLater(
      transport.readBatch(['/guilds/1', '/guilds/1/channels'], Cancellation()),
      throwsA(isA<AppFailure>()),
    );
    final write = transport.request(
      'PUT',
      '/guilds/1/members/10/roles/2',
      Cancellation(),
    );
    await until(() => reads == 2);
    expect(writes, 0);
    gate.complete();
    await failed;
    await write;
    expect(writes, 1);
  });

  for (final learned in [false, true]) {
    test('同一ルート/学習済み同一バケットを直列化: learned=$learned', () async {
      var active = 0, peak = 0;
      var measuring = false;
      final transport = DiscordTransport(
        client: MockClient((r) async {
          if (measuring) {
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            active--;
          }
          return http.Response(
            '{}',
            200,
            headers: {'x-ratelimit-bucket': 'shared'},
          );
        }),
      )..authenticate('fixture-only');
      addTearDown(transport.dispose);
      final paths = learned
          ? ['/guilds/1', '/guilds/1/channels']
          : ['/guilds/1/members/10', '/guilds/1/members/11'];
      if (learned) {
        for (final path in paths) {
          await transport.request('GET', path, Cancellation());
        }
      }
      measuring = true;
      await transport.readBatch(paths, Cancellation());
      expect(peak, 1);
    });
  }

  test('並列読取の制限待ち中にglobal期限が延びたら再検査する', () async {
    var time = DateTime.utc(2026);
    final secondResponse = Completer<http.Response>();
    final waits = <Completer<void>>[];
    final counts = <String, int>{};
    final transport = DiscordTransport(
      now: () => time,
      wait: (_, cancel) {
        cancel.check();
        final gate = Completer<void>();
        waits.add(gate);
        return gate.future;
      },
      client: MockClient((r) async {
        final path = r.url.path;
        final n = counts.update(path, (n) => n + 1, ifAbsent: () => 1);
        if (n > 1) return http.Response('{}', 200);
        if (path.endsWith('/channels')) return secondResponse.future;
        return http.Response('{"global":true,"retry_after":1}', 429);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final group = transport.readBatch([
      '/guilds/1',
      '/guilds/1/channels',
    ], Cancellation());
    await until(() => waits.length == 1);
    secondResponse.complete(
      http.Response('{"global":true,"retry_after":3}', 429),
    );
    await until(() => waits.length == 2);
    time = time.add(const Duration(milliseconds: 1050));
    waits[0].complete();
    await until(() => waits.length == 3);
    expect(counts.values.every((n) => n == 1), isTrue);
    time = DateTime.utc(2026).add(const Duration(milliseconds: 3050));
    waits[1].complete();
    waits[2].complete();
    await group;
    expect(counts.values.every((n) => n == 2), isTrue);
  });

  test('並列読取でも過去1秒の40要求を超えない', () async {
    var time = DateTime.utc(2026);
    final sent = <DateTime>[];
    final transport = DiscordTransport(
      now: () => time,
      wait: (d, c) async {
        c.check();
        time = time.add(d);
      },
      client: MockClient((_) async {
        sent.add(time);
        return http.Response('{}', 200);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    for (var i = 0; i < 39; i++) {
      await transport.request('GET', '/users/@me', Cancellation());
    }
    for (var i = 0; i < 15; i++) {
      await transport.readBatch([
        '/guilds/1',
        '/guilds/1/channels',
        '/guilds/1/members/9',
      ], Cancellation());
    }
    for (final at in sent) {
      expect(
        sent
            .where(
              (s) =>
                  !s.isBefore(at) &&
                  s.isBefore(at.add(const Duration(seconds: 1))),
            )
            .length,
        lessThanOrEqualTo(40),
      );
    }
  });

  test('キューは128グループを上限とし、あふれた要求を送信しない', () async {
    final gate = Completer<void>();
    var calls = 0;
    var time = DateTime.utc(2026);
    final transport = DiscordTransport(
      now: () => time,
      wait: (d, c) async {
        c.check();
        time = time.add(d);
      },
      client: MockClient((_) async {
        calls++;
        await gate.future;
        return http.Response('{}', 200);
      }),
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    final futures = List.generate(
      129,
      (_) => transport
          .request('GET', '/users/@me', Cancellation())
          .then<Object?>((v) => v, onError: (Object e) => e),
    );
    await until(() => calls == 1);
    gate.complete();
    final results = await Future.wait(futures);
    expect(results.whereType<AppFailure>(), hasLength(1));
    expect(calls, 128);
  });

  test('待機中の取消とToken変更はグループ全体を未送信で拒否する', () async {
    for (final cancelled in [false, true]) {
      var calls = 0;
      final transport = DiscordTransport(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      )..authenticate('fixture-only');
      final cancel = Cancellation();
      final request = transport.readBatch([
        '/guilds/1',
        '/guilds/1/channels',
      ], cancel);
      if (cancelled) {
        cancel.cancel();
      } else {
        transport.authenticate('fixture-changed');
      }
      await expectLater(
        request,
        cancelled ? throwsA(isA<Cancelled>()) : throwsA(isA<AppFailure>()),
      );
      expect(calls, 0);
      transport.dispose();
    }
  });

  test('並列読取は最大3件だけを受け付ける', () {
    final transport = DiscordTransport(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(transport.dispose);
    expect(() => transport.readBatch([], Cancellation()), throwsArgumentError);
    expect(
      () => transport.readBatch(['/1', '/2', '/3', '/4'], Cancellation()),
      throwsArgumentError,
    );
  });
}
