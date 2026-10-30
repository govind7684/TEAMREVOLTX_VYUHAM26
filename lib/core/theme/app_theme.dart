import 'package:flutter/material.dart';

/// Visual identity: deep navy and teal/cyan (the CIVINEX logo colours), clean
/// cards, bold titles. Light and dark themes share the same structure.
class AppTheme {
  /// Deepest navy: dark-theme background and hero panels.
  static const ink = Color(0xFF06121F);

  /// Dark cards and sheets, one step above [ink].
  static const inkSoft = Color(0xFF0B1F33);

  /// Brand navy.
  static const navy = Color(0xFF0B2545);

  /// Bright teal/cyan: accent on dark backgrounds, filled buttons in dark mode.
  static const accent = Color(0xFF14D6C4);

  /// Darker teal with enough contrast for text and buttons on white.
  static const accentDeep = Color(0xFF0A7F77);

  /// Red for critical items and errors only.
  static const alert = Color(0xFFE5484D);

  /// Amber for warnings and highlights.
  static const ember = Color(0xFFFFB020);

  /// Heavy font (Inter Display Black, SIL Open Font License) for the wordmark
  /// and hero headlines only.
  static const displayFont = 'Display';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Heavy, tight style for hero headlines.
  static TextStyle display(TextStyle? base, {double? size, Color? color, double spacing = 0.2}) =>
      (base ?? const TextStyle()).copyWith(
        fontFamily: displayFont,
        fontWeight: FontWeight.w900,
        fontSize: size,
        color: color,
        letterSpacing: spacing,
        height: 1.08,
      );

  /// The accent that suits the current brightness (for icons and text).
  static Color accentOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? accent : accentDeep;

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final primary = dark ? accent : accentDeep;
    final base = ColorScheme.fromSeed(seedColor: accent, brightness: b);
    final scheme = base.copyWith(
      primary: primary,
      onPrimary: dark ? ink : Colors.white,
      secondary: dark ? const Color(0xFF7FE9DF) : navy,
      onSecondary: dark ? ink : Colors.white,
      tertiary: ember,
      error: dark ? const Color(0xFFFF6B70) : const Color(0xFFB3261E),
      surface: dark ? ink : const Color(0xFFF6F9FC),
      onSurface: dark ? Colors.white : const Color(0xFF0B1F33),
      onSurfaceVariant: dark ? const Color(0xFFA6B9CC) : const Color(0xFF51657A),
      surfaceContainerLowest: dark ? ink : Colors.white,
      surfaceContainerLow: dark ? inkSoft : Colors.white,
      surfaceContainer: dark ? const Color(0xFF0E2740) : const Color(0xFFEDF3F8),
      surfaceContainerHigh: dark ? const Color(0xFF123049) : const Color(0xFFE4ECF3),
      outlineVariant: dark ? const Color(0xFF1B3A56) : const Color(0xFFD5E0EA),
      errorContainer: dark ? const Color(0xFF4A1519) : const Color(0xFFFFDAD9),
      onErrorContainer: dark ? const Color(0xFFFFDAD9) : const Color(0xFF410004),
    );

    final text = ThemeData(brightness: b).textTheme;
    final textTheme = text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );

    const radius = 16.0;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final btnFg = dark ? ink : Colors.white;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
            fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: btnFg,
          disabledBackgroundColor: scheme.outlineVariant,
          shape: StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          minimumSize: const Size(0, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.7), width: 1.2),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          minimumSize: const Size(0, 46),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: btnFg,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.transparent : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        selectedColor: primary,
        secondaryLabelStyle: TextStyle(color: btnFg, fontWeight: FontWeight.w700),
        checkmarkColor: btnFg,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(const StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? btnFg : scheme.onSurface),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF081A2B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: dark ? 0.18 : 0.14),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? primary : scheme.onSurfaceVariant)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? primary : scheme.onSurfaceVariant,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? const Color(0xFF081A2B) : Colors.white,
        indicatorColor: primary.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: primary),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800),
        dividerColor: scheme.outlineVariant,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(iconColor: primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? btnFg : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : scheme.surfaceContainerHigh),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? inkSoft : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? inkSoft : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
    );
  }

  static Color priorityColor(String name) {
    switch (name) {
      case 'critical':
        return const Color(0xFFE5484D);
      case 'high':
        return const Color(0xFFF08A24);
      case 'medium':
        return const Color(0xFFE0B100);
      default:
        return const Color(0xFF2FB36B);
    }
  }
}
