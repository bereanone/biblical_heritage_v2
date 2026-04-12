import 'package:flutter/material.dart';

import 'app_settings_service.dart';
import 'app_theme_mode.dart';

ThemeData buildAppTheme(
  AppThemeMode mode, {
  AppVisualSettings? settings,
}) {
  final isNight = mode == AppThemeMode.night;
  final background = settings?.backgroundColor ??
      (isNight ? const Color(0xFF111214) : const Color(0xFFF6F1E4));
  final text = settings?.textColor ??
      (isNight ? const Color(0xFFF1F1F1) : const Color(0xFF2B2316));
  final appBar = settings?.appBarColor ??
      (isNight ? const Color(0xFF1C1D20) : const Color(0xFFEDE6D6));
  final bottomBar = settings?.bottomBarColor ?? appBar;
  final accent = settings?.accentColor ??
      (isNight ? const Color(0xFF77A9FF) : const Color(0xFF8B6F47));
  final primary = accent;
  final secondary = text.withValues(alpha: isNight ? 0.92 : 0.82);
  final surface = Color.alphaBlend(
    isNight ? const Color(0x22111111) : const Color(0x08FFFFFF),
    background,
  );
  final surfaceHigh = Color.alphaBlend(
    isNight ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
    background,
  );
  final onPrimary = isNight ? const Color(0xFF0E1116) : Colors.white;
  final outline = Color.alphaBlend(
    isNight ? const Color(0x44FFFFFF) : const Color(0x22000000),
    background,
  );

  final colorScheme = ColorScheme(
    brightness: isNight ? Brightness.dark : Brightness.light,
    primary: primary,
    onPrimary: onPrimary,
    secondary: secondary,
    onSecondary: isNight ? const Color(0xFF241D15) : Colors.white,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: surface,
    onSurface: text,
    outline: outline,
    tertiary: accent,
    onTertiary: onPrimary,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHigh,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: appBar,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: bottomBar,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: text,
        fontFamily: 'PlayfairDisplay',
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: text,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: text,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: secondary.withValues(alpha: 0.14),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: TextStyle(
        color: text,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    dividerColor: outline,
  );
}
