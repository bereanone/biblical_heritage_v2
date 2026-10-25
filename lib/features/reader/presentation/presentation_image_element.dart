import 'package:flutter/material.dart';
import '../data/presentation/note_image_layout.dart';
import 'presentation_element.dart';

/// Image movement is a draft edit, snapped to the authored grid and bounded
/// without changing the image's size or the original attachment.
class PresentationImageElement extends StatefulWidget {
  const PresentationImageElement({
    super.key,
    required this.itemId,
    required this.layout,
    required this.stageSize,
    required this.scale,
    required this.child,
  });
  final String itemId;
  final NoteImageLayout layout;
  final Size stageSize;
  final double scale;
  final Widget child;
  @override
  State<PresentationImageElement> createState() =>
      _PresentationImageElementState();
}

class _PresentationImageElementState extends State<PresentationImageElement> {
  Offset? _start;
  NoteImageLayout? _origin;
  @override
  Widget build(BuildContext context) {
    final scope = PresentationElementScope.maybeOf(context);
    final key = presentationElementKey(widget.itemId, 'image');
    scope?.registerImage?.call(key, widget.layout);
    final selected = scope?.editing == true && scope?.selected == key;
    void select(Offset position) => scope?.select(key, 'Image', 0, position);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: scope == null
          ? null
          : (details) => select(details.globalPosition),
      onTapUp: scope?.editing == true
          ? (details) => select(details.globalPosition)
          : null,
      onPanStart: selected
          ? (details) {
              _start = details.globalPosition;
              _origin = widget.layout;
            }
          : null,
      onPanUpdate: selected
          ? (details) {
              final origin = _origin;
              if (origin == null || _start == null || widget.scale <= 0) return;
              final delta = (details.globalPosition - _start!) / widget.scale;
              final row =
                  (origin.row +
                          (delta.dy / (widget.stageSize.height / origin.rows))
                              .round())
                      .clamp(0, origin.rows - origin.rowSpan);
              final column =
                  (origin.column +
                          (delta.dx / (widget.stageSize.width / origin.columns))
                              .round())
                      .clamp(0, origin.columns - origin.columnSpan);
              final layout = NoteImageLayout.fromJson({
                ...origin.toJson(),
                'row': row,
                'column': column,
              });
              if (layout != null) scope?.changeImage?.call(key, layout);
            }
          : null,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected
              ? Border.all(
                  color: const Color(0xFFE0BE87),
                  width: 3 / widget.scale,
                )
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
