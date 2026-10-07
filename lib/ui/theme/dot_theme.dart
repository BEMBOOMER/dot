import 'package:flutter/material.dart';

class DotColors {
  static const bg = Color(0xFFF7F7F8);
  static const ink = Color(0xFF0E0E10);
  static const bgDark = Color(0xFF0B0B0D);
  static const surfaceDark = Color(0xFF16161A);
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF7B84B)
      : const Color(0xFFF5A524);
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF222228)
      : const Color(0xFFEFEFF2);
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF34D27A)
      : const Color(0xFF1DB954);
  static Color secondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF9A9AA3)
      : const Color(0xFF6E6E76);
}

final lightTheme = _theme(false);
final darkTheme = _theme(true);
ThemeData _theme(bool dark) {
  final text = dark ? const Color(0xFFF4F4F6) : DotColors.ink;
  final secondary = dark ? const Color(0xFF9A9AA3) : const Color(0xFF6E6E76);
  final accent = dark ? const Color(0xFF6C83FF) : const Color(0xFF3D5AFE);
  final muted = dark ? const Color(0xFF222228) : const Color(0xFFEFEFF2);
  final surface = dark ? DotColors.surfaceDark : Colors.white;
  final hairline = dark ? const Color(0xFF2A2A31) : const Color(0xFFE6E6EA);
  TextStyle type(
    double size,
    double height,
    double weight, {
    double spacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    height: height / size,
    fontVariations: [FontVariation('wght', weight)],
    fontWeight: weight >= 600
        ? FontWeight.w600
        : weight >= 500
        ? FontWeight.w500
        : FontWeight.w400,
    letterSpacing: spacing,
    color: color ?? text,
  );
  final button = type(15, 22, 600);
  final shape = const StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: dark ? DotColors.bgDark : DotColors.bg,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: accent,
          secondary: accent,
          onSecondary: Colors.white,
          surfaceContainerHighest: muted,
          outlineVariant: hairline,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: text,
          onSurfaceVariant: secondary,
          outline: hairline,
          error: dark ? const Color(0xFFFF6369) : const Color(0xFFE5484D),
        ),
    textTheme: TextTheme(
      displayLarge: type(34, 40, 650, spacing: -0.8),
      displaySmall: type(34, 40, 650, spacing: -0.8),
      headlineLarge: type(22, 28, 650, spacing: -0.4),
      headlineMedium: type(22, 28, 650, spacing: -0.4),
      headlineSmall: type(16, 22, 600, spacing: -0.2),
      titleSmall: type(16, 22, 600, spacing: -0.2),
      displayMedium: type(34, 40, 650, spacing: -0.8),
      titleLarge: type(22, 28, 650, spacing: -0.4),
      titleMedium: type(16, 22, 600, spacing: -0.2),
      bodyLarge: type(15, 22, 400),
      bodyMedium: type(15, 22, 400),
      bodySmall: type(13, 18, 500, color: secondary),
      labelLarge: button,
      labelMedium: type(13, 18, 500, color: secondary),
      labelSmall: type(13, 18, 500, color: secondary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? DotColors.bgDark : DotColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: type(22, 28, 650, spacing: -0.4),
      iconTheme: IconThemeData(color: secondary, size: 22),
    ),
    iconTheme: IconThemeData(color: secondary, size: 22),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: muted,
      selectedColor: accent,
      showCheckmark: false,
      side: BorderSide.none,
      shape: shape,
      labelStyle: type(13, 18, 500),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : muted,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: shape,
        textStyle: button,
        minimumSize: const Size(0, 52),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: shape,
        textStyle: button,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
