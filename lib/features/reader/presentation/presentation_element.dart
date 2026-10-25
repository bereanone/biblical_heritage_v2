import 'package:flutter/material.dart';
import '../data/presentation/note_image_layout.dart';

String presentationElementKey(String itemId, String part) =>
    'item:$itemId:$part';

/// Selection lives in the editor; renderers only expose their real text blocks.
class PresentationElementScope extends InheritedWidget {
  const PresentationElementScope({
    super.key,
    required super.child,
    required this.editing,
    required this.selected,
    required this.select,
    required this.reportBaseFont,
    this.registerImage,
    this.changeImage,
  });
  final bool editing;
  final String? selected;
  final void Function(String, NoteImageLayout)? registerImage;
  final void Function(String, NoteImageLayout)? changeImage;
  final void Function(String key, String label, double font, Offset position)
  select;
  final void Function(String key, double font) reportBaseFont;
  static PresentationElementScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PresentationElementScope>();
  @override
  bool updateShouldNotify(PresentationElementScope old) =>
      editing != old.editing || selected != old.selected;
}

class PresentationElement extends StatelessWidget {
  const PresentationElement({
    super.key,
    required this.elementKey,
    required this.label,
    required this.defaultFontSize,
    required this.child,
  });
  final String elementKey, label;
  final double defaultFontSize;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = PresentationElementScope.maybeOf(context);
    if (scope == null) return child;
    scope.reportBaseFont(elementKey, defaultFontSize);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => scope.select(
        elementKey,
        label,
        defaultFontSize,
        details.globalPosition,
      ),
      onTapUp: scope.editing
          ? (details) => scope.select(
              elementKey,
              label,
              defaultFontSize,
              details.globalPosition,
            )
          : null,
      child: Container(
        foregroundDecoration: scope.editing && scope.selected == elementKey
            ? BoxDecoration(
                border: Border.all(color: const Color(0xFFE0BE87), width: 2),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: child,
      ),
    );
  }
}
