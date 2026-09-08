import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../design/device_layout.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../application/kakutei_controller.dart';

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key, required this.controller});
  final KakuteiController controller;
  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final _token = TextEditingController();
  bool _remember = false;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Discord接続',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (c.connected) ...[
            Text(c.bot!.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '${c.guilds.length}サーバーに参加',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  'メンバー取得 ${c.bot!.membersIntent ? '有効' : '未設定'}',
                  color: c.bot!.membersIntent
                      ? context.colors.primary
                      : context.colors.tertiary,
                ),
                if (!isPhoneLayout(context))
                  StatusPill(
                    '本文取得 ${c.bot!.contentIntent ? '有効' : '未設定'}',
                    color: c.bot!.contentIntent
                        ? context.colors.primary
                        : context.colors.tertiary,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!c.demo)
                  OutlinedButton.icon(
                    onPressed: c.busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: c.bot!.inviteUrl.toString()),
                            );
                            if (context.mounted) {
                              c.showNotice('招待URLをコピーしました。');
                            }
                          },
                    icon: Icon(Icons.copy_outlined, size: 17),
                    label: Text('Bot招待URLをコピー'),
                  ),
                OutlinedButton(
                  onPressed: c.busy ? null : () => c.disconnect(),
                  child: Text(c.demo ? 'サンプルを終了' : '切断'),
                ),
              ],
            ),
          ] else ...[
            if (!c.demoOnly) ...[
              Text('Bot Token', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                enabled: !c.busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: const InputDecoration(
                  hintText: 'Bot Tokenを入力',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _remember,
                title: Text('この端末にTokenを保存する'),
                onChanged: c.busy
                    ? null
                    : (value) => setState(() => _remember = value!),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: c.busy ? null : _connect,
                    icon: Icon(Icons.link, size: 18),
                    label: Text('接続する'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy ? null : c.startDemo,
                    child: Text('サンプルで試す'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              ExpansionTile(
                key: const PageStorageKey('discord_setup'),
                tilePadding: EdgeInsets.zero,
                title: Text('Botの準備'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  Text(
                    '1. Discord Developer PortalでBotを作成します。\n'
                    '2. チャンネルを見る・メッセージ履歴を読む・ロールの管理を許可して招待します。\n'
                    '3. Botのロールを、操作するロールより上に配置します。\n'
                    '4. 本文・添付URLの取得にはMessage Content Intent、一括解除にはServer Members Intentを有効にします。',
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      height: 1.9,
                    ),
                  ),
                ],
              ),
            ] else
              FilledButton(
                onPressed: c.busy ? null : c.startDemo,
                child: Text('サンプルを開く'),
              ),
          ],
          if (c.savedCredential) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: c.busy ? null : c.deleteCredential,
              icon: Icon(Icons.key_off_outlined, size: 18),
              label: Text('保存済みTokenを削除'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final token = _token.text;
    _token.clear();
    await widget.controller.connect(token, remember: _remember);
  }
}
