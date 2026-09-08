import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/runtime_controller.dart';
import '../design/widgets.dart';

class RuntimeSettings extends StatelessWidget {
  const RuntimeSettings({super.key, required this.controller});
  final RuntimeController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final target = Theme.of(context).platform;
      if (kIsWeb ||
          ![
            TargetPlatform.windows,
            TargetPlatform.android,
            TargetPlatform.iOS,
          ].contains(target) ||
          (target == TargetPlatform.iOS && controller.error == null)) {
        return const SizedBox.shrink();
      }
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('バックグラウンド', style: Theme.of(context).textTheme.titleMedium),
            if (target == TargetPlatform.windows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('閉じてもタスクトレイで続ける'),
                value: controller.trayEnabled,
                onChanged: (v) => controller.setPreferences(tray: v),
              ),
            if (target == TargetPlatform.android)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('完了後にアプリを終了'),
                subtitle: const Text('バックグラウンドでのロール操作完了時'),
                value: controller.mobileAutoClose,
                onChanged: (v) => controller.setPreferences(autoClose: v),
              ),
            if (controller.error != null)
              MessageBanner(controller.error!, error: true),
          ],
        ),
      );
    },
  );
}
