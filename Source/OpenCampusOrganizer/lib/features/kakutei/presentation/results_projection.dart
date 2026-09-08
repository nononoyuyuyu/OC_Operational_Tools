import '../domain/models.dart';

/// 不変の抽出結果と検索語に対応する、遅延評価された画面用の一覧。
/// 進捗や配色の変更では再生成せず、非表示の一覧は検索しない。
class ResultsProjection {
  ResultsProjection(this.result, {String search = ''})
    : search = search.trim().toLowerCase();
  final Extraction result;
  final String search;

  late final int adding = result.users
      .where((user) => !user.hasRole && user.member.present)
      .length;

  late final List<Activity> users = search.isEmpty
      ? result.users
      : List.unmodifiable(
          result.users.where(
            (user) =>
                user.member.displayName.toLowerCase().contains(search) ||
                user.member.id.contains(search) ||
                user.member.username.toLowerCase().contains(search),
          ),
        );

  late final List<Message> messages = search.isEmpty
      ? result.messages
      : List.unmodifiable(
          result.messages.where(
            (message) =>
                message.author.displayName.toLowerCase().contains(search) ||
                message.author.id.contains(search) ||
                message.content.toLowerCase().contains(search),
          ),
        );
}
