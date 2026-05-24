import 'package:flutter/material.dart';

class LibraryFontScaleScope extends InheritedWidget {
  const LibraryFontScaleScope({
    super.key,
    required this.scale,
    required super.child,
  });

  final double scale;

  static double of(BuildContext context, {double fallback = 1.0}) {
    return context
            .dependOnInheritedWidgetOfExactType<LibraryFontScaleScope>()
            ?.scale ??
        fallback;
  }

  @override
  bool updateShouldNotify(LibraryFontScaleScope oldWidget) {
    return scale != oldWidget.scale;
  }
}

double libraryFontScaleOf(BuildContext context, {double fallback = 1.0}) {
  return LibraryFontScaleScope.of(context, fallback: fallback);
}

double _clampScale(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

double libraryBodyScale(double value) => _clampScale(value, 0.85, 1.60);

double libraryControlScale(double value) =>
    _clampScale(value * 0.90, 0.85, 1.25);

double libraryTitleScale(double value) => _clampScale(value * 1.15, 0.95, 1.80);

double libraryCaptionScale(double value) =>
    _clampScale(value * 0.82, 0.75, 1.05);

TextStyle libraryScaledTextStyle(
  TextStyle? base,
  double fontScale, {
  double multiplier = 1.0,
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
  double? fontSize,
  double minFontSize = 10,
  double maxFontSize = 48,
}) {
  final resolved = base ?? const TextStyle(fontSize: 14);
  final resolvedFontSize =
      fontSize ??
      ((resolved.fontSize ?? 14) * fontScale * multiplier)
          .clamp(minFontSize, maxFontSize)
          .toDouble();
  return resolved.copyWith(
    fontSize: resolvedFontSize,
    color: color ?? resolved.color,
    fontWeight: fontWeight ?? resolved.fontWeight,
    height: height ?? resolved.height,
    letterSpacing: letterSpacing ?? resolved.letterSpacing,
  );
}

TextStyle libraryBodyTextStyle(
  BuildContext context,
  TextStyle? base, {
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return libraryScaledTextStyle(
    base,
    libraryBodyScale(libraryFontScaleOf(context)),
    multiplier: 1.0,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle libraryTitleTextStyle(
  BuildContext context,
  TextStyle? base, {
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return libraryScaledTextStyle(
    base,
    libraryTitleScale(libraryFontScaleOf(context)),
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle libraryControlTextStyle(
  BuildContext context,
  TextStyle? base, {
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return libraryScaledTextStyle(
    base,
    libraryControlScale(libraryFontScaleOf(context)),
    multiplier: 1.0,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle libraryCaptionTextStyle(
  BuildContext context,
  TextStyle? base, {
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return libraryScaledTextStyle(
    base,
    libraryCaptionScale(libraryFontScaleOf(context)),
    multiplier: 1.0,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}
