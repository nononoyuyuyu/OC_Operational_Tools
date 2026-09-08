import 'package:flutter/material.dart';
import '../../../design/theme.dart';
import '../application/kakutei_controller.dart';
import '../domain/models.dart';

Future<void> confirmOperation(
  BuildContext context,
  KakuteiController controller,
  RolePlan plan,
) async {
  if (plan.targets.isEmpty) {
    controller.showNotice('操作対象者はいません。');
    return;
  }
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _OperationConfirmation(plan: plan, demo: controller.demo),
  );
  if (approved == true) {
    await controller.execute(
      plan,
      acknowledged: plan.action == RoleAction.remove,
    );
  }
}

class _OperationConfirmation extends StatefulWidget {
  const _OperationConfirmation({required this.plan, required this.demo});
  final RolePlan plan;
  final bool demo;
  @override
  State<_OperationConfirmation> createState() => _OperationConfirmationState();
}

class _OperationConfirmationState extends State<_OperationConfirmation> {
  bool _acknowledged = false;
  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final removal = plan.action == RoleAction.remove;
    return AlertDialog(
      scrollable: true,
      title: Text(removal ? 'ロール解除の確認' : 'ロール付与の確認'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.guild.name,
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '「${plan.role.name}」を${plan.targets.length}人${removal ? 'から解除' : 'に付与'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!removal) ...[
              const SizedBox(height: 8),
              Text(
                '付与予定 ${plan.targets.where((m) => m.present && !m.roles.contains(plan.role.id)).length}人 · '
                'スキップ予定 ${plan.targets.where((m) => !m.present || m.roles.contains(plan.role.id)).length}人',
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.separated(
                key: const PageStorageKey('confirmation_targets'),
                primary: false,
                itemCount: plan.targets.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final member = plan.targets[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.displayName),
                    subtitle: Text(member.id),
                  );
                },
              ),
            ),
            if (removal) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _acknowledged,
                onChanged: (value) =>
                    setState(() => _acknowledged = value ?? false),
                title: const Text('抽出条件に関係なく、対象者全員からこのロールを解除することを確認しました。'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              widget.demo ? 'サンプルデータに反映します。' : '実行済みの変更は、中止しても元には戻りません。',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          style: removal
              ? FilledButton.styleFrom(
                  backgroundColor: context.colors.error,
                  foregroundColor: context.colors.onError,
                )
              : null,
          onPressed: !removal || _acknowledged
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(removal ? '一括解除する' : '付与する'),
        ),
      ],
    );
  }
}

Future<bool> confirmMessageExport(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('メッセージCSVを出力'),
        content: const Text(
          'メッセージや添付URLには個人情報が含まれる場合があります。保存先と共有する相手を確認してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('出力する'),
          ),
        ],
      ),
    ) ??
    false;
