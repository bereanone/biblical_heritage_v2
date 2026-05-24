import 'package:flutter/material.dart';

enum TextRangeSourceKind {
  bible,
  elibrary,
}

@immutable
class TextRangeLayoutSeed {
  const TextRangeLayoutSeed({
    required this.anchor,
    required this.startOffset,
    required this.endOffset,
    this.lineIndex,
  });

  final TextRangeAnchor anchor;
  final int startOffset;
  final int endOffset;
  final int? lineIndex;
}

@immutable
class TextRangeAnchor {
  const TextRangeAnchor({
    required this.sourceKind,
    required this.scopeId,
    required this.blockId,
    required this.tokenIndex,
    this.characterOffset,
    this.contentKey,
  });

  factory TextRangeAnchor.bible({
    required String scopeId,
    required int verseBlockId,
    required int tokenIndex,
    int? characterOffset,
    String? contentKey,
  }) {
    return TextRangeAnchor(
      sourceKind: TextRangeSourceKind.bible,
      scopeId: scopeId,
      blockId: verseBlockId,
      tokenIndex: tokenIndex,
      characterOffset: characterOffset,
      contentKey: contentKey,
    );
  }

  factory TextRangeAnchor.elibrary({
    required String scopeId,
    required int paragraphBlockIndex,
    required int tokenIndex,
    int? characterOffset,
    String? contentKey,
  }) {
    return TextRangeAnchor(
      sourceKind: TextRangeSourceKind.elibrary,
      scopeId: scopeId,
      blockId: paragraphBlockIndex,
      tokenIndex: tokenIndex,
      characterOffset: characterOffset,
      contentKey: contentKey,
    );
  }

  final TextRangeSourceKind sourceKind;
  final String scopeId;
  final int blockId;
  final int tokenIndex;
  final int? characterOffset;
  final String? contentKey;

  @override
  bool operator ==(Object other) {
    return other is TextRangeAnchor &&
        other.sourceKind == sourceKind &&
        other.scopeId == scopeId &&
        other.blockId == blockId &&
        other.tokenIndex == tokenIndex &&
        other.characterOffset == characterOffset &&
        other.contentKey == contentKey;
  }

  @override
  int get hashCode {
    return Object.hash(
      sourceKind,
      scopeId,
      blockId,
      tokenIndex,
      characterOffset,
      contentKey,
    );
  }

  @override
  String toString() {
    return 'TextRangeAnchor('
        'sourceKind: $sourceKind, '
        'scopeId: $scopeId, '
        'blockId: $blockId, '
        'tokenIndex: $tokenIndex, '
        'characterOffset: $characterOffset, '
        'contentKey: $contentKey'
        ')';
  }
}

@immutable
class TextRangeGeometry {
  const TextRangeGeometry({
    required this.anchor,
    required this.localRect,
    required this.globalRect,
    required this.textDirection,
    this.lineIndex,
    this.baseline,
  });

  final TextRangeAnchor anchor;
  final Rect localRect;
  final Rect globalRect;
  final TextDirection textDirection;
  final int? lineIndex;
  final double? baseline;

  Offset get localCenter => localRect.center;

  Offset get globalCenter => globalRect.center;

  TextRangeGeometry translateGlobal(Offset delta) {
    return TextRangeGeometry(
      anchor: anchor,
      localRect: localRect,
      globalRect: globalRect.shift(delta),
      textDirection: textDirection,
      lineIndex: lineIndex,
      baseline: baseline,
    );
  }
}

class TextRangeGeometryRegistry extends ChangeNotifier {
  final Map<TextRangeAnchor, TextRangeGeometry> _entries =
      <TextRangeAnchor, TextRangeGeometry>{};

  int get entryCount => _entries.length;

  Iterable<TextRangeGeometry> get entries => _entries.values;

  void register(TextRangeGeometry geometry) {
    final previous = _entries[geometry.anchor];
    if (previous == geometry) return;
    _entries[geometry.anchor] = geometry;
    notifyListeners();
  }

  void registerAll(Iterable<TextRangeGeometry> geometries) {
    var changed = false;
    for (final geometry in geometries) {
      final previous = _entries[geometry.anchor];
      if (previous == geometry) continue;
      _entries[geometry.anchor] = geometry;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void remove(TextRangeAnchor anchor) {
    if (_entries.remove(anchor) != null) {
      notifyListeners();
    }
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void clearScope(
    String scopeId, {
    TextRangeSourceKind? sourceKind,
  }) {
    final anchorsToRemove = _entries.keys
        .where((anchor) {
          final matchesScope = anchor.scopeId == scopeId;
          final matchesKind =
              sourceKind == null || anchor.sourceKind == sourceKind;
          return matchesScope && matchesKind;
        })
        .toList(growable: false);
    if (anchorsToRemove.isEmpty) return;
    for (final anchor in anchorsToRemove) {
      _entries.remove(anchor);
    }
    notifyListeners();
  }

  TextRangeGeometry? geometryForAnchor(TextRangeAnchor anchor) {
    return _entries[anchor];
  }

  Rect? localRectForAnchor(TextRangeAnchor anchor) {
    return _entries[anchor]?.localRect;
  }

  Rect? globalRectForAnchor(TextRangeAnchor anchor) {
    return _entries[anchor]?.globalRect;
  }

  TextRangeAnchor? nearestAnchorToGlobalPoint(
    Offset globalPoint, {
    TextRangeSourceKind? sourceKind,
    String? scopeId,
    double maxDistance = double.infinity,
  }) {
    TextRangeAnchor? bestAnchor;
    double bestDistanceSquared = maxDistance * maxDistance;

    for (final entry in _entries.values) {
      final anchor = entry.anchor;
      if (sourceKind != null && anchor.sourceKind != sourceKind) continue;
      if (scopeId != null && anchor.scopeId != scopeId) continue;
      final candidateDistance = _distanceSquaredToRect(
        globalPoint,
        entry.globalRect,
      );
      if (candidateDistance < bestDistanceSquared) {
        bestDistanceSquared = candidateDistance;
        bestAnchor = anchor;
      }
    }

    return bestAnchor;
  }

  Rect? localRectForSelection({
    required TextRangeAnchor start,
    required TextRangeAnchor end,
  }) {
    final geometries = _geometriesForSelection(start: start, end: end);
    return _unionRects(geometries.map((geometry) => geometry.localRect));
  }

  Rect? globalRectForSelection({
    required TextRangeAnchor start,
    required TextRangeAnchor end,
  }) {
    final geometries = _geometriesForSelection(start: start, end: end);
    return _unionRects(geometries.map((geometry) => geometry.globalRect));
  }

  List<TextRangeGeometry> _geometriesForSelection({
    required TextRangeAnchor start,
    required TextRangeAnchor end,
  }) {
    final comparison = _compareAnchors(start, end);
    final low = comparison <= 0 ? start : end;
    final high = comparison <= 0 ? end : start;
    return _entries.values.where((geometry) {
      final anchor = geometry.anchor;
      if (anchor.sourceKind != low.sourceKind || anchor.scopeId != low.scopeId) {
        return false;
      }
      return _compareAnchors(anchor, low) >= 0 &&
          _compareAnchors(anchor, high) <= 0;
    }).toList(growable: false);
  }
}

double _distanceSquaredToRect(Offset point, Rect rect) {
  final clampedX = point.dx < rect.left
      ? rect.left
      : point.dx > rect.right
      ? rect.right
      : point.dx;
  final clampedY = point.dy < rect.top
      ? rect.top
      : point.dy > rect.bottom
      ? rect.bottom
      : point.dy;
  final dx = point.dx - clampedX;
  final dy = point.dy - clampedY;
  return dx * dx + dy * dy;
}

int _compareAnchors(TextRangeAnchor left, TextRangeAnchor right) {
  final sourceCompare = left.sourceKind.index.compareTo(right.sourceKind.index);
  if (sourceCompare != 0) return sourceCompare;
  final scopeCompare = left.scopeId.compareTo(right.scopeId);
  if (scopeCompare != 0) return scopeCompare;
  final blockCompare = left.blockId.compareTo(right.blockId);
  if (blockCompare != 0) return blockCompare;
  final tokenCompare = left.tokenIndex.compareTo(right.tokenIndex);
  if (tokenCompare != 0) return tokenCompare;
  final leftOffset = left.characterOffset ?? -1;
  final rightOffset = right.characterOffset ?? -1;
  final offsetCompare = leftOffset.compareTo(rightOffset);
  if (offsetCompare != 0) return offsetCompare;
  final leftKey = left.contentKey ?? '';
  final rightKey = right.contentKey ?? '';
  return leftKey.compareTo(rightKey);
}

Rect? _unionRects(Iterable<Rect> rects) {
  Rect? union;
  for (final rect in rects) {
    if (rect.isEmpty) continue;
    union = union == null ? rect : union.expandToInclude(rect);
  }
  return union;
}

class TextRangeGeometryReporter extends StatefulWidget {
  const TextRangeGeometryReporter({
    super.key,
    required this.registry,
    required this.scopeId,
    required this.sourceKind,
    required this.text,
    required this.seeds,
    required this.child,
    required this.textDirection,
    required this.textAlign,
    this.geometryRevision = 0,
    this.textScaler = TextScaler.noScaling,
    this.locale,
    this.maxLines,
    this.strutStyle,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
  });

  final TextRangeGeometryRegistry registry;
  final String scopeId;
  final TextRangeSourceKind sourceKind;
  final InlineSpan text;
  final List<TextRangeLayoutSeed> seeds;
  final Widget child;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final int geometryRevision;
  final TextScaler textScaler;
  final Locale? locale;
  final int? maxLines;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;

  @override
  State<TextRangeGeometryReporter> createState() =>
      _TextRangeGeometryReporterState();
}

class _TextRangeGeometryReporterState extends State<TextRangeGeometryReporter> {
  final GlobalKey _childKey = GlobalKey();
  bool _measureScheduled = false;
  final Set<TextRangeAnchor> _registeredAnchors = <TextRangeAnchor>{};

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant TextRangeGeometryReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.scopeId != widget.scopeId ||
        oldWidget.sourceKind != widget.sourceKind ||
        oldWidget.seeds != widget.seeds ||
        oldWidget.textDirection != widget.textDirection ||
        oldWidget.textAlign != widget.textAlign ||
        oldWidget.geometryRevision != widget.geometryRevision ||
        oldWidget.textScaler != widget.textScaler ||
        oldWidget.locale != widget.locale ||
        oldWidget.maxLines != widget.maxLines ||
        oldWidget.strutStyle != widget.strutStyle ||
        oldWidget.textWidthBasis != widget.textWidthBasis ||
        oldWidget.textHeightBehavior != widget.textHeightBehavior) {
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    for (final anchor in _registeredAnchors) {
      widget.registry.remove(anchor);
    }
    _registeredAnchors.clear();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final context = _childKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final maxWidth = renderObject.size.width;
    if (!maxWidth.isFinite || maxWidth <= 0) return;

    final painter = TextPainter(
      text: widget.text,
      textDirection: widget.textDirection,
      textAlign: widget.textAlign,
      textScaler: widget.textScaler,
      locale: widget.locale,
      maxLines: widget.maxLines,
      strutStyle: widget.strutStyle,
      textWidthBasis: widget.textWidthBasis,
      textHeightBehavior: widget.textHeightBehavior,
    )..layout(maxWidth: maxWidth);

    final origin = renderObject.localToGlobal(Offset.zero);
    final geometries = <TextRangeGeometry>[];
    for (final seed in widget.seeds) {
      final start = seed.startOffset;
      final end = seed.endOffset;
      if (start < 0 || end <= start) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      if (boxes.isEmpty) continue;
      final rect = _unionRects(boxes.map((box) {
        return Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
      }));
      if (rect == null || rect.isEmpty) continue;
      geometries.add(
        TextRangeGeometry(
          anchor: seed.anchor,
          localRect: rect,
          globalRect: rect.shift(origin),
          textDirection: widget.textDirection,
          lineIndex: seed.lineIndex,
        ),
      );
    }

    final nextAnchors = geometries.map((geometry) => geometry.anchor).toSet();
    final anchorsToRemove = _registeredAnchors.difference(nextAnchors);
    for (final anchor in anchorsToRemove) {
      widget.registry.remove(anchor);
    }
    widget.registry.registerAll(geometries);
    _registeredAnchors
      ..clear()
      ..addAll(nextAnchors);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return KeyedSubtree(
      key: _childKey,
      child: widget.child,
    );
  }
}
