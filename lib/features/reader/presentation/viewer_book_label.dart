import 'package:flutter/material.dart';

class ViewerBookLabel extends StatelessWidget {
  const ViewerBookLabel({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.fontSize = 14,
    this.minimumTapHeight = 0,
    this.expandWidth = false,
    this.singleLine = false,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;
  final double minimumTapHeight;
  final bool expandWidth;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor = brightness == Brightness.light
        ? Colors.black
        : Colors.white;
    final labelStyle = DefaultTextStyle.of(context).style.merge(TextStyle(
      fontSize: fontSize,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      decoration: selected ? TextDecoration.underline : TextDecoration.none,
      color: textColor,
      height: 1.05,
    ));
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final contentWidth =
        (painter.width.ceilToDouble() + (minimumTapHeight > 0 ? 16 : 12)).clamp(
          48.0,
          double.infinity,
        );
    painter.dispose();

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: expandWidth
              ? double.infinity
              : (minimumTapHeight > 0 ? contentWidth : null),
          constraints: BoxConstraints(
            minHeight: minimumTapHeight,
            minWidth: minimumTapHeight > 0 ? 48 : 0,
          ),
          padding: minimumTapHeight > 0
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: color,
          child: Text(
            label,
            textAlign: expandWidth ? TextAlign.center : null,
            maxLines: singleLine ? 1 : (minimumTapHeight > 0 ? 4 : 1),
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
      ),
    );
    return minimumTapHeight > 0 && !expandWidth
        ? SizedBox(width: contentWidth, child: button)
        : button;
  }
}

/// One shared size for the two-column picker, capped by its widest book name.
/// Measure bold too so selecting a book never causes clipping or wrapping.
double fitBookPickerFontSize({
  required Iterable<String> labels,
  required double requestedSize,
  required double availableTextWidth,
  required TextDirection textDirection,
  TextStyle baseStyle = const TextStyle(),
}) {
  final names = labels.toList();
  bool fits(double size) {
    for (final label in names) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: baseStyle.copyWith(
          fontSize: size, fontWeight: FontWeight.w700, height: 1.05)),
        textDirection: textDirection, maxLines: 1,
      )..layout();
      final tooWide = painter.width.ceilToDouble() > availableTextWidth - 8;
      painter.dispose();
      if (tooWide) return false;
    }
    return true;
  }
  if (fits(requestedSize)) return requestedSize;
  var low = 0.1;
  var high = requestedSize;
  for (var i = 0; i < 18; i++) {
    final mid = (low + high) / 2;
    if (fits(mid)) { low = mid; } else { high = mid; }
  }
  return low;
}
