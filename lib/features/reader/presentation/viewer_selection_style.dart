import 'package:flutter/material.dart';

Color viewerSelectedVerseColor(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) {
    return const Color(0xFF202020);
  }
  return const Color(0xFFF3E5D6);
}
