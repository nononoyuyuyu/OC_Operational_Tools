import 'package:flutter/material.dart';
import '../core/appearance.dart';
import 'color_schemes.dart';

extension OcoTheme on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}

ThemeData buildTheme([AppAppearance appearance = AppAppearance.dark]) {
  final scheme = colorSchemeFor(appearance);
  final paper = scheme.surfaceContainerLowest;
  final surface = scheme.surface;
  final ink = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final line = scheme.outlineVariant;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: scheme.outline),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    fontFamily: 'Noto Sans JP',
    fontFamilyFallback: const ['Yu Gothic UI', 'Hiragino Sans', 'sans-serif'],
    textTheme: TextTheme(
      headlineLarge: const TextStyle(
        fontSize: 28,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        height: 1.5,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: const TextStyle(
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: const TextStyle(fontSize: 14, height: 1.6),
      bodyMedium: const TextStyle(fontSize: 13, height: 1.6),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ).apply(bodyColor: ink, displayColor: ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: TextStyle(fontSize: 13, color: muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    // カード外周とExpansionTile標準の上下線を二重に描画しない。
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: ink),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
