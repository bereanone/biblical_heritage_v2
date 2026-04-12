import 'package:flutter/material.dart';

Color viewerBookGroupColor(int bookNumber) {
  const rules = <(int, int, int)>[
    (1, 5, 0xFFD87C6F),
    (6, 17, 0xFFA68CC6),
    (18, 22, 0xFF6FA8DC),
    (23, 27, 0xFF76C7B7),
    (28, 39, 0xFFEBCB6B),
    (40, 43, 0xFFE9967A),
    (44, 44, 0xFFB39F8F),
    (45, 57, 0xFF8CA0AD),
    (58, 65, 0xFF82C4D9),
    (66, 66, 0xFFD67CA0),
  ];

  for (final rule in rules) {
    if (bookNumber >= rule.$1 && bookNumber <= rule.$2) {
      return Color(rule.$3);
    }
  }

  return Colors.grey.shade400;
}

Color viewerGroupTone(
  BuildContext context,
  Color baseColor, {
  required bool fill,
}) {
  final theme = Theme.of(context);
  final surface = theme.colorScheme.surface;
  final isDark = theme.brightness == Brightness.dark;

  if (fill) {
    return Color.alphaBlend(
      baseColor.withValues(alpha: isDark ? 0.16 : 0.12),
      surface,
    );
  }

  return Color.alphaBlend(
    baseColor.withValues(alpha: isDark ? 0.88 : 0.78),
    surface,
  );
}
