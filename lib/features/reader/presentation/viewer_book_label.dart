import 'package:flutter/material.dart';

class ViewerBookLabel extends StatelessWidget {
  const ViewerBookLabel({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor =
        brightness == Brightness.light ? Colors.black : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: color,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              decoration:
                  selected ? TextDecoration.underline : TextDecoration.none,
              color: textColor,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}
