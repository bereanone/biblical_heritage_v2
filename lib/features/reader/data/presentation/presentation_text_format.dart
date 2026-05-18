import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

enum PresentationTextDecorationKind { bold, underline, italic }

class PresentationTextSpanStyle {
  const PresentationTextSpanStyle({
    this.bold = false,
    this.underline = false,
    this.italic = false,
  });

  final bool bold;
  final bool underline;
  final bool italic;

  bool get isEmpty => !bold && !underline && !italic;

  PresentationTextSpanStyle copyWith({
    bool? bold,
    bool? underline,
    bool? italic,
  }) {
    return PresentationTextSpanStyle(
      bold: bold ?? this.bold,
      underline: underline ?? this.underline,
      italic: italic ?? this.italic,
    );
  }

  Map<String, Object?> toJson() {
    return {'bold': bold, 'underline': underline, 'italic': italic};
  }

  factory PresentationTextSpanStyle.fromJson(Map<String, Object?> json) {
    return PresentationTextSpanStyle(
      bold: json['bold'] == true,
      underline: json['underline'] == true,
      italic: json['italic'] == true,
    );
  }

  TextStyle applyTo(TextStyle baseStyle) {
    return baseStyle.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: underline ? TextDecoration.underline : null,
      decorationColor: underline ? baseStyle.color : null,
    );
  }
}

class PresentationTextSpanRange {
  const PresentationTextSpanRange({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final PresentationTextSpanStyle style;

  PresentationTextSpanRange copyWith({
    int? start,
    int? end,
    PresentationTextSpanStyle? style,
  }) {
    return PresentationTextSpanRange(
      start: start ?? this.start,
      end: end ?? this.end,
      style: style ?? this.style,
    );
  }

  Map<String, Object?> toJson() {
    return {'start': start, 'end': end, ...style.toJson()};
  }

  factory PresentationTextSpanRange.fromJson(Map<String, Object?> json) {
    return PresentationTextSpanRange(
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      style: PresentationTextSpanStyle.fromJson(json),
    );
  }
}

class PresentationTextFormat {
  const PresentationTextFormat({
    required this.baseTextHash,
    required this.spans,
  });

  final String? baseTextHash;
  final List<PresentationTextSpanRange> spans;

  bool matchesText(String text) => baseTextHash == _hashText(text);

  PresentationTextFormat copyWith({
    String? baseTextHash,
    List<PresentationTextSpanRange>? spans,
  }) {
    return PresentationTextFormat(
      baseTextHash: baseTextHash ?? this.baseTextHash,
      spans: spans ?? this.spans,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'format_version': 1,
      'base_text_hash': baseTextHash,
      'spans': spans.map((span) => span.toJson()).toList(growable: false),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory PresentationTextFormat.fromJsonString(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const PresentationTextFormat(baseTextHash: null, spans: []);
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final spansValue = decoded['spans'];
        final spans = <PresentationTextSpanRange>[];
        if (spansValue is List) {
          for (final entry in spansValue) {
            if (entry is Map<String, dynamic>) {
              spans.add(
                PresentationTextSpanRange.fromJson(
                  entry.cast<String, Object?>(),
                ),
              );
            }
          }
        }
        return PresentationTextFormat(
          baseTextHash: decoded['base_text_hash']?.toString(),
          spans: spans,
        );
      }
    } catch (_) {
      // Fall through to an empty format object.
    }

    return const PresentationTextFormat(baseTextHash: null, spans: []);
  }
}

String? presentationTextFormatJsonForText({
  required String text,
  required PresentationTextFormat? format,
}) {
  if (format == null || format.spans.isEmpty) return null;
  final normalized = format.copyWith(baseTextHash: _hashText(text));
  return normalized.toJsonString();
}

PresentationTextFormat? presentationTextFormatForText({
  required String text,
  required String? json,
}) {
  final format = PresentationTextFormat.fromJsonString(json);
  if (format.spans.isEmpty) return null;
  if (!format.matchesText(text)) return null;
  return format;
}

PresentationTextFormat? togglePresentationTextDecoration({
  required String text,
  required PresentationTextFormat? current,
  required TextSelection selection,
  required PresentationTextDecorationKind kind,
}) {
  final normalized =
      current ?? const PresentationTextFormat(baseTextHash: null, spans: []);
  final bounds = _normalizedBounds(selection, text.length);
  if (bounds == null) return normalized;

  final segments = _segmentsForText(text.length, normalized.spans);
  final selectedSegments = segments
      .where(
        (segment) =>
            _rangesOverlap(segment.start, segment.end, bounds.$1, bounds.$2),
      )
      .toList(growable: false);
  if (selectedSegments.isEmpty) return normalized;

  final shouldEnable = !selectedSegments.every((segment) {
    return _styleFlag(segment.style, kind);
  });

  final updated = <PresentationTextSpanRange>[];
  for (final segment in segments) {
    if (!_rangesOverlap(segment.start, segment.end, bounds.$1, bounds.$2)) {
      updated.add(segment);
      continue;
    }

    final left = segment.start < bounds.$1
        ? segment.copyWith(end: bounds.$1)
        : null;
    final right = segment.end > bounds.$2
        ? segment.copyWith(start: bounds.$2)
        : null;
    var middleStyle = segment.style;
    switch (kind) {
      case PresentationTextDecorationKind.bold:
        middleStyle = middleStyle.copyWith(bold: shouldEnable);
      case PresentationTextDecorationKind.underline:
        middleStyle = middleStyle.copyWith(underline: shouldEnable);
      case PresentationTextDecorationKind.italic:
        middleStyle = middleStyle.copyWith(italic: shouldEnable);
    }
    final middle = PresentationTextSpanRange(
      start: bounds.$1.clamp(segment.start, segment.end).toInt(),
      end: bounds.$2.clamp(segment.start, segment.end).toInt(),
      style: middleStyle,
    );
    if (left != null && left.end > left.start) updated.add(left);
    if (middle.end > middle.start) updated.add(middle);
    if (right != null && right.end > right.start) updated.add(right);
  }

  return PresentationTextFormat(
    baseTextHash: _hashText(text),
    spans: _mergeSegments(_normalizeSegments(updated, text.length)),
  );
}

List<InlineSpan> buildPresentationTextSpans({
  required String text,
  required TextStyle baseStyle,
  String? formatJson,
}) {
  final format = presentationTextFormatForText(text: text, json: formatJson);
  if (format == null || format.spans.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }

  return buildPresentationTextSpansFromFormat(
    text: text,
    baseStyle: baseStyle,
    format: format,
  );
}

List<InlineSpan> buildPresentationTextSpansFromFormat({
  required String text,
  required TextStyle baseStyle,
  required PresentationTextFormat? format,
}) {
  if (format == null || format.spans.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final segment in _normalizeSegments(format.spans, text.length)) {
    if (segment.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, segment.start), style: baseStyle),
      );
    }
    final segmentText = text.substring(segment.start, segment.end);
    spans.add(
      TextSpan(text: segmentText, style: segment.style.applyTo(baseStyle)),
    );
    cursor = segment.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  if (spans.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }
  return spans;
}

String? presentationTextFormatHashForText(String text) => _hashText(text);

List<PresentationTextSpanRange> _segmentsForText(
  int textLength,
  List<PresentationTextSpanRange> spans,
) {
  final normalized = _normalizeSegments(spans, textLength);
  final segments = <PresentationTextSpanRange>[];
  var cursor = 0;
  for (final span in normalized) {
    if (span.start > cursor) {
      segments.add(
        PresentationTextSpanRange(
          start: cursor,
          end: span.start,
          style: const PresentationTextSpanStyle(),
        ),
      );
    }
    segments.add(span);
    cursor = span.end;
  }
  if (cursor < textLength) {
    segments.add(
      PresentationTextSpanRange(
        start: cursor,
        end: textLength,
        style: const PresentationTextSpanStyle(),
      ),
    );
  }
  if (segments.isEmpty && textLength > 0) {
    segments.add(
      PresentationTextSpanRange(
        start: 0,
        end: textLength,
        style: const PresentationTextSpanStyle(),
      ),
    );
  }
  return segments;
}

List<PresentationTextSpanRange> _normalizeSegments(
  List<PresentationTextSpanRange> spans,
  int textLength,
) {
  final clamped = <PresentationTextSpanRange>[];
  for (final span in spans) {
    final start = span.start.clamp(0, textLength).toInt();
    final end = span.end.clamp(0, textLength).toInt();
    if (end <= start) continue;
    clamped.add(span.copyWith(start: start, end: end));
  }
  clamped.sort((a, b) => a.start.compareTo(b.start));

  final segments = <PresentationTextSpanRange>[];
  for (final span in clamped) {
    if (segments.isEmpty) {
      segments.add(span);
      continue;
    }
    final last = segments.last;
    if (span.start < last.end) {
      final start = last.end;
      if (span.end > start) {
        segments.add(span.copyWith(start: start));
      }
      continue;
    }
    if (span.start == last.end && _sameStyle(span.style, last.style)) {
      segments[segments.length - 1] = last.copyWith(end: span.end);
      continue;
    }
    segments.add(span);
  }
  return segments;
}

List<PresentationTextSpanRange> _mergeSegments(
  List<PresentationTextSpanRange> spans,
) {
  if (spans.isEmpty) return spans;
  final merged = <PresentationTextSpanRange>[spans.first];
  for (var i = 1; i < spans.length; i++) {
    final current = spans[i];
    final last = merged.last;
    if (current.start == last.end && _sameStyle(current.style, last.style)) {
      merged[merged.length - 1] = last.copyWith(end: current.end);
      continue;
    }
    merged.add(current);
  }
  return merged;
}

bool _sameStyle(PresentationTextSpanStyle a, PresentationTextSpanStyle b) {
  return a.bold == b.bold && a.underline == b.underline && a.italic == b.italic;
}

bool _styleFlag(
  PresentationTextSpanStyle style,
  PresentationTextDecorationKind kind,
) {
  return switch (kind) {
    PresentationTextDecorationKind.bold => style.bold,
    PresentationTextDecorationKind.underline => style.underline,
    PresentationTextDecorationKind.italic => style.italic,
  };
}

bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) {
  return aStart < bEnd && bStart < aEnd;
}

Tuple2<int, int>? _normalizedBounds(TextSelection selection, int textLength) {
  final start = selection.start;
  final end = selection.end;
  if (start < 0 || end < 0 || start == end) return null;
  final normalizedStart = start.clamp(0, textLength).toInt();
  final normalizedEnd = end.clamp(0, textLength).toInt();
  if (normalizedEnd <= normalizedStart) return null;
  return Tuple2(normalizedStart, normalizedEnd);
}

String _hashText(String text) {
  return sha1.convert(utf8.encode(text)).toString();
}

class Tuple2<T1, T2> {
  const Tuple2(this.item1, this.item2);

  final T1 item1;
  final T2 item2;

  T1 get $1 => item1;
  T2 get $2 => item2;
}
