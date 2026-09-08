import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/tool_module.dart';
import '../core/tool_activity.dart';
import '../design/adaptive_page_list.dart';
import '../design/theme.dart';
import '../design/select_field.dart';
import '../design/widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.modules, this.active = true});
  final List<ToolModule> modules;
  final bool active;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _tool;
  (String, String)? _selected;
  bool _showDetails = false;
  (String, String)? _opened;

  @override
  Widget build(BuildContext context) {
    final entries =
        <(ToolModule, ToolActivity)>[
          for (final module in widget.modules)
            if (_tool == null || module.id == _tool)
              for (final activity in module.activities) (module, activity),
        ]..sort((a, b) {
          final order = b.$2.at.compareTo(a.$2.at);
          return order != 0
              ? order
              : '${a.$1.id}/${a.$2.id}'.compareTo('${b.$1.id}/${b.$2.id}');
        });
    // 他ツールの未取得の新しい履歴を、取得済みの古い履歴より後に出さない。
    // 続きがある各ツールの最古の取得位置までを、順序が確定した範囲とする。
    var available = entries.length;
    for (final module in widget.modules) {
      if ((_tool == null || module.id == _tool) &&
          module is PagedActivityModule &&
          (module as PagedActivityModule).hasMoreActivities) {
        available = math.min(
          available,
          entries.lastIndexWhere((entry) => entry.$1.id == module.id) + 1,
        );
      }
    }
    entries.removeRange(available, entries.length);
    final selected =
        entries.where((e) => (e.$1.id, e.$2.id) == _selected).firstOrNull ??
        entries.firstOrNull;
    _selected = selected == null ? null : (selected.$1.id, selected.$2.id);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final sources = widget.modules
        .where((module) => _tool == null || module.id == _tool)
        .toList();
    final paged = sources.whereType<PagedActivityModule>().toList();
    final total = sources.fold<int>(
      0,
      (sum, module) =>
          sum +
          (module is PagedActivityModule
              ? (module as PagedActivityModule).activityTotal
              : module.activities.length),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900 && box.maxHeight >= 420 * scale;
        if (widget.active && (wide || _showDetails)) _opened = _selected;
        final listWidth = wide
            ? (box.maxWidth * .4).clamp(320.0, 460.0)
            : box.maxWidth;
        return SingleChildScrollView(
          primary: false,
          child: SizedBox(
            height: math.max(box.maxHeight, 320 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Offstage(
                  offstage: wide,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      key: const ValueKey('history-view-tabs'),
                      children: [
                        ChoiceChip(
                          label: const Text('履歴'),
                          selected: !_showDetails || selected == null,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _showDetails = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('詳細'),
                          selected: _showDetails && selected != null,
                          showCheckmark: false,
                          onSelected: selected == null
                              ? null
                              : (_) => setState(() => _showDetails = true),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  // 同じ子を維持し、横並び・片側表示の往復でもページ位置を保つ。
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: listWidth,
                        child: Offstage(
                          offstage: !wide && _showDetails && selected != null,
                          child: Surface(
                            key: const ValueKey('history-list-panel'),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.modules.length > 1) ...[
                                  SelectField<String>(
                                    initialValue: _tool ?? '',
                                    decoration: const InputDecoration(
                                      labelText: 'ツール',
                                      isDense: true,
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: '',
                                        child: Text('すべて'),
                                      ),
                                      for (final module in widget.modules)
                                        DropdownMenuItem(
                                          value: module.id,
                                          child: Text(module.title),
                                        ),
                                    ],
                                    onChanged: (value) => setState(() {
                                      _tool = value == '' ? null : value;
                                      _selected = null;
                                      _showDetails = false;
                                    }),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Expanded(
                                  child: AdaptivePageList(
                                    itemCount: entries.length,
                                    totalCount: math.max(entries.length, total),
                                    hasMore: paged.any(
                                      (source) => source.hasMoreActivities,
                                    ),
                                    onLoadMore: () async {
                                      await Future.wait([
                                        for (final source in paged)
                                          if (source.hasMoreActivities)
                                            source.loadMoreActivities(),
                                      ]);
                                    },
                                    itemExtent: 16 + 96 * scale,
                                    resetToken: _tool,
                                    paginationKey: const ValueKey(
                                      'history-pagination',
                                    ),
                                    previousTooltip: '前の履歴',
                                    nextTooltip: '次の履歴',
                                    empty: const EmptyState(
                                      icon: Icons.history,
                                      title: '操作履歴はありません',
                                      message: '',
                                    ),
                                    itemBuilder: (context, index) {
                                      final (module, activity) = entries[index];
                                      final active =
                                          (module.id, activity.id) == _selected;
                                      return Material(
                                        key: ValueKey(
                                          'activity_${module.id}_${activity.id}',
                                        ),
                                        color: active
                                            ? context.colors.primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Semantics(
                                          selected: active,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            onTap: () => setState(() {
                                              _selected = (
                                                module.id,
                                                activity.id,
                                              );
                                              _showDetails = true;
                                            }),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              child: _summary(
                                                context,
                                                module,
                                                activity,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: wide ? listWidth + 16 : 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Offstage(
                          offstage:
                              selected == null || (!wide && !_showDetails),
                          child: selected == null || _opened != _selected
                              ? const SizedBox()
                              : _details(selected.$1, selected.$2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summary(
    BuildContext context,
    ToolModule module,
    ToolActivity activity,
  ) {
    final secondary = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_date(activity.at)} JST · ${module.title}${activity.sample ? ' · サンプル' : ''}',
          style: secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          '${activity.action} · ${activity.subject}',
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          activity.context,
          style: secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          activity.result,
          style: secondary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _details(ToolModule module, ToolActivity activity) => Surface(
    key: const ValueKey('history-details-panel'),
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(48, box.maxHeight * .3),
            ),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${module.title} · ${_date(activity.at)} JST${activity.sample ? ' · サンプル' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${activity.action} · ${activity.subject}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    activity.context,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    activity.result,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey((module.id, activity.id)),
              child: module.buildActivityDetails(activity.id),
            ),
          ),
        ],
      ),
    ),
  );

  String _date(DateTime at) {
    final value = at.toUtc().add(const Duration(hours: 9));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}
