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
}) {
  final baseBackground = isNightMode
      ? const Color(0xFF121212)
      : const Color(0xFFF6EEDD);
  final layerSpec = _highlightLayerSpec(layerType, isNightMode);
  final adjustedSource = isNightMode
      ? _nightAdjustedHighlightColor(sourceColor, layerType)
      : sourceColor;
  final mixed = Color.alphaBlend(
    adjustedSource.withValues(alpha: layerSpec.opacity),
    baseBackground,
  );
  final background = isNightMode
      ? Color.lerp(mixed, adjustedSource, layerSpec.lift) ?? mixed
      : mixed;
  final backgroundWithContrast = _ensureReadableContrast(
    background,
    isNightMode ? Colors.white : const Color(0xFF2F2014),
    isNightMode: isNightMode,
  );
  final text = _preferredHighlightTextColor(backgroundWithContrast, isNightMode);
  return HighlightRenderSpec(
    backgroundColor: backgroundWithContrast,
    textColor: text,
  );
}

_HighlightLayerSpec _highlightLayerSpec(
  HighlightLayerType layerType,
  bool isNightMode,
) {
  return switch (layerType) {
    HighlightLayerType.savedVerse =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.40, lift: 0.08)
          : const _HighlightLayerSpec(opacity: 0.30, lift: 0.0),
    HighlightLayerType.savedRange =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.70, lift: 0.18)
          : const _HighlightLayerSpec(opacity: 0.50, lift: 0.0),
    HighlightLayerType.temporarySelection =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.78, lift: 0.20)
          : const _HighlightLayerSpec(opacity: 0.60, lift: 0.0),
    HighlightLayerType.eLibrarySaved =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.68, lift: 0.17)
          : const _HighlightLayerSpec(opacity: 0.52, lift: 0.0),
    HighlightLayerType.eLibraryTemporary =>
      isNightMode
          ? const _HighlightLayerSpec(opacity: 0.82, lift: 0.22)
          : const _HighlightLayerSpec(opacity: 0.64, lift: 0.0),
  };
}

Color _nightAdjustedHighlightColor(Color sourceColor, HighlightLayerType layerType) {
  if (!_isWarmHighlight(sourceColor)) return sourceColor;

  final hsl = HSLColor.fromColor(sourceColor);
  final targetLightness = switch (layerType) {
    HighlightLayerType.savedVerse => 0.34,
    HighlightLayerType.savedRange => 0.27,
    HighlightLayerType.temporarySelection => 0.23,
    HighlightLayerType.eLibrarySaved => 0.29,
    HighlightLayerType.eLibraryTemporary => 0.25,
  };
  final targetSaturation = switch (layerType) {
    HighlightLayerType.savedVerse => 0.68,
    HighlightLayerType.savedRange => 0.76,
    HighlightLayerType.temporarySelection => 0.82,
    HighlightLayerType.eLibrarySaved => 0.72,
    HighlightLayerType.eLibraryTemporary => 0.78,
  };

  final adjustedSaturation =
      hsl.saturation > targetSaturation ? targetSaturation : hsl.saturation;
  final adjustedLightness =
      hsl.lightness > targetLightness ? targetLightness : hsl.lightness;
  return hsl
      .withSaturation(adjustedSaturation)
      .withLightness(adjustedLightness)
      .toColor();
}

bool _isWarmHighlight(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.hue >= 28 &&
      hsl.hue <= 92 &&
      hsl.saturation >= 0.18 &&
      hsl.lightness >= 0.22;
}

Color _ensureReadableContrast(
  Color background,
  Color targetTextColor, {
  required bool isNightMode,
}) {
  const minContrast = 4.5;
  var candidate = background;
  for (var i = 0; i < 8; i++) {
    if (_contrastRatio(candidate, targetTextColor) >= minContrast) {
      return candidate;
    }
    candidate = Color.lerp(
          candidate,
          isNightMode ? const Color(0xFF050506) : const Color(0xFFFDF8EE),
          0.12,
        ) ??
        candidate;
  }
  return candidate;
}

Color _preferredHighlightTextColor(Color background, bool isNightMode) {
  final preferred = isNightMode
      ? Colors.white
      : const Color(0xFF2F2014);
  if (_contrastRatio(background, preferred) >= 4.5) {
    return preferred;
  }

  final fallback = preferred == Colors.white ? Colors.black : Colors.white;
  return _contrastRatio(background, fallback) > _contrastRatio(background, preferred)
      ? fallback
      : preferred;
}

double _contrastRatio(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

class _HighlightLayerSpec {
  const _HighlightLayerSpec({required this.opacity, required this.lift});

  final double opacity;
  final double lift;
}
