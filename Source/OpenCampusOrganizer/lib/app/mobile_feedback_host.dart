import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/tool_status.dart';
import '../design/theme.dart';

/// 画面を切り替えても通知を重複させない、アプリ全体で一つの表示領域。
class MobileFeedbackHost extends StatefulWidget {
  const MobileFeedbackHost({
    super.key,
    required this.enabled,
    required this.feedback,
    required this.child,
  });
  final bool enabled;
  final List<ToolFeedback> feedback;
  final Widget child;

  @override
  State<MobileFeedbackHost> createState() => _MobileFeedbackHostState();
}

class _MobileFeedbackHostState extends State<MobileFeedbackHost> {
  final _seen = <String, Object>{};
  ToolFeedback? _active;
  Timer? _timer;
  bool _visible = false;
  bool _accessibleNavigation = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    if (accessible != _accessibleNavigation) {
      _accessibleNavigation = accessible;
      _scheduleDismiss();
    }
  }

  @override
  void didUpdateWidget(covariant MobileFeedbackHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final oldKey = _active?.eventKey;
    final wasVisible = _visible;
    final current = widget.feedback
        .where((value) => value.sourceId == _active?.sourceId)
        .firstOrNull;
    _active = current;
    for (final value in widget.feedback) {
      if (_seen[value.sourceId] != value.eventKey) {
        _active = value;
        _visible = widget.enabled;
        _seen[value.sourceId] = value.eventKey;
      }
    }
    if (!widget.enabled || _active == null) _visible = false;
    // PCで開始してからスマホ表示へ移っても、中止操作を失わない。
    if (widget.enabled && _active?.working == true) _visible = true;
    if (oldKey != _active?.eventKey || wasVisible != _visible) {
      _scheduleDismiss();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel();
    final value = _active;
    if (!_visible ||
        value == null ||
        value.working ||
        value.error ||
        _accessibleNavigation) {
      return;
    }
    _timer = Timer(const Duration(seconds: 6), _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    final dismiss = _active?.dismiss;
    setState(() => _visible = false);
    dismiss?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible && _active != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: _FeedbackPopup(
              key: const ValueKey('mobile-feedback'),
              feedback: _active!,
              maxHeight: math.max(48, math.min(160, box.maxHeight * .45)),
              dismiss: _dismiss,
            ),
          ),
      ],
    ),
  );
}

class _FeedbackPopup extends StatelessWidget {
  const _FeedbackPopup({
    super.key,
    required this.feedback,
    required this.maxHeight,
    required this.dismiss,
  });
  final ToolFeedback feedback;
  final double maxHeight;
  final VoidCallback dismiss;

  @override
  Widget build(BuildContext context) {
    final color = feedback.error
        ? context.colors.error
        : context.colors.primary;
    return Semantics(
      liveRegion: true,
      child: Material(
        elevation: 6,
        shadowColor: context.colors.shadow.withValues(alpha: .25),
        color: context.colors.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: .45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (feedback.working)
              LinearProgressIndicator(value: feedback.progress, minHeight: 3),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    Icon(
                      feedback.error
                          ? Icons.error_outline
                          : feedback.working
                          ? Icons.sync
                          : Icons.check_circle_outline,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      fit: FlexFit.tight,
                      child: SingleChildScrollView(
                        key: ValueKey(feedback.eventKey),
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          feedback.message,
                          style: TextStyle(
                            color: context.colors.onSurface,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    if (feedback.working)
                      TextButton(
                        onPressed: feedback.cancel,
                        child: const Text('中止'),
                      )
                    else
                      IconButton(
                        tooltip: '通知を閉じる',
                        onPressed: dismiss,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
