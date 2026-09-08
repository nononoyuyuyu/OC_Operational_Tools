import 'dart:convert';
import '../../../core/ports.dart';

class ExtractionInput {
  const ExtractionInput({
    this.start,
    this.end = '',
    this.minimum = '1',
    this.excludeBots = true,
    this.includeContent = false,
    this.includeAttachments = false,
  });
  final String? start;
  final String end, minimum;
  final bool excludeBots, includeContent, includeAttachments;

  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'minimum': minimum,
    'excludeBots': excludeBots,
    'includeContent': includeContent,
    'includeAttachments': includeAttachments,
  };
  factory ExtractionInput.fromJson(Map<String, dynamic> value) =>
      ExtractionInput(
        start: value['start'] as String?,
        end: value['end'] as String? ?? '',
        minimum: value['minimum'] as String? ?? '1',
        excludeBots: value['excludeBots'] as bool? ?? true,
        includeContent: value['includeContent'] as bool? ?? false,
        includeAttachments: value['includeAttachments'] as bool? ?? false,
      );
}

class GuildSelection {
  const GuildSelection(this.channelId, this.roleId);
  final String? channelId, roleId;
  Map<String, Object?> toJson() => {'channel': channelId, 'role': roleId};
  factory GuildSelection.fromJson(Map<String, dynamic> value) =>
      GuildSelection(value['channel'] as String?, value['role'] as String?);
}

class SavedKakuteiSettings {
  const SavedKakuteiSettings({
    this.guildId,
    this.selections = const {},
    this.input = const ExtractionInput(),
  });
  final String? guildId;
  final Map<String, GuildSelection> selections;
  final ExtractionInput input;

  SavedKakuteiSettings withInput(ExtractionInput value) => SavedKakuteiSettings(
    guildId: guildId,
    selections: selections,
    input: value,
  );
  SavedKakuteiSettings select(String guild, String? channel, String? role) =>
      SavedKakuteiSettings(
        guildId: guild,
        selections: {...selections, guild: GuildSelection(channel, role)},
        input: input,
      );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'guild': guildId,
    'input': input.toJson(),
    'selections': selections.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory SavedKakuteiSettings.fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1) throw const FormatException('設定形式を読み取れません。');
    return SavedKakuteiSettings(
      guildId: value['guild'] as String?,
      input: ExtractionInput.fromJson(value['input'] as Map<String, dynamic>),
      selections: (value['selections'] as Map<String, dynamic>).map(
        (key, entry) => MapEntry(
          key,
          GuildSelection.fromJson(entry as Map<String, dynamic>),
        ),
      ),
    );
  }
}

/// Tokenを保存せず、BotのIDごとにツールの選択値を分離する。
class KakuteiSettingsStore {
  KakuteiSettingsStore(this.store);
  final LocalStore store;
  Future<void> _pending = Future.value();
  Future<SavedKakuteiSettings?> load(String botId) async {
    await _pending.catchError((Object _) {});
    final value = await store.read('settings_$botId');
    return value == null
        ? null
        : SavedKakuteiSettings.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          );
  }

  Future<void> save(String botId, SavedKakuteiSettings value) {
    final encoded = jsonEncode(value.toJson());
    return _pending = _pending
        .catchError((Object _) {})
        .then((_) => store.write('settings_$botId', encoded));
  }
}
