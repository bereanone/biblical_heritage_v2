import 'package:flutter/material.dart';

Color viewerSelectedVerseColor(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) {
    return const Color(0xFF7B6856);
  }
  final surface = theme.colorScheme.surface;
  return Color.alphaBlend(const Color(0x66CFB49A), surface);
}
