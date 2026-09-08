import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// ヘッダー・操作欄を除いた実際の高さから、一画面に入る件数を決める。
class AdaptivePageList extends StatefulWidget {
  const AdaptivePageList({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    required this.resetToken,
    required this.empty,
    this.itemExtentFor,
    this.paginationKey = const ValueKey('results-pagination'),
    this.previousTooltip = '前のページ',
    this.nextTooltip = '次のページ',
    this.totalCount,
    this.hasMore = false,
    this.onLoadMore,
  });
  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final Object? resetToken;
  final Widget empty;
  final double Function(int index)? itemExtentFor;
  final Key paginationKey;
  final String previousTooltip;
  final String nextTooltip;
  final int? totalCount;
  final bool hasMore;
  final Future<void> Function()? onLoadMore;
  @override
  State<AdaptivePageList> createState() => _AdaptivePageListState();
}

class _AdaptivePageListState extends State<AdaptivePageList> {
  int _first = 0;
  bool _loading = false;
  final _previousStarts = <int>[];
  final _overflowScroll = ScrollController(keepScrollOffset: false);
  final _rowsScroll = ScrollController(keepScrollOffset: false);

  void _resetScroll() {
    if (!mounted) return;
    for (final controller in [_overflowScroll, _rowsScroll]) {
      if (controller.hasClients) controller.jumpTo(0);
    }
  }

  void _go(int index) {
    setState(() => _first = index);
    _resetScroll();
  }

  Future<void> _next(int first, int end) async {
    final resetToken = widget.resetToken;
    if (end >= widget.itemCount) {
      if (_loading || !widget.hasMore || widget.onLoadMore == null) return;
      setState(() => _loading = true);
      try {
        await widget.onLoadMore!();
        // 呼び出し元の件数更新を描画してから、新しいページの先頭を決める。
        await WidgetsBinding.instance.endOfFrame;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (!mounted ||
        resetToken != widget.resetToken ||
        end >= widget.itemCount) {
      return;
    }
    _previousStarts.add(first);
    _go(end);
  }

  @override
  void dispose() {
    _overflowScroll.dispose();
    _rowsScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdaptivePageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _first = 0;
      _previousStarts.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetScroll());
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final footerHeight = math.max(
        48.0,
        MediaQuery.textScalerOf(context).scale(14) * 2 + 16,
      );
      final room = math.max(0.0, box.maxHeight - footerHeight);
      // リサイズしても先頭の対象者を維持する。ページ番号×可変件数にはしない。
      final first = _first.clamp(0, math.max(0, widget.itemCount - 1)).toInt();
      double extent(int index) =>
          widget.itemExtentFor?.call(index) ?? widget.itemExtent;
      var end = first;
      var used = 0.0;
      while (end < widget.itemCount) {
        final height = extent(end);
        if (end > first && used + height > room) break;
        used += height;
        end++;
      }
      var previous = first;
      used = 0;
      while (previous > 0) {
        final height = extent(previous - 1);
        if (previous < first && used + height > room) break;
        used += height;
        previous--;
      }
      final firstExtent = widget.itemCount == 0
          ? widget.itemExtent
          : extent(first);
      Widget content() => Column(
        children: [
          Expanded(
            child: widget.itemCount == 0
                ? SingleChildScrollView(child: widget.empty)
                : ListView.builder(
                    key: const PageStorageKey('adaptive-page-rows'),
                    controller: _rowsScroll,
                    primary: false,
                    padding: EdgeInsets.zero,
                    physics: room >= firstExtent
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    itemExtent: widget.itemExtentFor == null
                        ? widget.itemExtent
                        : null,
                    itemCount: end - first,
                    itemBuilder: (context, index) => SizedBox(
                      height: extent(first + index),
                      child: widget.itemBuilder(context, first + index),
                    ),
                  ),
          ),
          SizedBox(
            key: widget.paginationKey,
            height: footerHeight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.itemCount == 0
                        ? '0件'
                        : '${first + 1}–$end / ${widget.totalCount ?? widget.itemCount}件',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.previousTooltip,
                  onPressed: first == 0 || _loading
                      ? null
                      : () {
                          _previousStarts.removeWhere(
                            (index) => index >= first,
                          );
                          _go(
                            _previousStarts.isEmpty
                                ? previous
                                : _previousStarts.removeLast(),
                          );
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: widget.nextTooltip,
                  onPressed:
                      _loading || (end >= widget.itemCount && !widget.hasMore)
                      ? null
                      : () => _next(first, end),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      );
      final minimumHeight = footerHeight + firstExtent;
      // 高さの境界をまたいでも子のStateを作り直さない。
      return SingleChildScrollView(
        controller: _overflowScroll,
        primary: false,
        child: SizedBox(
          height: math.max(box.maxHeight, minimumHeight),
          child: content(),
        ),
      );
    },
  );
}
