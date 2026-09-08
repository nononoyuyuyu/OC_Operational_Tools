import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../design/theme.dart';
import '../application/kakutei_controller.dart';

class OperationFeedback extends StatelessWidget {
  const OperationFeedback({
    super.key,
    required this.controller,
    this.localError,
    this.onDismiss,
  });
  final KakuteiController controller;
  final String? localError;
  final VoidCallback? onDismiss;
  KakuteiController get c => controller;
  static double heightFor(BuildContext context) =>
      math.max(56, MediaQuery.textScalerOf(context).scale(13) * 2 + 16);
  @override
  Widget build(BuildContext context) {
    final error = localError ?? c.error;
    if (!c.busy && error == null && c.notice == null) {
      return SizedBox(
        key: const ValueKey('operation-feedback'),
        height: heightFor(context),
      );
    }
    final message = c.busy
        ? '${c.progress}${c.done > 0 ? ' · ${c.done}${c.total == null ? '件' : ' / ${c.total}'}' : ''}'
        : error ?? c.notice ?? '';
    final color = error == null
        ? context.colors.onSurfaceVariant
        : context.colors.error;
    return SizedBox(
      key: const ValueKey('operation-feedback'),
      height: heightFor(context),
      child: Column(
        children: [
          SizedBox(
            height: 3,
            child: c.busy
                ? LinearProgressIndicator(
                    value: c.total == null || c.total == 0
                        ? null
                        : c.done / c.total!,
                  )
                : const SizedBox.expand(),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  error != null
                      ? Icons.error_outline
                      : c.busy
                      ? Icons.sync
                      : Icons.info_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 10),
                if (c.demo &&
                    (c.busy || c.notice != null || error != null)) ...[
                  const Text('サンプル', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: _FeedbackMessage(
                      key: ValueKey(message),
                      message: message,
                      color: color,
                    ),
                  ),
                ),
                if (c.busy)
                  TextButton(onPressed: c.cancel, child: const Text('中止'))
                else if (error != null || c.notice != null)
                  IconButton(
                    tooltip: '通知を閉じる',
                    onPressed: () {
                      onDismiss?.call();
                      c.clearMessage();
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackMessage extends StatefulWidget {
  const _FeedbackMessage({
    super.key,
    required this.message,
    required this.color,
  });
  final String message;
  final Color color;
  @override
  State<_FeedbackMessage> createState() => _FeedbackMessageState();
}

class _FeedbackMessageState extends State<_FeedbackMessage> {
  final _scroll = ScrollController(keepScrollOffset: false);
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    primary: false,
    padding: const EdgeInsets.only(right: 12),
    child: Text(
      widget.message,
      style: TextStyle(fontSize: 13, color: widget.color),
    ),
  );
}
