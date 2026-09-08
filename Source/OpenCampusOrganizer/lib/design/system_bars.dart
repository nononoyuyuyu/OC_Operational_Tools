import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Androidのedge-to-edge領域はFlutter側の背景で塗り、OSには文字色を渡す。
/// iOSのホームインジケーターの見た目はOSが管理する。
class ThemedSystemBars extends StatelessWidget {
  const ThemedSystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemStatusBarContrastEnforced: false,
        // Android 15以降はこの色指定を無視してFlutterの背景を表示する。
        // 8〜14では明るいテーマに黒いバー・黒いボタンが残るのを防ぐ。
        systemNavigationBarColor: colors.surface,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(color: colors.surface, child: child),
    );
  }
}
