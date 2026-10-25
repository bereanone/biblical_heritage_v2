import 'package:flutter/material.dart';
import 'text_range_geometry.dart';
import 'viewer_range_selection.dart';

/// Uses the reader's stable source anchors; dragging never invokes the range
/// action menu. Geometry is only measured while a selection is active.
class ViewerSelectionHandles extends StatefulWidget {
  const ViewerSelectionHandles({
    super.key,
    required this.registry,
    required this.selection,
    required this.child,
    this.onMove,
    this.onDismiss,
  });
  final TextRangeGeometryRegistry registry;
  final ViewerRangeSelection selection;
  final Widget child;
  final VoidCallback? onDismiss;
  final void Function(bool start, int blockId, int tokenIndex)? onMove;
  @override
  State<ViewerSelectionHandles> createState() => _ViewerSelectionHandlesState();
}

class _ViewerSelectionHandlesState extends State<ViewerSelectionHandles> {
  bool _scheduled = false;
  Offset _dragPointOffset = Offset.zero;
  Offset? _pointerDown;
  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_refresh);
  }

  void _refresh() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(ViewerSelectionHandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry) {
      oldWidget.registry.removeListener(_refresh);
      widget.registry.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.registry.removeListener(_refresh);
    super.dispose();
  }

  TextRangeGeometry? _endpoint(bool start) {
    final block = start
        ? widget.selection.lowerBlockId
        : widget.selection.upperBlockId;
    final token = start
        ? widget.selection.lowerTokenIndex
        : widget.selection.upperTokenIndex;
    for (final geometry in widget.registry.entries) {
      if (geometry.anchor.blockId == block &&
          geometry.anchor.tokenIndex == token) {
        return geometry;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final box = this.context.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero)
          : Offset.zero;
      final show =
          widget.selection.hasCompletedRange &&
          widget.selection.hasTokenSelection &&
          widget.onMove != null;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _pointerDown = event.position,
        onPointerUp: (event) {
          final down = _pointerDown;
          _pointerDown = null;
          if (!show || down == null || (event.position - down).distance > 5) {
            return;
          }
          final point = event.position;
          final touchesHandle = [true, false].any((start) {
            final geometry = _endpoint(start);
            if (geometry == null) return false;
            final rect =
                (start ? geometry.globalStartRect : geometry.globalEndRect) ??
                geometry.globalRect;
            final rtl = geometry.textDirection == TextDirection.rtl;
            final x = start != rtl ? rect.left : rect.right;
            final y = start ? rect.top : rect.bottom;
            return Rect.fromLTWH(
              x - 22,
              y - (start ? 36 : 8),
              44,
              44,
            ).contains(point);
          });
          final rowRects = widget.registry.entries
              .where(
                (entry) =>
                    widget.selection.containsTokenPosition(
                      entry.anchor.blockId,
                      entry.anchor.tokenIndex,
                    ) &&
                    point.dy >= entry.globalRect.top - 2 &&
                    point.dy <= entry.globalRect.bottom + 2,
              )
              .map((entry) => entry.globalRect)
              .toList();
          Rect? selectedRow;
          for (final rect in rowRects) {
            selectedRow = selectedRow == null
                ? rect
                : selectedRow.expandToInclude(rect);
          }
          final touchesSelection =
              selectedRow?.inflate(2).contains(point) == true;
          if (!touchesHandle && !touchesSelection) widget.onDismiss?.call();
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            widget.child,
            if (show)
              for (final start in [true, false])
                if (_endpoint(start) case final TextRangeGeometry geometry)
                  _handle(context, constraints, origin, geometry, start),
          ],
        ),
      );
    },
  );
  Widget _handle(
    BuildContext context,
    BoxConstraints constraints,
    Offset origin,
    TextRangeGeometry geometry,
    bool start,
  ) {
    final rect =
        (start ? geometry.globalStartRect : geometry.globalEndRect) ??
        geometry.globalRect;
    final rtl = geometry.textDirection == TextDirection.rtl;
    final x = (start != rtl ? rect.left : rect.right) - origin.dx;
    final y = (start ? rect.top : rect.bottom) - origin.dy;
    // Hide stale/offscreen endpoints instead of attaching a handle to the edge
    // of the viewport after its verse has scrolled away.
    if (y < 0 ||
        y > constraints.maxHeight ||
        x < 0 ||
        x > constraints.maxWidth) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: (x - 22).clamp(
        0.0,
        (constraints.maxWidth - 44).clamp(0.0, double.infinity),
      ),
      top: y - (start ? 36 : 8),
      width: 44,
      height: 44,
      child: Semantics(
        label: start ? 'Start of selection' : 'End of selection',
        child: GestureDetector(
          key: ValueKey(
            start
                ? 'viewer-selection-start-handle'
                : 'viewer-selection-end-handle',
          ),
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _dragPointOffset =
                Offset(
                  start != rtl ? rect.left + 1 : rect.right - 1,
                  rect.center.dy,
                ) -
                details.globalPosition;
          },
          onPanUpdate: (details) {
            final point = details.globalPosition + _dragPointOffset;
            final target = widget.registry.nearestAnchorToGlobalPoint(
              point,
              sourceKind: TextRangeSourceKind.bible,
            );
            if (target != null) {
              widget.onMove?.call(start, target.blockId, target.tokenIndex);
            }
          },
          child: CustomPaint(
            painter: _HandlePainter(
              Theme.of(context).colorScheme.primary,
              start,
            ),
          ),
        ),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter(this.color, this.start);
  final Color color;
  final bool start;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 8), Offset(x, 36), paint);
    canvas.drawCircle(Offset(x, start ? 8 : 36), 6, paint);
  }

  @override
  bool shouldRepaint(_HandlePainter old) =>
      color != old.color || start != old.start;
}
