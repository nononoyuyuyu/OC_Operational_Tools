import '../../../core/failure.dart';
import 'models.dart';

final administrator = BigInt.one << 3;
final viewChannel = BigInt.one << 10;
final readHistory = BigInt.one << 16;
final manageRoles = BigInt.one << 28;
final _all = (BigInt.one << 64) - BigInt.one;
bool hasPermission(BigInt permissions, BigInt flag) =>
    (permissions & flag) == flag;

BigInt guildPermissions(GuildContext context) {
  if (context.ownerId == context.me.id) return _all;
  var result = context.roles
      .where((r) => r.id == context.guild.id || context.me.roles.contains(r.id))
      .fold(BigInt.zero, (value, role) => value | role.permissions);
  if (hasPermission(result, administrator)) result = _all;
  return result;
}

BigInt channelPermissions(GuildContext context, Channel channel) {
  var result = guildPermissions(context);
  if (hasPermission(result, administrator)) return _all;
  for (final o in channel.overwrites.where(
    (o) => o.type == 0 && o.id == context.guild.id,
  )) {
    result = (result & ~o.deny) | o.allow;
  }
  var deny = BigInt.zero;
  var allow = BigInt.zero;
  for (final o in channel.overwrites.where(
    (o) =>
        o.type == 0 &&
        o.id != context.guild.id &&
        context.me.roles.contains(o.id),
  )) {
    deny |= o.deny;
    allow |= o.allow;
  }
  result = (result & ~deny) | allow;
  for (final o in channel.overwrites.where(
    (o) => o.type == 1 && o.id == context.me.id,
  )) {
    result = (result & ~o.deny) | o.allow;
  }
  return result;
}

String? roleBlockReason(GuildContext context, Role role) {
  if (role.id == context.guild.id) return '@everyoneは操作できません。';
  if (role.managed) return '外部連携が管理するロールは操作できません。';
  if (hasPermission(role.permissions, administrator)) {
    return '管理者権限を持つロールは操作できません。';
  }
  if (!hasPermission(guildPermissions(context), manageRoles)) {
    return 'Botに「ロールの管理」権限がありません。';
  }
  final top = context.roles
      .where((r) => context.me.roles.contains(r.id))
      .fold(0, (value, role) => value > role.position ? value : role.position);
  if (role.position >= top) return 'Botのロールを対象ロールより上に移動してください。';
  return null;
}

void requireReadable(GuildContext context, String channelId) {
  final channel = context.channel(channelId);
  if (channel.type != 0) throw const AppFailure('通常のテキストチャンネルを選択してください。');
  final permissions = channelPermissions(context, channel);
  if (!hasPermission(permissions, viewChannel) ||
      !hasPermission(permissions, readHistory)) {
    throw const AppFailure('Botに「チャンネルを見る」「メッセージ履歴を読む」権限を許可してください。');
  }
}

void requireManageable(GuildContext context, String roleId) {
  final reason = roleBlockReason(context, context.role(roleId));
  if (reason != null) throw AppFailure(reason);
}
