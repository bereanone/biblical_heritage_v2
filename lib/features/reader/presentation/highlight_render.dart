import 'package:flutter/material.dart';

class HighlightRenderSpec {
  const HighlightRenderSpec({
    required this.backgroundColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color textColor;
}

enum HighlightLayerType {
  savedVerse,
  savedRange,
  temporarySelection,
  eLibrarySaved,
  eLibraryTemporary,
}

HighlightRenderSpec resolveHighlightRender(
  Color sourceColor,
  bool isNightMode, {
  HighlightLayerType layerType = HighlightLayerType.savedRange,
  Color? readerBackground,
}) {
  final baseBackground =
      readerBackground ??
      (isNightMode ? const Color(0xFF121212) : const Color(0xFFF6EEDD));
  final layerSpec = _highlightLayerSpec(layerType, isNightMode);
  final renderedOpacity = sourceColor.a * layerSpec.opacity;
  final background = Color.alphaBlend(
    sourceColor.withValues(alpha: renderedOpacity),
    baseBackground,
  );
  return HighlightRenderSpec(
    backgroundColor: background,
    textColor: highlightForegroundForBackground(background),
  );
}

const double minimumNormalTextContrastRatio = 4.5;

double highlightContrastRatio(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
  final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color highlightForegroundForBackground(
  Color background, {
  Color? semanticColor,
}) {
  if (semanticColor != null &&
      highlightContrastRatio(background, semanticColor) >=
          minimumNormalTextContrastRatio) {
    return semanticColor;
  }
  final blackContrast = highlightContrastRatio(background, Colors.black);
  final whiteContrast = highlightContrastRatio(background, Colors.white);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

_HighlightLayerSpec _highlightLayerSpec(
  HighlightLayerType layerType,
  bool isNightMode,
) {
  return switch (layerType) {
    HighlightLayerType.savedVerse =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.75)
          : const _HighlightLayerSpec(opacity: 0.30),
    HighlightLayerType.savedRange =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.70)
          : const _HighlightLayerSpec(opacity: 0.50),
    HighlightLayerType.temporarySelection =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.78)
          : const _HighlightLayerSpec(opacity: 0.60),
    HighlightLayerType.eLibrarySaved =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.68)
          : const _HighlightLayerSpec(opacity: 0.52),
    HighlightLayerType.eLibraryTemporary =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.82)
          : const _HighlightLayerSpec(opacity: 0.64),
  };
}

class _HighlightLayerSpec {
  const _HighlightLayerSpec({required this.opacity});

  final double opacity;
}
