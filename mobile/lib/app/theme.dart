import 'package:flutter/material.dart';

/// Unisync brand palette, shared with the marketing site
/// (web/app/globals.css). Warm near-black ground, copper accent.
abstract final class UnisyncColors {
  static const accent = Color(0xFFD97757);
  static const accentBright = Color(0xFFE8916F);
  static const accentDeep = Color(0xFFB85C3F);

  // Dark ground — warm, not pure black.
  static const bgDark = Color(0xFF0A0A0B);
  static const surfaceDark = Color(0xFF141416);
  static const surfaceElevatedDark = Color(0xFF1C1C1F);
  static const fgDark = Color(0xFFF4F2EE);
  static const fgMutedDark = Color(0xFF8A8780);

  // Light ground — warm off-white.
  static const bgLight = Color(0xFFF7F5F1);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const fgLight = Color(0xFF1A1917);
  static const fgMutedLight = Color(0xFF6B6862);

  static const success = Color(0xFF4CAF7D);
}

const _fontFamily = 'Manrope';

ThemeData buildLightTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: UnisyncColors.accent,
      ).copyWith(
        primary: UnisyncColors.accentDeep,
        surface: UnisyncColors.surfaceLight,
        surfaceContainerLowest: UnisyncColors.bgLight,
        onSurface: UnisyncColors.fgLight,
        onSurfaceVariant: UnisyncColors.fgMutedLight,
      );
  return _base(scheme, UnisyncColors.bgLight);
}

ThemeData buildDarkTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: UnisyncColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: UnisyncColors.accent,
        surface: UnisyncColors.surfaceDark,
        surfaceContainerLowest: UnisyncColors.bgDark,
        surfaceContainerHighest: UnisyncColors.surfaceElevatedDark,
        onSurface: UnisyncColors.fgDark,
        onSurfaceVariant: UnisyncColors.fgMutedDark,
      );
  return _base(scheme, UnisyncColors.bgDark);
}

ThemeData _base(ColorScheme scheme, Color scaffoldBg) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: scaffoldBg,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  return base.copyWith(
    textTheme: _textTheme(base.textTheme, scheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: scheme.onSurface,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      side: BorderSide.none,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}

TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
  TextStyle h(double size, FontWeight w, {double spacing = -0.4}) => TextStyle(
    fontFamily: _fontFamily,
    fontSize: size,
    fontWeight: w,
    letterSpacing: spacing,
    color: scheme.onSurface,
    height: 1.1,
  );
  return base
      .copyWith(
        displaySmall: h(34, FontWeight.w700),
        headlineMedium: h(26, FontWeight.w700),
        headlineSmall: h(22, FontWeight.w700),
        titleLarge: h(19, FontWeight.w600, spacing: -0.2),
        titleMedium: h(16, FontWeight.w600, spacing: -0.1),
        titleSmall: h(14, FontWeight.w600, spacing: 0),
      )
      .apply(fontFamily: _fontFamily);
}
