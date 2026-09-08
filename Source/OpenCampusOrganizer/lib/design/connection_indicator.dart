import 'package:flutter/material.dart';
import '../core/tool_status.dart';
import 'theme.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.connection});
  final ToolConnection connection;

  @override
  Widget build(BuildContext context) {
    final color = switch (connection.state) {
      ToolConnectionState.connected => context.colors.primary,
      ToolConnectionState.connecting ||
      ToolConnectionState.sample => context.colors.tertiary,
      ToolConnectionState.disconnected => context.colors.onSurfaceVariant,
    };
    final icon = switch (connection.state) {
      ToolConnectionState.connected => Icons.check_circle,
      ToolConnectionState.connecting => Icons.sync,
      ToolConnectionState.sample => Icons.science_outlined,
      ToolConnectionState.disconnected => Icons.link_off,
    };
    return Semantics(
      label: '${connection.service} ${connection.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: .09),
              context.colors.surface,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${connection.service} · ${connection.label}',
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
