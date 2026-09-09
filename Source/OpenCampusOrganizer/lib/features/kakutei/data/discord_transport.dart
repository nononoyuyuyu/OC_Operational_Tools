import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/failure.dart';
import 'bounded_response.dart';

class DiscordTransport {
  DiscordTransport({
    http.Client? client,
    Future<void> Function(Duration, Cancellation)? wait,
    DateTime Function()? now,
    this.parallelReads = true,
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _wait = wait ?? ((d, c) => c.wait(d)),
       _now = now ?? DateTime.now {
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
  }
  final http.Client _client;
  final Future<void> Function(Duration, Cancellation) _wait;
  final bool parallelReads;
  final int maxResponseBytes;
  String? _token;
  int _session = 0;
  bool _disposed = false;
  Future<void> _tail = Future.value();
  int _pending = 0;
  final DateTime Function() _now;
  final _routes = <String, String>{};
  final _readyAt = <String, DateTime>{};
  final _recent = <DateTime>[];
  DateTime? _globalReadyAt;
  static final _numericSegment = RegExp(r'^\d+$');

  String _route(String method, String path) {
    final parts = path.split('/');
    return '$method ${[for (var i = 0; i < parts.length; i++) i != 2 && _numericSegment.hasMatch(parts[i]) ? ':id' : parts[i]].join('/')}';
  }

  void _block(String key, Duration delay) {
    final until = _now().add(delay);
    if (_readyAt[key] == null || until.isAfter(_readyAt[key]!)) {
      _readyAt[key] = until;
    }
  }

  Future<void> _throttle(
    String route,
    Cancellation cancel, {
    bool recheck = false,
  }) async {
    while (true) {
      final now = _now();
      _recent.removeWhere(
        (at) => now.difference(at) >= const Duration(seconds: 1),
      );
      var ready = now;
      for (final candidate in [
        _readyAt[_routes[route] ?? route], _globalReadyAt,
        // 全体上限に余裕を持たせ、過去1秒で40回までにする。
        if (_recent.length >= 40)
          _recent[_recent.length - 40].add(const Duration(seconds: 1)),
      ]) {
        if (candidate != null && candidate.isAfter(ready)) ready = candidate;
      }
      if (ready.isAfter(now)) {
        await _wait(ready.difference(now), cancel);
        cancel.check();
        // Another reader can extend a bucket/global deadline while we wait.
        if (recheck) continue;
      }
      cancel.check();
      // No await between admission and reservation: readers cannot consume
      // the same last slot in the rolling window.
      _recent.add(_now());
      return;
    }
  }

  void authenticate(String token) {
    if (_disposed) throw const AppFailure('終了済みの接続は使用できません。');
    final value = token.trim();
    if (value.isEmpty || value.length > 512 || RegExp(r'\s').hasMatch(value)) {
      throw const AppFailure('Bot Tokenを入力してください。');
    }
    _session++;
    _token = value;
  }

  void disconnect() {
    _session++;
    _token = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _client.close();
  }

  void _requireSession(String token, int session) {
    if (_disposed || _session != session || _token != token) {
      throw const AppFailure('接続が変更されました。再接続してください。');
    }
  }

  Future<T> _enqueue<T>(
    Cancellation cancel,
    Future<T> Function(String token, int session) run,
  ) {
    if (_pending >= 128) {
      return Future<T>.error(
        const AppFailure('待機中の要求が多すぎます。処理の終了後に再実行してください。'),
      );
    }
    _pending++;
    final result = Completer<T>();
    final tokenAtEnqueue = _token;
    final session = _session;
    _tail = _tail.then((_) async {
      try {
        cancel.check();
        if (tokenAtEnqueue == null) {
          throw const AppFailure('Discordに接続してください。');
        }
        _requireSession(tokenAtEnqueue, session);
        result.complete(await run(tokenAtEnqueue, session));
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _pending--;
      }
    });
    return result.future;
  }

  Future<Object?> request(
    String method,
    String path,
    Cancellation cancel, {
    Map<String, String>? query,
  }) {
    final snapshot = query == null
        ? null
        : Map<String, String>.unmodifiable(query);
    return _enqueue(
      cancel,
      (token, session) => _send(method, path, snapshot, cancel, token, session),
    );
  }

  /// An explicit, bounded read group; normal requests and all writes remain
  /// FIFO barriers. A failed group drains every reader before releasing it.
  Future<List<Object?>> readBatch(List<String> paths, Cancellation cancel) {
    if (paths.isEmpty || paths.length > 3) {
      throw ArgumentError.value(paths.length, 'paths', 'Expected 1 to 3 GETs');
    }
    final snapshot = List<String>.unmodifiable(paths);
    return _enqueue(cancel, (token, session) async {
      final buckets = snapshot.map((path) {
        final route = _route('GET', path);
        return _routes[route] ?? route;
      }).toSet();
      // Unknown aliases can only be learned from responses. Once learned,
      // conservatively serialize the whole small group sharing a bucket.
      if (!parallelReads || buckets.length != snapshot.length) {
        final values = <Object?>[];
        for (final path in snapshot) {
          values.add(await _send('GET', path, null, cancel, token, session));
        }
        return values;
      }
      return Future.wait([
        for (final path in snapshot)
          _send(
            'GET',
            path,
            null,
            cancel,
            token,
            session,
            concurrentRead: true,
          ),
      ]);
    });
  }

  Future<Object?> _send(
    String method,
    String path,
    Map<String, String>? query,
    Cancellation cancel,
    String token,
    int session, {
    bool concurrentRead = false,
  }) async {
    final mutation = method != 'GET';
    final route = _route(method, path);
    for (var attempt = 0; attempt < 6; attempt++) {
      _requireSession(token, session);
      await _throttle(route, cancel, recheck: concurrentRead);
      cancel.check();
      _requireSession(token, session);
      final abort = Completer<void>();
      void abortRequest() {
        if (!abort.isCompleted) abort.complete();
      }

      final request =
          http.AbortableRequest(
              method,
              Uri.https('discord.com', '/api/v10$path', query),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bot $token',
              'User-Agent':
                  'DiscordBot (https://github.com/nononoyuyuyu/OC_Operational_Tools, 0.4.6)',
              if (mutation)
                'X-Audit-Log-Reason': Uri.encodeComponent(
                  'Open Campus Organizerから${method == 'PUT' ? '付与' : '解除'}',
                ),
            });
      late http.Response response;
      try {
        response = await _client
            .send(request)
            .then(
              (response) => readBoundedResponse(
                response,
                maxBytes: maxResponseBytes,
                abort: abortRequest,
              ),
            )
            .timeout(
              const Duration(seconds: 25),
              onTimeout: () {
                abortRequest();
                throw TimeoutException('request timeout');
              },
            );
      } on ResponseTooLarge {
        throw AppFailure(
          'Discordの応答がサイズ上限を超えたため停止しました。取得条件を確認してください。',
          uncertain: mutation,
        );
      } catch (_) {
        // レスポンス・HTTP例外には機密情報が含まれ得るため、そのまま表示・保存しない。
        throw AppFailure(
          mutation
              ? '通信が途切れたため結果を確認できません。Discordの状態を確認してください。'
              : 'Discordに接続できません。ネットワークを確認してください。',
          uncertain: mutation,
          retryable: true,
        );
      }
      // 古い読取結果は破棄する。送信済みの更新の成功応答は記録のため保持する。
      if (!mutation) _requireSession(token, session);
      final currentSession = _session == session && _token == token;
      Object? data;
      if (response.bodyBytes.isNotEmpty) {
        try {
          data = jsonDecode(utf8.decode(response.bodyBytes));
        } catch (_) {
          /* 本文を表示しない */
        }
      }
      var bucket = _routes[route] ?? route;
      final bucketId = response.headers['x-ratelimit-bucket'];
      if (currentSession && bucketId != null) {
        final parts = path.split('/');
        final major =
            parts.length > 2 && (parts[1] == 'guilds' || parts[1] == 'channels')
            ? '${parts[1]}/${parts[2]}'
            : 'other';
        final learned = '$major:$bucketId';
        final previous = _readyAt[bucket];
        if (previous != null &&
            (_readyAt[learned] == null ||
                previous.isAfter(_readyAt[learned]!))) {
          _readyAt[learned] = previous;
        }
        bucket = learned;
        _routes[route] = bucket;
      }
      if (response.statusCode == 429) {
        _requireSession(token, session);
        final raw = data is Map ? data['retry_after'] : null;
        final bodySeconds = raw is num ? raw.toDouble() : 0.0;
        final headerSeconds =
            double.tryParse(response.headers['retry-after'] ?? '') ?? 0.0;
        final seconds = bodySeconds > headerSeconds
            ? bodySeconds
            : headerSeconds;
        if (!seconds.isFinite || seconds <= 0 || seconds > 300) {
          throw const AppFailure(
            'Discordの利用制限に達しました。時間をおいて再度確認してください。',
            status: 429,
          );
        }
        final delay = Duration(milliseconds: (seconds * 1000).ceil() + 50);
        if (data is Map && data['global'] == true ||
            response.headers['x-ratelimit-global'] == 'true' ||
            response.headers['x-ratelimit-scope'] == 'global') {
          final until = _now().add(delay);
          if (_globalReadyAt == null || until.isAfter(_globalReadyAt!)) {
            _globalReadyAt = until;
          }
        } else {
          _block(bucket, delay);
        }
        // この要求の再試行を終えても、次の要求に対する制限は消さない。
        if (attempt == 5) {
          throw AppFailure(
            'Discordの利用制限に達しました。時間をおいて再度確認してください。',
            status: 429,
            retryable: true,
            retryAfter: delay,
          );
        }
        continue;
      }
      if (currentSession && response.headers['x-ratelimit-remaining'] == '0') {
        final seconds =
            double.tryParse(
              response.headers['x-ratelimit-reset-after'] ?? '',
            ) ??
            1;
        if (seconds.isFinite && seconds > 0) {
          _block(bucket, Duration(milliseconds: (seconds * 1000).ceil() + 50));
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (method == 'GET') {
          cancel.check();
          _requireSession(token, session);
          if (data == null) throw const AppFailure('Discordの応答を読み取れませんでした。');
        }
        return data;
      }
      throw AppFailure(
        switch (response.statusCode) {
          401 => 'Bot Tokenが無効です。設定から再接続してください。',
          403 => 'Discordへのアクセスが拒否されました。Botの権限とIntentを確認してください。',
          404 => 'サーバー、チャンネル、ロールまたはメンバーが見つかりません。',
          >= 500 => 'Discordで一時的なエラーが発生しました。時間をおいて確認してください。',
          _ => 'Discordの要求を完了できませんでした。一覧を更新して再確認してください。',
        },
        status: response.statusCode,
        uncertain: mutation && response.statusCode >= 500,
        retryable: response.statusCode >= 500,
      );
    }
    throw const AppFailure('時間をおいて再度確認してください。');
  }
}
