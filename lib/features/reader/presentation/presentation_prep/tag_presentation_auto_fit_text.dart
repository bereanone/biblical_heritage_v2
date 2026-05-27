import 'dart:math' as math;

import 'package:flutter/material.dart';

class TagPresentationAutoFitText extends StatelessWidget {
  const TagPresentationAutoFitText({
    super.key,
    required this.text,
    required this.style,
    required this.minFontSize,
    required this.maxFontSize,
    this.maxLines,
    this.textAlign = TextAlign.left,
    this.color,
    this.fontWeight,
    this.letterSpacing,
    this.height,
    this.allowScrollWhenOverflow = false,
    this.overflowWarningText,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final double maxFontSize;
  final int? maxLines;
  final TextAlign textAlign;
  final Color? color;
  final FontWeight? fontWeight;
  final double? letterSpacing;
  final double? height;
  final bool allowScrollWhenOverflow;
  final String? overflowWarningText;

  @override
  Widget build(BuildContext context) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = measurePresentationTextFit(
          text: cleaned,
          style: style,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          minFontSize: minFontSize,
          maxFontSize: maxFontSize,
          maxLines: maxLines,
          textAlign: textAlign,
          height: height,
          letterSpacing: letterSpacing,
        );

        final renderedText = Text(
          cleaned,
          textAlign: textAlign,
          softWrap: true,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
          style: style.copyWith(
            fontSize: fit.fontSize,
            color: color ?? style.color,
            fontWeight: fontWeight ?? style.fontWeight,
            letterSpacing: letterSpacing ?? style.letterSpacing,
            height: height ?? style.height,
          ),
        );

        if (fit.fits) return renderedText;

        final warning = overflowWarningText?.trim();
        if (allowScrollWhenOverflow && maxLines == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (warning != null && warning.isNotEmpty) ...[
                Text(
                  warning,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    fontSize: math.max(11.0, minFontSize * 0.8),
                    color: const Color(0xFFD7CBB4),
                    fontWeight: FontWeight.w600,
                    letterSpacing: letterSpacing ?? style.letterSpacing,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  child: renderedText,
                ),
              ),
            ],
          );
        }

        if (warning != null && warning.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                warning,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  fontSize: math.max(11.0, minFontSize * 0.8),
                  color: const Color(0xFFD7CBB4),
                  fontWeight: FontWeight.w600,
                  letterSpacing: letterSpacing ?? style.letterSpacing,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              renderedText,
            ],
          );
        }

        return renderedText;
      },
    );
  }
}

class TagPresentationTextFitResult {
  const TagPresentationTextFitResult({
    required this.fontSize,
    required this.fits,
  });

  final double fontSize;
  final bool fits;
}

TagPresentationTextFitResult measurePresentationTextFit({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double maxHeight,
  required double minFontSize,
  required double maxFontSize,
  required int? maxLines,
  required TextAlign textAlign,
  required double? height,
  required double? letterSpacing,
}) {
  if (maxWidth <= 0 || maxHeight <= 0) {
    return TagPresentationTextFitResult(fontSize: minFontSize, fits: false);
  }

  final top = math.max(minFontSize, maxFontSize);
  final bottom = math.min(minFontSize, maxFontSize);
  var best = bottom;
  var bestFits = false;

  for (var fontSize = top; fontSize >= bottom; fontSize -= 1.0) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          fontSize: fontSize,
          color: style.color,
          fontWeight: style.fontWeight,
          letterSpacing: letterSpacing ?? style.letterSpacing,
          height: height ?? style.height,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);

    if (painter.width <= maxWidth + 0.5 && painter.height <= maxHeight + 0.5) {
      return TagPresentationTextFitResult(fontSize: fontSize, fits: true);
    }
    best = fontSize;
    bestFits = false;
  }

  return TagPresentationTextFitResult(
    fontSize: best.clamp(bottom, top),
    fits: bestFits,
  );
}
