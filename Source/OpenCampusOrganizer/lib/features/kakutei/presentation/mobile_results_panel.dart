import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../domain/models.dart';

/// スマホでは一覧だけをスクロールさせ、検索と付与操作を常に残す。
class MobileResultsPanel extends StatefulWidget {
  const MobileResultsPanel({
    super.key,
    required this.result,
    required this.users,
    required this.adding,
    required this.search,
    required this.onSearch,
    required this.action,
  });
  final Extraction result;
  final List<Activity> users;
  final int adding;
  final TextEditingController search;
  final VoidCallback onSearch;
  final Widget action;

  @override
  State<MobileResultsPanel> createState() => _MobileResultsPanelState();
}

class _MobileResultsPanelState extends State<MobileResultsPanel> {
  final _scroll = ScrollController();
  String _query = '';

  @override
  void didUpdateWidget(covariant MobileResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.search.text.trim().toLowerCase();
    if (oldWidget.result != widget.result || query != _query) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    _query = query;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _searchField() => TextField(
    key: const ValueKey('mobile-member-search'),
    controller: widget.search,
    decoration: const InputDecoration(
      isDense: true,
      hintText: '名前で検索',
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      prefixIcon: Icon(Icons.search, size: 18),
      prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 44),
    ),
    onChanged: (_) => widget.onSearch(),
  );

  @override
  Widget build(BuildContext context) => Surface(
    key: const ValueKey('results-panel'),
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final short = box.maxHeight < 220 * scale;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: short
                  ? Row(
                      children: [
                        Expanded(child: _searchField()),
                        const SizedBox(width: 8),
                        widget.action,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '対象者 ${widget.result.users.length}人',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '付与予定 ${widget.adding}人',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _searchField(),
                      ],
                    ),
            ),
            Expanded(
              child: widget.users.isEmpty
                  ? const Center(child: Text('対象者が見つかりませんでした'))
                  : Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: ListView.builder(
                        key: const ValueKey('mobile-member-list'),
                        controller: _scroll,
                        primary: false,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(right: 12),
                        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                        itemCount: widget.users.length,
                        itemExtent: math.max(40, 16 + 21 * scale),
                        itemBuilder: (context, index) {
                          final user = widget.users[index];
                          return Container(
                            key: ValueKey('member-${user.member.id}'),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: context.colors.outlineVariant,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: user.member.displayName,
                                    child: Text(
                                      user.member.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  user.planned,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: user.hasRole || !user.member.present
                                        ? context.colors.onSurfaceVariant
                                        : context.colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            if (!short) ...[
              const Divider(),
              const SizedBox(height: 8),
              widget.action,
            ],
          ],
        );
      },
    ),
  );
}
