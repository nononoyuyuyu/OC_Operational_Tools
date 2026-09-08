import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/failure.dart';
import '../../../design/adaptive_page_list.dart';
import '../../../design/device_layout.dart';
import '../../../design/theme.dart';
import '../../../design/widgets.dart';
import '../application/kakutei_controller.dart';
import '../domain/jst.dart';
import '../domain/models.dart';

class ReportPanel extends StatelessWidget {
  const ReportPanel({
    super.key,
    required this.report,
    required this.controller,
    this.fill = false,
    this.onShowTargets,
  });
  final OperationReport report;
  final KakuteiController controller;
  final bool fill;
  final VoidCallback? onShowTargets;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '「${report.plan.role.name}」を${report.plan.actionLabel}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            StatusPill(
              report.finishedAt == null
                  ? (controller.busy ? '処理中' : '中断・要確認')
                  : '処理終了',
              color: report.finishedAt == null
                  ? context.colors.tertiary
                  : context.colors.primary,
            ),
            if (onShowTargets != null)
              TextButton.icon(
                onPressed: onShowTargets,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('対象者一覧'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${report.plan.guild.name} · ${formatJst(report.startedAt)} JST',
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),
        _Outcomes(report: report),
        const SizedBox(height: 16),
        if (fill)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('対象者ごとの結果'),
                const SizedBox(height: 12),
                Expanded(child: _ReportRows(report: report, fill: true)),
              ],
            ),
          )
        else
          ExpansionTile(
            key: PageStorageKey('operation_${report.id}'),
            tilePadding: EdgeInsets.zero,
            title: const Text('対象者ごとの結果'),
            children: [_ReportRows(report: report)],
          ),
        if (!isPhoneLayout(context)) ...[
          const SizedBox(height: 8),
          _ExportReport(report: report, controller: controller),
        ],
      ],
    ),
  );
}

/// 全体履歴の要約行を開いた先の詳細。ツール固有の項目はこのモジュールで描画する。
class LazyReportDetails extends StatefulWidget {
  const LazyReportDetails({
    super.key,
    required this.id,
    required this.controller,
  });
  final String id;
  final KakuteiController controller;
  @override
  State<LazyReportDetails> createState() => _LazyReportDetailsState();
}

class _LazyReportDetailsState extends State<LazyReportDetails> {
  late Future<OperationReport?> _report;
  @override
  void initState() {
    super.initState();
    _report = widget.controller.loadReport(widget.id);
  }

  @override
  void didUpdateWidget(covariant LazyReportDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.controller != widget.controller) {
      _report = widget.controller.loadReport(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OperationReport?>(
    future: _report,
    builder: (context, snapshot) {
      final live = widget.controller.latestReport;
      final report = live?.id == widget.id ? live : snapshot.data;
      if (report != null) {
        return ReportDetails(report: report, controller: widget.controller);
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              snapshot.hasError
                  ? failureMessage(snapshot.error!)
                  : '操作履歴が見つかりません。',
            ),
            TextButton(
              onPressed: () => setState(() {
                _report = widget.controller.loadReport(widget.id);
              }),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    },
  );
}

class ReportDetails extends StatelessWidget {
  const ReportDetails({
    super.key,
    required this.report,
    required this.controller,
  });
  final OperationReport report;
  final KakuteiController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final header = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          const Text('対象者ごとの結果'),
          if (!isPhoneLayout(context))
            _ExportReport(report: report, controller: controller),
        ],
      );
      if (!box.hasBoundedHeight) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 4),
            _ReportRows(report: report),
          ],
        );
      }
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return SingleChildScrollView(
        primary: false,
        child: SizedBox(
          height: math.max(box.maxHeight, 180 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 4),
              Expanded(child: _ReportRows(report: report, fill: true)),
            ],
          ),
        ),
      );
    },
  );
}

class _Outcomes extends StatelessWidget {
  const _Outcomes({required this.report});
  final OperationReport report;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    children: [
      for (final outcome in [
        Outcome.success,
        Outcome.skipped,
        Outcome.failed,
        Outcome.uncertain,
        Outcome.unprocessed,
      ])
        StatusPill(
          '${outcomeLabel(outcome)} ${report.count(outcome)}',
          color: outcome == Outcome.failed || outcome == Outcome.uncertain
              ? context.colors.tertiary
              : context.colors.primary,
        ),
    ],
  );
}

class _ReportRows extends StatelessWidget {
  const _ReportRows({required this.report, this.fill = false});
  final OperationReport report;
  final bool fill;
  @override
  Widget build(BuildContext context) {
    if (report.rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('対象者はいません。'),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final text = Theme.of(context).textTheme.bodyMedium!;
        final secondary = text.copyWith(
          fontSize: 12,
          color: context.colors.onSurfaceVariant,
        );
        final scaler = MediaQuery.textScalerOf(context);
        Size measure(String value, TextStyle style, double width) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            locale: Localizations.maybeLocaleOf(context),
          )..layout(maxWidth: width);
          final size = painter.size;
          painter.dispose();
          return size;
        }

        final outcomeWidth = Outcome.values
            .map(
              (value) =>
                  measure(outcomeLabel(value), text, double.infinity).width,
            )
            .reduce(math.max)
            .ceilToDouble();
        final textWidth = math.max(1.0, box.maxWidth - outcomeWidth - 24);
        final heights = <int, double>{};
        double extent(int index) => heights.putIfAbsent(index, () {
          final row = report.rows[index];
          final contentHeight =
              measure(row.member.displayName, text, textWidth).height +
              measure(row.member.id, secondary, textWidth).height +
              (row.reason.isEmpty
                  ? 0
                  : measure(row.reason, secondary, textWidth).height);
          return 17 +
              math
                  .max(
                    contentHeight,
                    measure(
                      outcomeLabel(row.outcome),
                      text,
                      outcomeWidth,
                    ).height,
                  )
                  .ceilToDouble();
        });
        final footerHeight = math.max(48.0, scaler.scale(14) * 2 + 16);
        final limit = math.min(360.0, MediaQuery.sizeOf(context).height * .45);
        var compactHeight = footerHeight;
        for (
          var index = 0;
          index < report.rows.length && compactHeight < limit;
          index++
        ) {
          compactHeight += extent(index);
        }
        return SizedBox(
          height: fill && box.hasBoundedHeight
              ? box.maxHeight
              : math.min(compactHeight, limit),
          child: AdaptivePageList(
            key: ValueKey('operation_rows_${report.id}'),
            itemCount: report.rows.length,
            itemExtent: extent(0),
            itemExtentFor: extent,
            resetToken: report.id,
            paginationKey: ValueKey('operation-pagination-${report.id}'),
            empty: const SizedBox(),
            itemBuilder: (context, index) {
              final row = report.rows[index];
              return Container(
                key: ValueKey('operation-row-${report.id}-${row.member.id}'),
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.colors.outlineVariant),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.member.displayName, style: text),
                          Text(row.member.id, style: secondary),
                          if (row.reason.isNotEmpty)
                            Text(row.reason, style: secondary),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: outcomeWidth,
                      child: Text(
                        outcomeLabel(row.outcome),
                        style: text,
                        key: ValueKey('outcome-${report.id}-${row.member.id}'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ExportReport extends StatelessWidget {
  const _ExportReport({required this.report, required this.controller});
  final OperationReport report;
  final KakuteiController controller;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: controller.busy ? null : () => controller.exportReport(report),
    icon: const Icon(Icons.download_outlined, size: 18),
    label: const Text('結果CSVを出力'),
  );
}
