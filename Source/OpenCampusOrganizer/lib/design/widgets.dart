import 'package:flutter/material.dart';
import 'theme.dart';

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
    clipBehavior: Clip.antiAlias,
    color: color ?? context.colors.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: context.colors.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final resolved = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.circle,
            color: resolved,
            size: icon == null ? 6 : 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: resolved,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 24,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(color: context.colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: context.colors.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: context.colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class MessageBanner extends StatelessWidget {
  const MessageBanner(
    this.message, {
    super.key,
    this.error = false,
    this.onClose,
  });
  final String message;
  final bool error;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error
            ? context.colors.errorContainer
            : context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 20,
            color: error
                ? context.colors.onErrorContainer
                : context.colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: error
                    ? context.colors.onErrorContainer
                    : context.colors.onSurface,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              tooltip: '閉じる',
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    ),
  );
}

class OcoMark extends StatelessWidget {
  const OcoMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.colors.primaryContainer,
      shape: BoxShape.circle,
    ),
    clipBehavior: Clip.antiAlias,
    child: ColorFiltered(
      colorFilter: _markColors(
        context.colors.primary,
        context.colors.primaryContainer,
      ),
      child: Image.asset('assets/branding/oco-master.png', fit: BoxFit.contain),
    ),
  );

  // 白黒の生成原画を色の濃淡として使い、テーマ変更時も同じ形を保つ。
  ColorFilter _markColors(Color foreground, Color background) =>
      ColorFilter.matrix([
        foreground.r - background.r,
        0,
        0,
        0,
        background.r * 255,
        foreground.g - background.g,
        0,
        0,
        0,
        background.g * 255,
        foreground.b - background.b,
        0,
        0,
        0,
        background.b * 255,
        0,
        0,
        0,
        1,
        0,
      ]);
}
