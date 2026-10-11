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
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;
  final double minimumTapHeight;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor = brightness == Brightness.light
        ? Colors.black
        : Colors.white;
    final labelStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      decoration: selected ? TextDecoration.underline : TextDecoration.none,
      color: textColor,
      height: 1.05,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
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
            maxLines: minimumTapHeight > 0 ? 4 : 1,
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
