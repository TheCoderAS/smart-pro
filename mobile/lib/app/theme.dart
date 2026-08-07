import 'package:flutter/material.dart';

/// Material 3 light and dark themes.
///
/// The app follows the system brightness by default; an explicit toggle
/// lands with the settings feature (PLAN.md §6.11).
const _seed = Color(0xFF0057B8);

final ThemeData lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed),
);

final ThemeData darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  ),
);
