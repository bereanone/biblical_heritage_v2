import 'package:flutter/material.dart';

const popupPadding = EdgeInsets.all(12.0);
const popupRadius = BorderRadius.all(Radius.circular(14));

BoxDecoration popupDecoration(BuildContext context) {
  final background = Theme.of(context).dialogTheme.backgroundColor ??
      Theme.of(context).colorScheme.surface;
  return BoxDecoration(
    color: background,
    borderRadius: popupRadius,
    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
  );
}
