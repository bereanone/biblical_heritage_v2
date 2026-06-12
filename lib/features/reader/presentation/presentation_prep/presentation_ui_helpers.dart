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

void showReadableSnackBar(
  BuildContext context,
  String message, {
  required double fontScale,
  bool isRapid = false,
  String dismissLabel = 'Dismiss',
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final theme = Theme.of(context);
  final textStyle = presentationTextStyle(
    context,
    theme.textTheme.bodyMedium,
    fontScale,
    color: theme.colorScheme.onInverseSurface,
    fontWeight: isRapid ? FontWeight.w500 : FontWeight.w600,
    fontSize: isRapid ? 13 : 15,
    minFontSize: isRapid ? 12 : 13,
    maxFontSize: isRapid ? 15 : 18,
    height: 1.2,
  );

  if (isRapid) {
    messenger.removeCurrentSnackBar();
  } else {
    messenger.hideCurrentSnackBar();
    messenger.clearSnackBars();
  }
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: theme.colorScheme.inverseSurface,
      content: Text(message, style: textStyle),
      action: isRapid
          ? null
          : SnackBarAction(
              label: dismissLabel,
              textColor: theme.colorScheme.onInverseSurface,
              onPressed: () => messenger.hideCurrentSnackBar(),
            ),
      duration: isRapid ? const Duration(milliseconds: 1100) : duration,
      elevation: 6,
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: (isRapid ? 8 : 16) + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isRapid ? 12 : 16,
        vertical: isRapid ? 10 : 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
