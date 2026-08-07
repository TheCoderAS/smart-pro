import 'package:flutter/material.dart';

/// Unisync brand palette, shared with the marketing site
/// (web/app/globals.css). Warm near-black ground, copper accent.
abstract final class UnisyncColors {
  static const accent = Color(0xFFD97757);
  static const bgDark = Color(0xFF0A0A0B);
  static const bgElevatedDark = Color(0xFF111113);
  static const fgDark = Color(0xFFF4F2EE);
  static const fgMuted = Color(0xFF8A8780);
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: UnisyncColors.accent,
  );
  return _base(scheme);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: UnisyncColors.accent,
    brightness: Brightness.dark,
    surface: UnisyncColors.bgDark,
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: UnisyncColors.bgDark,
    appBarTheme: AppBarTheme(
      backgroundColor: UnisyncColors.bgDark,
      foregroundColor: UnisyncColors.fgDark,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: UnisyncColors.bgElevatedDark,
    ),
  );
}

ThemeData _base(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
