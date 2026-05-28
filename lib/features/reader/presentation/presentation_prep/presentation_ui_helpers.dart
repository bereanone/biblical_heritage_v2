import 'dart:math' as math;

import 'package:flutter/material.dart';

double presentationUiScale(BuildContext context, double fontScale) {
  return MediaQuery.textScalerOf(context).scale(fontScale);
}

double presentationScaledSize(
  BuildContext context,
  double baseSize,
  double fontScale, {
  double min = 0,
  double max = double.infinity,
}) {
  final resolved = presentationUiScale(context, fontScale) * baseSize;
  return math.max(min, math.min(max, resolved));
}

TextStyle presentationTextStyle(
  BuildContext context,
  TextStyle? base,
  double fontScale, {
  Color? color,
  FontWeight? fontWeight,
  double? fontSize,
  double minFontSize = 12,
  double maxFontSize = 24,
  double? height,
  double? letterSpacing,
}) {
  final resolved = base ?? const TextStyle(fontSize: 14);
  final resolvedFontSize = fontSize ?? resolved.fontSize ?? 14;
  return resolved.copyWith(
    fontSize: presentationScaledSize(
      context,
      resolvedFontSize,
      fontScale,
      min: minFontSize,
      max: maxFontSize,
    ),
    color: color ?? resolved.color,
    fontWeight: fontWeight ?? resolved.fontWeight,
    height: height ?? resolved.height,
    letterSpacing: letterSpacing ?? resolved.letterSpacing,
  );
}

