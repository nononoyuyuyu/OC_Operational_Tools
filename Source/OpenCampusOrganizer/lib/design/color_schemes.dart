import 'package:flutter/material.dart';
import '../core/appearance.dart';

/// 面・文字・操作の役割を揃え、淡い背景でも文字を薄くしない。
ColorScheme colorSchemeFor(AppAppearance appearance) {
  final p = _palettes[appearance]!;
  final dark = appearance == AppAppearance.dark;
  return ColorScheme.fromSeed(
    seedColor: Color(p.primary),
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: Color(p.primary),
    onPrimary: Color(dark ? 0xff101722 : 0xffffffff),
    primaryContainer: Color(p.primaryContainer),
    onPrimaryContainer: Color(p.primary),
    surface: Color(p.surface),
    onSurface: Color(p.ink),
    onSurfaceVariant: Color(p.muted),
    outline: Color(p.outline),
    outlineVariant: Color(p.line),
    error: Color(dark ? 0xffffaaaa : 0xffb32c2c),
    onError: Color(dark ? 0xff4e0000 : 0xffffffff),
    errorContainer: Color(dark ? 0xff49282a : 0xffffecec),
    onErrorContainer: Color(dark ? 0xffffc9c9 : 0xff8c2323),
    tertiary: Color(dark ? 0xfff2c97b : 0xff806018),
    onTertiary: Color(dark ? 0xff251a00 : 0xffffffff),
    tertiaryContainer: Color(dark ? 0xff433519 : 0xfffff0d0),
    onTertiaryContainer: Color(dark ? 0xffffdfa0 : 0xff624600),
  ).copyWith(
    surfaceContainerLowest: Color(p.paper),
    surfaceContainerLow: Color(p.low),
    surfaceContainer: Color(p.surface),
    surfaceContainerHigh: Color(p.high),
    surfaceContainerHighest: Color(p.highest),
    surfaceTint: Colors.transparent,
  );
}

const _palettes = {
  AppAppearance.dark: _Palette(
    primary: 0xff8bb5ff,
    primaryContainer: 0xff27384f,
    surface: 0xff23272b,
    paper: 0xff151719,
    ink: 0xffeef1f4,
    muted: 0xffaeb7c2,
    outline: 0xff8792a0,
    line: 0xff464c54,
    low: 0xff181b1e,
    high: 0xff30363d,
    highest: 0xff363d45,
  ),
  AppAppearance.light: _Palette(
    primary: 0xff245dc1,
    primaryContainer: 0xffe5edfd,
    surface: 0xffffffff,
    paper: 0xfff4f6f8,
    ink: 0xff20242a,
    muted: 0xff5b6572,
    outline: 0xff7e8998,
    line: 0xffc9ced6,
    low: 0xffeef1f5,
    high: 0xffe8ecf1,
    highest: 0xffdfe5ed,
  ),
  AppAppearance.warm: _Palette(
    primary: 0xff3d4b4b,
    primaryContainer: 0xffe0e5e2,
    surface: 0xfffffefc,
    paper: 0xfff5f4f1,
    ink: 0xff25231f,
    muted: 0xff656058,
    outline: 0xff8b8377,
    line: 0xffccc8bf,
    low: 0xffedebe6,
    high: 0xffeeede8,
    highest: 0xffe5e2da,
  ),
  AppAppearance.sage: _Palette(
    primary: 0xff376649,
    primaryContainer: 0xffdcebdd,
    surface: 0xfffbfdf9,
    paper: 0xfff1f6f0,
    ink: 0xff203127,
    muted: 0xff546357,
    outline: 0xff7b887b,
    line: 0xffccd8cc,
    low: 0xffeaf1e7,
    high: 0xffe4ece0,
    highest: 0xffdae5d6,
  ),
  AppAppearance.orange: _Palette(
    primary: 0xff994b20,
    primaryContainer: 0xfff9e2d0,
    surface: 0xfffffbf7,
    paper: 0xfffbf4ed,
    ink: 0xff35281f,
    muted: 0xff6f5e50,
    outline: 0xff9a8070,
    line: 0xffdecec0,
    low: 0xfff5ece1,
    high: 0xfff0e5d7,
    highest: 0xffe9dbc9,
  ),
};

class _Palette {
  const _Palette({
    required this.primary,
    required this.primaryContainer,
    required this.surface,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.outline,
    required this.line,
    required this.low,
    required this.high,
    required this.highest,
  });
  final int primary, primaryContainer, surface, paper, ink, muted;
  final int outline, line, low, high, highest;
}
