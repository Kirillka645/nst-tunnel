import 'package:flutter/material.dart';

/// NST Tunnel design system.
///
/// Mirrors the Android app's `res/values/colors.xml` and `res/values-night/colors.xml`
/// so light/dark mode looks identical across the two platforms. The colour names
/// follow Material 3 tokens 1:1, which means `Theme.of(context).colorScheme.secondary`
/// returns brand orange on every screen — no hard-coded hex anywhere downstream.
class AppTheme {
  AppTheme._();

  // ---- Brand constants ------------------------------------------------------
  static const Color brandOrange = Color(0xFFE96A0A);
  static const Color brandOrangeDark = Color(0xFFFF9A4D);

  // Connection-state colours (used by ConnectionFab, server pings).
  static const Color connectedDark = Color(0xFF5BDBAE);
  static const Color connectedLight = Color(0xFF006D52);
  static const Color connectingAmber = Color(0xFFF4B400);
  static const Color disconnectedGrey = Color(0xFF9E9A93);

  // ---- LIGHT colour scheme --------------------------------------------------
  static const ColorScheme _light = ColorScheme(
    brightness: Brightness.light,

    primary: Color(0xFF1F1B16),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF2EBE0),
    onPrimaryContainer: Color(0xFF2A241B),
    inversePrimary: Color(0xFFE8E1D5),

    secondary: Color(0xFFB85B0E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFDDB3),
    onSecondaryContainer: Color(0xFF2C1700),

    tertiary: Color(0xFF006D52),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF79F8C9),
    onTertiaryContainer: Color(0xFF002117),

    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),

    surface: Color(0xFFFFFBF5),
    onSurface: Color(0xFF1F1B16),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAF4EC),
    surfaceContainer: Color(0xFFF5EFE5),
    surfaceContainerHigh: Color(0xFFEFE9DF),
    surfaceContainerHighest: Color(0xFFE9E3D9),
    onSurfaceVariant: Color(0xFF4D4639),
    surfaceTint: Color(0xFF1F1B16),
    inverseSurface: Color(0xFF34302A),
    onInverseSurface: Color(0xFFF8EFE2),

    outline: Color(0xFF7F7768),
    outlineVariant: Color(0xFFD0C7B6),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // ---- DARK colour scheme ---------------------------------------------------
  static const ColorScheme _dark = ColorScheme(
    brightness: Brightness.dark,

    primary: Color(0xFFECE7E1),
    onPrimary: Color(0xFF312E27),
    primaryContainer: Color(0xFF48433C),
    onPrimaryContainer: Color(0xFFF2EBE0),
    inversePrimary: Color(0xFF1F1B16),

    secondary: Color(0xFFFF9A4D),
    onSecondary: Color(0xFF4A2400),
    secondaryContainer: Color(0xFF6B3700),
    onSecondaryContainer: Color(0xFFFFDDB3),

    tertiary: Color(0xFF5BDBAE),
    onTertiary: Color(0xFF003828),
    tertiaryContainer: Color(0xFF00513B),
    onTertiaryContainer: Color(0xFF79F8C9),

    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),

    surface: Color(0xFF15140F),
    onSurface: Color(0xFFE8E2DA),
    surfaceContainerLowest: Color(0xFF100F0A),
    surfaceContainerLow: Color(0xFF1D1C16),
    surfaceContainer: Color(0xFF21201A),
    surfaceContainerHigh: Color(0xFF2C2A24),
    surfaceContainerHighest: Color(0xFF37362F),
    onSurfaceVariant: Color(0xFFD0C7B6),
    surfaceTint: Color(0xFFECE7E1),
    inverseSurface: Color(0xFFE8E2DA),
    onInverseSurface: Color(0xFF34302A),

    outline: Color(0xFF999182),
    outlineVariant: Color(0xFF4D4639),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // ---- Public accessors -----------------------------------------------------
  static ThemeData light() => _build(_light);
  static ThemeData dark() => _build(_dark);

  /// Builds the actual `ThemeData` from a colour scheme. We tweak a handful of
  /// component themes (cards, dialogs, lists) so they feel native on desktop
  /// without losing the M3 look.
  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.secondary, width: 2),
        ),
      ),
    );
  }
}
