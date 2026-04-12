import 'package:flutter/material.dart';

class HighlightRenderSpec {
  const HighlightRenderSpec({
    required this.backgroundColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color textColor;
}

HighlightRenderSpec resolveHighlightRender(Color sourceColor, bool isNightMode) {
  final baseBackground =
      isNightMode ? const Color(0xFF121212) : const Color(0xFFF6EEDD);
  final mixed = Color.alphaBlend(
    sourceColor.withValues(alpha: isNightMode ? 0.58 : 0.3),
    baseBackground,
  );
  final background =
      isNightMode ? Color.lerp(mixed, sourceColor, 0.12) ?? mixed : mixed;
  final text = background.computeLuminance() > 0.45
      ? const Color(0xFF2F2014)
      : Colors.white;
  return HighlightRenderSpec(
    backgroundColor: background,
    textColor: text,
  );
}
