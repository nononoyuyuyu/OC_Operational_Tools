import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_campus_organizer/app/oco_app.dart';
import 'package:open_campus_organizer/core/platform/memory_store.dart';
import 'package:open_campus_organizer/features/kakutei/application/kakutei_controller.dart';
import 'package:open_campus_organizer/features/kakutei/data/saved_settings.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/features/kakutei/kakutei_module.dart';
import 'support.dart';

class SettingsGateway extends FakeGateway {
  String identity = '9';
  bool removed = false;
  @override
  Future<BotIdentity> connect(String token, Cancellation cancel) async =>
      BotIdentity(
        identity,
        'fixture',
        identity,
        membersIntent: true,
        contentIntent: true,
      );
  @override
  Future<List<Guild>> guilds(Cancellation cancel) async => [
    guild,
    const Guild('20', '第二サーバー'),
  ];
  @override
  Future<GuildContext> context(
    Guild chosen,
    Cancellation cancel, {
    bool includeChannels = true,
  }) async {
    final base = contextWith();
    return GuildContext(
      chosen,
      '99',
      me,
      [
        Role(
          chosen.id,
          '@everyone',
          0,
          permissions: base.roles.first.permissions,
        ),
        ...base.roles.skip(1),
        if (!removed) Role('7', 'スタッフ', 1),
      ],
      [Channel('4', '連絡'), if (!removed) Channel('6', '予備連絡')],
    );
  }
}

KakuteiController create(
  MemoryStore credentials,
  MemoryStore local, {
  SettingsGateway? gateway,
}) => KakuteiController(
  gateway: gateway ?? SettingsGateway(),
  credentials: credentials,
  journal: FakeJournal(),
  exports: FakeExport(),
  settingsStore: KakuteiSettingsStore(local),
);

const input = ExtractionInput(
  start: '2026/09/01 09:30',
  end: '2026/09/07 18:45',
  minimum: '3',
  excludeBots: false,
  includeContent: true,
  includeAttachments: true,
);

Future<void> prepare(KakuteiController c) async {
  await c.connect('fixture-only', remember: true);
  await c.selectGuild('20');
  c.selectChannel('6');
  c.selectRole('7');
  c.updateInput(input);
  await c.pendingSettings;
}

void main() {
  test('保存済みTokenで起動すると前回のサーバー・チャンネル・ロール・抽出条件を復元する', () async {
    final credentials = MemoryStore(), local = MemoryStore();
    final first = create(credentials, local);
    await prepare(first);
    first.dispose();
    final next = create(credentials, local);
    await next.initialize();
    expect(next.connected, isTrue);
    expect(next.selectedGuild?.id, '20');
    expect(next.channelId, '6');
    expect(next.roleId, '7');
    expect(next.settings.input.toJson(), input.toJson());
    expect((await local.read('settings_9'))!.contains('fixture-only'), isFalse);
    next.dispose();
  });

  test('サーバーを切り替えて戻ると、そのサーバーで選んだチャンネルとロールに戻る', () async {
    final c = create(MemoryStore(), MemoryStore());
    await prepare(c);
    await c.selectGuild('1');
    expect(c.channelId, '4');
    await c.selectGuild('20');
    expect(c.channelId, '6');
    expect(c.roleId, '7');
    await c.pendingSettings;
    c.dispose();
  });

  test('保存しない接続と別Botの接続では前のBotの設定を流用しない', () async {
    final credentials = MemoryStore(), local = MemoryStore();
    final first = create(credentials, local);
    await prepare(first);
    final before = await local.read('settings_9');
    await first.startDemo();
    first.updateInput(const ExtractionInput(minimum: '8'));
    await first.pendingSettings;
    expect(await local.read('settings_9'), before);
    first.dispose();
    final second = create(credentials, local);
    await second.connect('fixture-only', remember: false);
    expect(second.selectedGuild?.id, '1');
    expect(second.settings.input.minimum, '1');
    second.updateInput(const ExtractionInput(minimum: '7'));
    await second.pendingSettings;
    expect(await local.read('settings_9'), before);
    second.dispose();
    final third = create(
      credentials,
      local,
      gateway: SettingsGateway()..identity = '123',
    );
    await third.connect('another-fixture', remember: true);
    expect(third.selectedGuild?.id, '1');
    expect(third.roleId, '2');
    await third.pendingSettings;
    expect(await local.read('settings_9'), before);
    third.dispose();
  });

  test('削除されたチャンネルやロールを別の対象に自動で置き換えない', () async {
    final credentials = MemoryStore(), local = MemoryStore();
    final first = create(credentials, local);
    await prepare(first);
    first.dispose();
    final next = create(
      credentials,
      local,
      gateway: SettingsGateway()..removed = true,
    );
    await next.initialize();
    expect(next.selectedGuild?.id, '20');
    expect(next.channelId, isNull);
    expect(next.roleId, isNull);
    expect(next.additionPlan, throwsA(isA<AppFailure>()));
    next.dispose();
  });

  test('破損した設定は接続を妨げず、読み込めないデータを自動で上書きしない', () async {
    final credentials = MemoryStore(), local = MemoryStore();
    await credentials.save('fixture-only');
    await local.write('settings_9', 'broken fixture');
    final c = create(credentials, local);
    await c.initialize();
    await c.pendingSettings;
    expect(c.connected, isTrue);
    expect(c.error, contains('設定を読み込めません'));
    expect(await local.read('settings_9'), 'broken fixture');
    c.dispose();
  });

  testWidgets('保存した抽出条件を入力欄とチェックボックスにも復元する', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final credentials = MemoryStore(), local = MemoryStore();
    final first = create(credentials, local);
    await prepare(first);
    first.dispose();
    final c = create(credentials, local);
    await tester.pumpWidget(OcoApp(modules: [KakuteiModule(c)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定ロール').first);
    await tester.pumpAndSettle();
    TextField field(String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label));
    expect(field('開始日時（JST）').controller!.text, input.start);
    expect(field('終了日時（任意）').controller!.text, input.end);
    expect(field('最小投稿数').controller!.text, '3');
    final checks = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(checks.map((check) => check.value), [false, true, true]);
    await tester.enterText(find.widgetWithText(TextField, '最小投稿数'), '5');
    await tester.pumpAndSettle();
    await c.pendingSettings;
    expect((await KakuteiSettingsStore(local).load('9'))!.input.minimum, '5');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
