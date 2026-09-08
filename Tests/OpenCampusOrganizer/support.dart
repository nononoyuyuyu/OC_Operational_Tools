import 'dart:typed_data';
import 'package:open_campus_organizer/core/failure.dart';
import 'package:open_campus_organizer/core/ports.dart';
import 'package:open_campus_organizer/features/kakutei/domain/gateway.dart';
import 'package:open_campus_organizer/features/kakutei/domain/models.dart';
import 'package:open_campus_organizer/features/kakutei/domain/permissions.dart';

const guild = Guild('1', 'テストサーバー');
final targetRole = Role('2', '参加確定', 2);
final me = Member('9', 'bot', bot: true, roles: {'3'});
final alice = Member('10', 'alice', nickname: '同じ名前');
final bob = Member('11', 'bob', nickname: '同じ名前', roles: {'2'});
const bot = BotIdentity(
  '9',
  'Bot',
  '9',
  membersIntent: true,
  contentIntent: true,
);
final start = DateTime.utc(2026, 1, 1);
GuildContext contextWith({Role? role, List<Overwrite> overwrites = const []}) =>
    GuildContext(
      guild,
      '99',
      me,
      [
        Role('1', '@everyone', 0, permissions: viewChannel | readHistory),
        role ?? targetRole,
        Role('3', 'Bot', 10, permissions: manageRoles),
      ],
      [Channel('4', '連絡', overwrites: overwrites)],
    );
Conditions conditions({
  int minimum = 1,
  bool content = false,
  bool attachments = false,
}) => Conditions(
  guildId: '1',
  channelId: '4',
  roleId: '2',
  start: start,
  end: start.add(const Duration(days: 1)),
  minimum: minimum,
  includeContent: content,
  includeAttachments: attachments,
);
RolePlan plan({
  RoleAction action = RoleAction.add,
  List<Member>? targets,
  DateTime? at,
}) => RolePlan(
  guild: guild,
  role: targetRole,
  action: action,
  targets: targets ?? [alice, bob],
  fingerprint: 'current',
  createdAt: at ?? DateTime.now().toUtc(),
);
void noProgress(String text, int done, int? total) {}

class FakeGateway implements DiscordGateway {
  GuildContext contextValue = contextWith();
  final people = <String, Member>{alice.id: alice, bob.id: bob};
  List<List<Message>> messagePages = [[]];
  List<List<Member>> memberPages = [[]];
  int messagePage = 0;
  int memberPage = 0;
  int writes = 0;
  int contextCalls = 0;
  int memberCalls = 0;
  int membersCalls = 0;
  int? failMemberPage;
  Object? writeError;
  Object? lookupError;
  void Function()? onWrite;
  void Function()? onContext;
  void Function()? onMember;
  @override
  Future<BotIdentity> connect(String token, Cancellation cancel) async {
    cancel.check();
    return bot;
  }

  @override
  Future<List<Guild>> guilds(Cancellation cancel) async => [guild];
  @override
  Future<GuildContext> context(
    Guild guild,
    Cancellation cancel, {
    bool includeChannels = true,
  }) async {
    cancel.check();
    contextCalls++;
    onContext?.call();
    return contextValue;
  }

  @override
  Future<List<Message>> messages(
    String channelId,
    String? before,
    Cancellation cancel,
  ) async {
    cancel.check();
    return messagePage < messagePages.length ? messagePages[messagePage++] : [];
  }

  @override
  Future<Member?> member(
    String guildId,
    String userId,
    Cancellation cancel,
  ) async {
    cancel.check();
    memberCalls++;
    onMember?.call();
    if (lookupError != null) throw lookupError!;
    return people[userId];
  }

  @override
  Future<List<Member>> members(
    String guildId,
    String? after,
    Cancellation cancel,
  ) async {
    cancel.check();
    membersCalls++;
    if (memberPage == failMemberPage)
      throw const AppFailure('Intentが不足しています。', status: 403);
    return memberPage < memberPages.length ? memberPages[memberPage++] : [];
  }

  @override
  Future<void> setRole(
    String guildId,
    String userId,
    String roleId,
    RoleAction action,
    Cancellation cancel,
  ) async {
    cancel.check();
    writes++;
    onWrite?.call();
    if (writeError != null) throw writeError!;
  }

  @override
  void disconnect() {}
}

class FakeJournal implements OperationJournal {
  final reports = <OperationReport>[];
  int? failAt;
  @override
  Future<void> save(OperationReport report) async {
    if (reports.length == failAt) throw const AppFailure('保存失敗');
    reports.add(report);
  }

  @override
  Future<List<OperationReport>> load() async =>
      reports.isEmpty ? [] : [reports.last];
}

class FakeExport implements ExportSink {
  Uint8List? bytes;
  @override
  Future<String?> export(String name, Uint8List bytes) async {
    this.bytes = bytes;
    return '保存済み';
  }
}
