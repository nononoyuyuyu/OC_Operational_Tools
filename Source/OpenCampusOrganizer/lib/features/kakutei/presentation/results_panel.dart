import 'package:flutter/material.dart';
import '../../../core/failure.dart';
import '../../../design/adaptive_page_list.dart';
import '../../../design/device_layout.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../application/kakutei_controller.dart';
import '../domain/jst.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import 'operation_dialogs.dart';
import 'mobile_results_panel.dart';
import 'results_projection.dart';

class ResultsPanel extends StatefulWidget {
  const ResultsPanel({
    super.key,
    required this.controller,
    required this.onError,
    this.onShowReport,
  });
  final KakuteiController controller;
  final ValueChanged<String> onError;
  final VoidCallback? onShowReport;
  @override
  State<ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<ResultsPanel> {
  final _search = TextEditingController();
  int _tab = 0;
  ResultsProjection? _projection;
  KakuteiController get c => widget.controller;

  @override
  void didUpdateWidget(covariant ResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, c)) _projection = null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = c.extraction;
    if (result == null) {
      _projection = null;
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '対象者一覧',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.onShowReport != null)
                  TextButton(
                    onPressed: widget.onShowReport,
                    child: const Text('実行結果'),
                  ),
              ],
            ),
            const Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.people_outline,
                    title: '抽出結果はありません',
                    message: '条件を指定して対象者を確認してください。',
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final search = _search.text.trim().toLowerCase();
    if (!identical(_projection?.result, result) ||
        _projection?.search != search) {
      _projection = ResultsProjection(result, search: search);
    }
    final projection = _projection!;
    if (!result.conditions.retainMessages) _tab = 0;
    final adding = projection.adding;
    final phone = isPhoneLayout(context);
    final users = phone || _tab == 0 ? projection.users : const <Activity>[];
    if (phone) {
      return MobileResultsPanel(
        result: result,
        users: users,
        adding: adding,
        search: _search,
        onSearch: () => setState(() {}),
        action: _additionButton(adding, compact: true),
      );
    }
    final messages = _tab == 1 ? projection.messages : const <Message>[];
    return Surface(
      key: const ValueKey('results-panel'),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '対象者一覧',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const StatusPill('確認済み', icon: Icons.check),
                  if (widget.onShowReport != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onShowReport,
                      child: const Text('実行結果'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '付与予定 $adding人 · スキップ ${result.users.length - adding}人',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (
                    var i = 0;
                    i < (result.conditions.retainMessages ? 2 : 1);
                    i++
                  )
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        i == 0
                            ? 'メンバー ${result.users.length}'
                            : '投稿 ${result.messages.length}',
                      ),
                      selected: _tab == i,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _tab == 0 ? '名前・ユーザーIDで検索' : '名前・ユーザーID・本文で検索',
                  prefixIcon: const Icon(Icons.search, size: 19),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
            ],
          );
          final footer = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _additionButton(adding, compact: box.maxWidth < 420),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onPressed: c.busy
                        ? null
                        : () async {
                            if (_tab == 0) {
                              await c.exportUsers();
                            } else if (await confirmMessageExport(context)) {
                              await c.exportMessages();
                            }
                          },
                    child: const Text('CSV出力'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Tooltip(
                message:
                    '確認 ${formatJst(result.at)} JST · 除外したBot投稿 ${result.excludedBots}件',
                child: Text(
                  '確認 ${formatJst(result.at)} JST',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
          // 極端に低いウィンドウや拡大文字でも操作を失わないための局所的な退避。
          final minimumHeight = 390 * scale;
          Widget content() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: AdaptivePageList(
                  itemCount: _tab == 0 ? users.length : messages.length,
                  itemExtent: _tab == 0 ? 20 + 60 * scale : 24 + 76 * scale,
                  resetToken: (result, _tab, search),
                  empty: EmptyState(
                    icon: Icons.search_off,
                    title: search.isEmpty ? '対象者が見つかりませんでした' : '検索結果はありません',
                    message: '',
                  ),
                  itemBuilder: (context, index) => _tab == 0
                      ? _userRow(users[index])
                      : _messageRow(messages[index], result),
                ),
              ),
              footer,
            ],
          );
          // スクロールの必要性だけを変え、一覧とページ位置のStateを維持する。
          return SingleChildScrollView(
            primary: false,
            child: SizedBox(
              height: box.maxHeight < minimumHeight
                  ? minimumHeight
                  : box.maxHeight,
              child: content(),
            ),
          );
        },
      ),
    );
  }

  Widget _additionButton(int adding, {required bool compact}) => FilledButton(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    key: const ValueKey('add-role'),
    onPressed:
        c.busy ||
            adding == 0 ||
            c.selectedRole == null ||
            roleBlockReason(c.guildContext!, c.selectedRole!) != null
        ? null
        : () async {
            try {
              await confirmOperation(context, c, c.additionPlan());
            } catch (error) {
              if (mounted) widget.onError(failureMessage(error));
            }
          },
    child: Text('${compact ? '付与' : 'ロールを付与'} · $adding人'),
  );

  Widget _userRow(Activity user) => Container(
    key: ValueKey('member-${user.member.id}'),
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: context.colors.primaryContainer,
          child: Text(
            user.member.displayName.characters.firstOrNull ?? '?',
            style: TextStyle(color: context.colors.primary, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: user.member.displayName,
                child: Text(
                  user.member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                user.member.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Text(
                '最終投稿 ${formatJst(user.last)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              user.planned,
              style: TextStyle(
                fontSize: 12,
                color: user.hasRole
                    ? context.colors.onSurfaceVariant
                    : context.colors.primary,
              ),
            ),
            Text(
              '${user.count}件の投稿',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _messageRow(Message message, Extraction result) => InkWell(
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.author.displayName),
        content: SingleChildScrollView(
          child: SelectableText(
            '${formatJst(message.at)} JST\n${message.author.id}\n\n'
            '${result.conditions.includeContent ? message.content : '本文は取得していません。'}'
            '${message.attachments.isEmpty ? '' : '\n\n${message.attachments.join('\n')}'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  message.author.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatJst(message.at),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              result.conditions.includeContent
                  ? (message.content.isEmpty ? '（本文なし）' : message.content)
                  : '本文は取得していません。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
