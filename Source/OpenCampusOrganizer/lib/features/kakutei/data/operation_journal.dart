import 'dart:convert';
import '../../../core/failure.dart';
import '../../../core/ports.dart';
import '../domain/gateway.dart';
import '../domain/models.dart';
import '../domain/csv.dart';
import '../domain/operation_summary.dart';

class StoredOperationJournal implements IndexedOperationJournal {
  StoredOperationJournal(this.store);
  final LocalStore store;
  // Controllerが同時に実行する操作は1件。完了時には詳細を解放する。
  OperationReport? _last;
  Future<void> _writes = Future.value();
  List<_IndexEntry>? _index;
  bool _autoSaveCsv = false, _optionsLoaded = false;
  @override
  bool get autoSaveCsv => _autoSaveCsv;

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _loadOptions() async {
    if (_optionsLoaded) return;
    final text = await store.read('journal_options');
    if (text != null) {
      try {
        final data = jsonDecode(text) as Map<String, dynamic>;
        if (data['schema'] != 1 || data['autoSaveCsv'] is! bool) {
          throw const FormatException();
        }
        _autoSaveCsv = data['autoSaveCsv'] as bool;
      } catch (_) {
        throw const AppFailure('履歴の保存設定を読み取れませんでした。保存データを確認してください。');
      }
    }
    _optionsLoaded = true;
  }

  @override
  Future<void> setAutoSaveCsv(bool enabled) => _serial(() async {
    await _loadOptions();
    await store.write(
      'journal_options',
      jsonEncode({'schema': 1, 'autoSaveCsv': enabled}),
    );
    _autoSaveCsv = enabled;
  });

  Map<String, Object?> _member(Member m) => {
    'id': m.id,
    'username': m.username,
    'globalName': m.globalName,
    'nickname': m.nickname,
    'bot': m.bot,
    'present': m.present,
    'roles': m.roles.toList(),
  };
  Member _decodeMember(Map<String, dynamic> m) => Member(
    m['id'],
    m['username'],
    globalName: m['globalName'],
    nickname: m['nickname'],
    bot: m['bot'],
    present: m['present'],
    roles: (m['roles'] as List).cast<String>().toSet(),
  );
  Map<String, Object?> _row(OperationRow r) => {
    'member': _member(r.member),
    'outcome': r.outcome.name,
    'reason': r.reason,
  };
  OperationRow _decodeRow(Map<String, dynamic> r) => OperationRow(
    _decodeMember(r['member']),
    Outcome.values.byName(r['outcome']),
    r['reason'],
  );

  @override
  Future<void> save(OperationReport report) => _serial(() async {
    try {
      await _loadOptions();
      await _ensureIndex();
      await _save(report);
    } catch (_) {
      // 追記が途中で失敗した場合、次回は原子置換で正しいスナップショットから再開する。
      _last = null;
      _index = null;
      rethrow;
    }
  });

  Future<void> _save(OperationReport report) async {
    final previous = _last?.id == report.id ? _last : null;
    if (previous == null) {
      final p = report.plan;
      final header = {
        'schema': 1,
        'id': report.id,
        'guild': {'id': p.guild.id, 'name': p.guild.name},
        'role': {
          'id': p.role.id,
          'name': p.role.name,
          'position': p.role.position,
          'permissions': p.role.permissions.toString(),
          'managed': p.role.managed,
        },
        'action': p.action.name,
        'fingerprint': p.fingerprint,
        'createdAt': p.createdAt.toIso8601String(),
        'startedAt': report.startedAt.toIso8601String(),
        'finishedAt': report.finishedAt?.toIso8601String(),
        'rows': report.rows.map(_row).toList(),
      };
      await store.write('operation_${report.id}', '${jsonEncode(header)}\n');
    } else {
      final updates = <Map<String, Object?>>[];
      for (final i in report.rows.changedIndexes(previous.rows)) {
        updates.add({'index': i, 'row': _row(report.rows[i])});
      }
      // 一行が書き終わる前に中断された場合、復元時はその行を採用しない。
      await store.append(
        'operation_${report.id}',
        '${jsonEncode({'updates': updates, 'finishedAt': report.finishedAt?.toIso8601String()})}\n',
      );
    }
    _last = report.finishedAt == null ? report : null;
    if (previous == null || report.finishedAt != null) {
      await _writeSummary(OperationSummary.fromReport(report));
      _index!.removeWhere((entry) => entry.id == report.id);
      _index!.add(
        _IndexEntry(report.id, report.startedAt, report.finishedAt != null),
      );
      _sortIndex();
      await _writeIndex();
    }
    if (report.finishedAt != null) {
      if (_autoSaveCsv) {
        await store.write(
          'result_${report.id}_csv',
          utf8.decode(operationsCsv(report)),
        );
      }
    }
  }

  @override
  Future<List<OperationReport>> load() => _serial(() async {
    final result = <OperationReport>[];
    for (final key in await store.keys('operation_')) {
      final report = await _readReport(key.substring('operation_'.length));
      if (report != null) result.add(report);
    }
    result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return result;
  });

  @override
  Future<OperationReport?> find(String id) => _serial(() => _readReport(id));

  Future<OperationReport?> _readReport(String id) async {
    final text = await store.read('operation_$id');
    if (text == null) return null;
    try {
      final lines = text.split('\n')..removeLast();
      if (lines.isEmpty) throw const FormatException();
      final head = jsonDecode(lines.first) as Map<String, dynamic>;
      if (head['schema'] != 1 || head['id'] != id) {
        throw const FormatException();
      }
      final rows = (head['rows'] as List).map((r) => _decodeRow(r)).toList();
      final savedFinishedAt = head['finishedAt'] as String?;
      DateTime? finishedAt = savedFinishedAt == null
          ? null
          : DateTime.parse(savedFinishedAt);
      for (final line in lines.skip(1)) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        for (final update in event['updates'] as List) {
          rows[update['index'] as int] = _decodeRow(update['row']);
        }
        if (event['finishedAt'] != null) {
          finishedAt = DateTime.parse(event['finishedAt']);
        }
      }
      final r = head['role'];
      final plan = RolePlan(
        guild: Guild(head['guild']['id'], head['guild']['name']),
        role: Role(
          r['id'],
          r['name'],
          r['position'],
          permissions: BigInt.parse(r['permissions']),
          managed: r['managed'],
        ),
        action: RoleAction.values.byName(head['action']),
        targets: rows.map((r) => r.member).toList(),
        fingerprint: head['fingerprint'],
        createdAt: DateTime.parse(head['createdAt']),
      );
      return OperationReport(
        id: head['id'],
        plan: plan,
        rows: rows
            .map(
              (r) => r.outcome == Outcome.inFlight
                  ? OperationRow(
                      r.member,
                      Outcome.uncertain,
                      'アプリ終了前の結果を確認できません。Discordで確認してください。',
                    )
                  : r.outcome == Outcome.pending
                  ? OperationRow(
                      r.member,
                      Outcome.unprocessed,
                      'アプリ終了時に未処理でした。',
                    )
                  : r,
            )
            .toList(),
        startedAt: DateTime.parse(head['startedAt']),
        finishedAt: finishedAt,
      );
    } catch (_) {
      throw const AppFailure('操作履歴の一部を読み取れませんでした。保存データを保管し、管理者に確認してください。');
    }
  }

  void _sortIndex() => _index!.sort((a, b) {
    final order = b.at.compareTo(a.at);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  Future<void> _writeIndex() => store.write(
    'history_index',
    jsonEncode({
      'schema': 1,
      'entries': [
        for (final entry in _index!)
          {
            'id': entry.id,
            'at': entry.at.toIso8601String(),
            'finished': entry.finished,
          },
      ],
    }),
  );
  Future<void> _writeSummary(OperationSummary summary) => store.write(
    'history_summary_${summary.id}',
    jsonEncode({
      'schema': 1,
      'id': summary.id,
      'guild': {'id': summary.guild.id, 'name': summary.guild.name},
      'role': {'id': summary.role.id, 'name': summary.role.name},
      'action': summary.action.name,
      'startedAt': summary.startedAt.toIso8601String(),
      'finishedAt': summary.finishedAt?.toIso8601String(),
      'counts': summary.counts,
    }),
  );

  // 索引は派生データ。旧版の移行・索引破損時のみ原本を1件ずつ再生して再生成する。
  Future<void> _ensureIndex() async {
    if (_index != null) return;
    final ids = (await store.keys(
      'operation_',
    )).map((key) => key.substring('operation_'.length)).toSet();
    final text = await store.read('history_index');
    List<_IndexEntry>? entries;
    if (text != null) {
      try {
        final data = jsonDecode(text) as Map<String, dynamic>;
        if (data['schema'] != 1) throw const FormatException();
        entries = (data['entries'] as List)
            .map(
              (item) => _IndexEntry(
                item['id'] as String,
                DateTime.parse(item['at'] as String),
                item['finished'] as bool,
              ),
            )
            .toList();
        if (entries.length != ids.length ||
            entries.map((e) => e.id).toSet().length != ids.length ||
            !entries.every((e) => ids.contains(e.id))) {
          entries = null;
        }
      } catch (_) {
        entries = null;
      }
    }
    final rebuild = entries == null;
    entries ??= [
      for (final id in ids)
        _IndexEntry(id, DateTime.fromMillisecondsSinceEpoch(0), false),
    ];
    final restored = <_IndexEntry>[];
    for (final entry in entries) {
      // 原本→要約→索引の間に終了しても、未完了記録は起動時に必ず原本で照合する。
      if (rebuild || !entry.finished) {
        final report = await _readReport(entry.id);
        if (report == null) throw const AppFailure('操作履歴の原本が見つかりません。');
        await _writeSummary(OperationSummary.fromReport(report));
        restored.add(
          _IndexEntry(report.id, report.startedAt, report.finishedAt != null),
        );
      } else {
        restored.add(entry);
      }
    }
    _index = restored;
    _sortIndex();
    if (rebuild || entries.any((entry) => !entry.finished)) {
      try {
        await _writeIndex();
      } catch (_) {
        _index = null;
        rethrow;
      }
    }
  }

  Future<OperationSummary> _readSummary(_IndexEntry entry) async {
    final active = _last;
    if (active?.id == entry.id) return OperationSummary.fromReport(active!);
    final text = await store.read('history_summary_${entry.id}');
    if (text != null) {
      try {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final counts = (data['counts'] as List).cast<int>();
        final at = DateTime.parse(data['startedAt'] as String);
        final finished = data['finishedAt'] == null
            ? null
            : DateTime.parse(data['finishedAt'] as String);
        if (data['schema'] != 1 ||
            data['id'] != entry.id ||
            at != entry.at ||
            (finished != null) != entry.finished ||
            counts.length != Outcome.values.length ||
            counts.any((v) => v < 0)) {
          throw const FormatException();
        }
        return OperationSummary(
          id: entry.id,
          guild: Guild(data['guild']['id'], data['guild']['name']),
          role: Role(data['role']['id'], data['role']['name'], 0),
          action: RoleAction.values.byName(data['action']),
          startedAt: at,
          finishedAt: finished,
          counts: counts,
        );
      } catch (_) {
        /* 派生要約だけの破損は原本から回復する。 */
      }
    }
    final report = await _readReport(entry.id);
    if (report == null) throw const AppFailure('操作履歴の原本が見つかりません。');
    final summary = OperationSummary.fromReport(report);
    await _writeSummary(summary);
    return summary;
  }

  @override
  Future<OperationHistoryPage> summaries({int offset = 0, int limit = 30}) =>
      _serial(() async {
        if (offset < 0 || limit < 1 || limit > 100) {
          throw ArgumentError('履歴の取得範囲が正しくありません。');
        }
        await _loadOptions();
        await _ensureIndex();
        final items = <OperationSummary>[];
        for (final entry in _index!.skip(offset).take(limit)) {
          items.add(await _readSummary(entry));
        }
        return OperationHistoryPage(items, _index!.length);
      });
}

class _IndexEntry {
  const _IndexEntry(this.id, this.at, this.finished);
  final String id;
  final DateTime at;
  final bool finished;
}
