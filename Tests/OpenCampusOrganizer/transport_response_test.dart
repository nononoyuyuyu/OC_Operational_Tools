import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/data/discord_transport.dart';

void main() {
  for (final advertised in <int?>[null, 2]) {
    test('実受信量で上限超過を停止する: Content-Length=$advertised', () async {
      var chunks = 0;
      var closed = false;
      final aborted = Completer<void>();
      Stream<List<int>> body() async* {
        try {
          for (var i = 0; i < 100; i++) {
            chunks++;
            yield List<int>.filled(16, 32);
          }
        } finally {
          closed = true;
        }
      }

      final client = _StreamClient((request) async {
        final abortable = request as http.AbortableRequest;
        unawaited(abortable.abortTrigger!.then((_) => aborted.complete()));
        return http.StreamedResponse(
          body(),
          200,
          contentLength: advertised,
        );
      });
      final transport = DiscordTransport(
        client: client,
        maxResponseBytes: 64,
      )..authenticate('fixture-only');
      addTearDown(transport.dispose);
      await expectLater(
        transport.request('GET', '/users/@me', Cancellation()),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.message, '上限エラー', contains('サイズ上限'))
              .having((e) => e.retryable, '自動再試行しない', isFalse),
        ),
      );
      await aborted.future.timeout(const Duration(seconds: 2));
      expect(chunks, 5);
      expect(closed, isTrue);
    });
  }

  test('大きいContent-Lengthは本文を取得する前に拒否する', () async {
    var chunks = 0;
    final aborted = Completer<void>();
    Stream<List<int>> body() async* {
      chunks++;
      yield [123, 125];
    }

    final transport = DiscordTransport(
      client: _StreamClient((request) async {
        final abortable = request as http.AbortableRequest;
        unawaited(abortable.abortTrigger!.then((_) => aborted.complete()));
        return http.StreamedResponse(body(), 200, contentLength: 65);
      }),
      maxResponseBytes: 64,
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await expectLater(
      transport.request('GET', '/users/@me', Cancellation()),
      throwsA(isA<AppFailure>()),
    );
    await aborted.future.timeout(const Duration(seconds: 2));
    expect(chunks, 0);
  });

  test('上限と同じUTF-8バイト数の分割応答を受理する', () async {
    final bytes = utf8.encode('{"name":"日本語"}');
    final transport = DiscordTransport(
      client: _StreamClient(
        (_) async => http.StreamedResponse(
          Stream.fromIterable(bytes.map((byte) => [byte])),
          200,
          contentLength: bytes.length,
        ),
      ),
      maxResponseBytes: bytes.length,
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    expect(
      await transport.request('GET', '/users/@me', Cancellation()),
      {'name': '日本語'},
    );
  });

  test('更新応答の超過は未確認とし再送せず、次の要求を妨げない', () async {
    var calls = 0;
    final transport = DiscordTransport(
      client: _StreamClient(
        (_) async => ++calls == 1
            ? http.StreamedResponse(
                Stream.value(utf8.encode('秘密' * 30)),
                200,
              )
            : http.StreamedResponse(Stream.value([123, 125]), 200),
      ),
      maxResponseBytes: 64,
    )..authenticate('fixture-only');
    addTearDown(transport.dispose);
    await expectLater(
      transport.request('PUT', '/guilds/1/members/2/roles/3', Cancellation()),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.uncertain, '送信済みの結果は未確認', isTrue)
            .having((e) => e.retryable, '自動再試行しない', isFalse)
            .having((e) => e.message, '本文を漏らさない', isNot(contains('秘密'))),
      ),
    );
    expect(calls, 1);
    expect(
      await transport.request('GET', '/users/@me', Cancellation()),
      isEmpty,
    );
    expect(calls, 2);
  });

  test('無効な応答上限を拒否する', () {
    for (final limit in [0, -1]) {
      final client = _StreamClient(
        (_) async => http.StreamedResponse(const Stream.empty(), 204),
      );
      addTearDown(client.close);
      expect(
        () => DiscordTransport(client: client, maxResponseBytes: limit),
        throwsArgumentError,
      );
    }
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}
