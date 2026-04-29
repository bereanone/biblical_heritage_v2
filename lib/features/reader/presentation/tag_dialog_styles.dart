import 'package:flutter/material.dart';

class TagDialogStyles {
  static const EdgeInsets outerInset = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 10,
  );
  static const double maxWidth = 744;
  static const double maxHeight = 700;
  static const double borderRadius = 16;

  static const Color cream = Color(0xFFF3E3D0);
  static const Color creamSurface = Color(0xFFF8F1E8);
  static const Color creamWarm = Color(0xFFF1E1CF);
  static const Color brown = Color(0xFF9D6225);
  static const Color brownDark = Color(0xFF7B4A1D);
  static const Color brownDeep = Color(0xFF4A2B12);
  static const Color outline = Color(0xFFC39B66);
  static const Color accentWash = Color(0xFFEEE1CA);
  static const Color cardTint = Color(0xFFF9F1E7);

  static Color surface(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : creamSurface;
  }

  static Color surfaceHigh(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : creamWarm;
  }

  static Color card(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : cardTint;
  }

  static Color title(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : brownDeep;
  }

  static Color body(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : brownDark;
  }

  static Color accent(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : brown;
  }

  static Color outlineColor(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.outline
        : outline;
  }

  static Widget fittedButtonLabel(
    String text, {
    TextAlign textAlign = TextAlign.center,
    int maxLines = 1,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: false,
      ),
    );
  }
}
