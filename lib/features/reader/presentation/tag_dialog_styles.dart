import 'dart:math' as math;

import 'package:flutter/material.dart';

class TagDialogStyles {
  static const EdgeInsets outerInset = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 10,
  );
  static const double maxWidth = 1100;
  static const double maxHeight = 820;
  // Detail panel is the same width but intentionally shorter than main.
  static const double detailMaxHeight = 760;
  static const double borderRadius = 16;

  /// Size for the main #tag modal panel.
  /// On narrow screens, near-fullscreen. On wide screens, 90% wide / 88% tall,
  /// clamped to [maxWidth] × [maxHeight].
  static Size mainModalSize(Size screen) {
    final w = screen.width < 760
        ? screen.width - 24
        : math.min(screen.width * 0.90, maxWidth);
    final h = screen.height < 760
        ? screen.height - 24
        : math.min(screen.height * 0.88, maxHeight);
    return Size(w, h);
  }

  /// Size for the nested/detail panel that opens over the main #tag modal.
  /// Matches the main panel width; slightly shorter height so the reader
  /// beneath remains visibly tappable.
  static Size detailModalSize(Size screen) {
    final w = screen.width < 760
        ? screen.width - 24
        : math.min(screen.width * 0.90, maxWidth);
    final h = screen.height < 760
        ? screen.height - 60
        : math.min(screen.height * 0.82, detailMaxHeight);
    return Size(w, h);
  }

  static const Color cream = Color(0xFFF3E3D0);
  static const Color creamSurface = Color(0xFFF8F1E8);
  static const Color creamWarm = Color(0xFFF1E1CF);
  static const Color brown = Color(0xFF9D6225);
  static const Color brownDark = Color(0xFF7B4A1D);
  static const Color brownDeep = Color(0xFF4A2B12);
  static const Color outline = Color(0xFFC39B66);
  static const Color accentWash = Color(0xFFEEE1CA);
  static const Color cardTint = Color(0xFFF9F1E7);

  static const Color tagHeaderFill = Color(0xFFCBA983);
  static const Color tagHeaderBorder = Color(0xFFD2CDC3);
  static const Color tagSurface = Color(0xFFE9DCC8);
  static const Color tagSurfaceHigh = Color(0xFFE2D1B9);
  static const Color tagCardTint = Color(0xFFF4EDE3);
  static const Color tagAccentStrip = Color(0xFFDBC4A8);
  static const Color tagTitleInk = Color(0xFF2D2C2B);
  static const Color tagBodyInk = Color(0xFF483D30);
  static const Color tagAccentInk = Color(0xFF483D30);
  static const Color tagOutline = Color(0xFFD2CDC3);

  static const Color tagHeaderFillDark = Color(0xFF6F5234);
  static const Color tagHeaderBorderDark = Color(0xFF3B2E24);
  static const Color tagSurfaceDark = Color(0xFF15120F);
  static const Color tagSurfaceHighDark = Color(0xFF262018);
  static const Color tagCardTintDark = Color(0xFF221C16);
  static const Color tagAccentStripDark = Color(0xFF8C6A46);
  static const Color tagTitleInkDark = Color(0xFFF1ECE5);
  static const Color tagBodyInkDark = Color(0xFFE0D4C4);
  static const Color tagAccentInkDark = Color(0xFFF1E1CF);
  static const Color tagOutlineDark = Color(0xFF4B3D31);

  static Color surface(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagSurfaceDark : tagSurface;
  }

  static Color surfaceHigh(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? tagSurfaceHighDark
        : tagSurfaceHigh;
  }

  static Color card(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagCardTintDark : tagCardTint;
  }

  static Color title(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagTitleInkDark : tagTitleInk;
  }

  static Color body(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagBodyInkDark : tagBodyInk;
  }

  static Color mutedBody(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagBodyInkDark : tagBodyInk;
  }

  static Color disabledBody(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? tagBodyInkDark.withValues(alpha: 0.72)
        : tagBodyInk.withValues(alpha: 0.72);
  }

  static Color accent(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? tagAccentInkDark
        : tagAccentInk;
  }

  static Color outlineColor(ThemeData theme) {
    return theme.brightness == Brightness.dark ? tagOutlineDark : tagOutline;
  }

  static Color accentStripColor(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? tagAccentStripDark
        : tagAccentStrip;
  }

  static BoxDecoration headerDecoration(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const BoxDecoration(
            color: tagHeaderFillDark,
            border: Border(
              bottom: BorderSide(color: tagHeaderBorderDark, width: 0.6),
            ),
          )
        : const BoxDecoration(
            color: tagHeaderFill,
            border: Border(
              bottom: BorderSide(color: tagHeaderBorder, width: 0.6),
            ),
          );
  }

  static double scaledFontSize(double? baseSize, double fontScale) {
    return (baseSize ?? 14) * fontScale;
  }

  static double _clampFontSize(
    double resolved, {
    required double min,
    required double max,
  }) {
    return math.max(min, math.min(max, resolved));
  }

  static TextStyle scaledTextStyle(
    TextStyle? base,
    double fontScale, {
    Color? color,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    double? fontSize,
  }) {
    final resolved = base ?? const TextStyle(fontSize: 14);
    return resolved.copyWith(
      fontSize: fontSize ?? scaledFontSize(resolved.fontSize, fontScale),
      color: color ?? resolved.color,
      fontWeight: fontWeight ?? resolved.fontWeight,
      height: height ?? resolved.height,
      letterSpacing: letterSpacing ?? resolved.letterSpacing,
    );
  }

  static TextStyle titleTextStyle(
    ThemeData theme,
    double fontScale, {
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
    double? height,
    double? letterSpacing,
  }) {
    return scaledTextStyle(
      theme.textTheme.titleMedium,
      fontScale,
      color: color ?? title(theme),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontSize: _clampFontSize(
        scaledFontSize(theme.textTheme.titleMedium?.fontSize, fontScale),
        min: 20.0,
        max: 28.0,
      ),
    );
  }

  static TextStyle bodyTextStyle(
    ThemeData theme,
    double fontScale, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
  }) {
    return scaledTextStyle(
      theme.textTheme.bodyMedium,
      fontScale,
      color: color ?? body(theme),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontSize: _clampFontSize(
        scaledFontSize(theme.textTheme.bodyMedium?.fontSize, fontScale),
        min: 15.0,
        max: 22.0,
      ),
    );
  }

  static TextStyle labelTextStyle(
    ThemeData theme,
    double fontScale, {
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double? height,
    double? letterSpacing,
  }) {
    return scaledTextStyle(
      theme.textTheme.labelLarge ?? theme.textTheme.bodySmall,
      fontScale,
      color: color ?? body(theme),
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontSize: _clampFontSize(
        scaledFontSize(
          (theme.textTheme.labelLarge ?? theme.textTheme.bodySmall)?.fontSize,
          fontScale,
        ),
        min: 12.0,
        max: 17.0,
      ),
    );
  }

  static TextStyle buttonTextStyle(
    ThemeData theme,
    double fontScale, {
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double? height,
  }) {
    return scaledTextStyle(
      theme.textTheme.titleMedium,
      fontScale,
      color: color ?? accent(theme),
      fontWeight: fontWeight,
      height: height,
      fontSize: _clampFontSize(
        scaledFontSize(theme.textTheme.titleMedium?.fontSize, fontScale),
        min: 14.0,
        max: 16.5,
      ),
    );
  }

  static Widget fittedButtonLabel(
    String text, {
    TextAlign textAlign = TextAlign.center,
    int maxLines = 1,
    TextStyle? style,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: false,
        style: style,
      ),
    );
  }
}
