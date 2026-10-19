import 'dart:convert';
import 'dart:ui';

/// A single rectangular image reservation within a presentation grid.
class NoteImageLayout {
  const NoteImageLayout({
    this.rows = 3,
    this.columns = 3,
    this.row = 0,
    this.column = 2,
    this.rowSpan = 3,
    this.columnSpan = 1,
    this.imageIndex = 0,
    this.aspectRatio = 16 / 9,
    this.header = '',
    this.footer = '',
    this.fill = true,
  });
  final int rows, columns, row, column, rowSpan, columnSpan, imageIndex;
  final double aspectRatio;
  final String header, footer;
  final bool fill;

  bool get isValid =>
      rows >= 1 &&
      rows <= 4 &&
      columns >= 1 &&
      columns <= 4 &&
      row >= 0 &&
      column >= 0 &&
      rowSpan > 0 &&
      columnSpan > 0 &&
      row + rowSpan <= rows &&
      column + columnSpan <= columns &&
      imageIndex >= 0 &&
      aspectRatio.isFinite &&
      aspectRatio > 0;

  Set<int> get cells => {
    for (var r = row; r < row + rowSpan; r++)
      for (var c = column; c < column + columnSpan; c++) r * columns + c,
  };

  Rect imageRect(Size size) => Rect.fromLTWH(
    size.width * column / columns,
    size.height * row / rows,
    size.width * columnSpan / columns,
    size.height * rowSpan / rows,
  );

  static NoteImageLayout? fromCells({
    required int rows,
    required int columns,
    required Set<int> cells,
    int imageIndex = 0,
    double aspectRatio = 16 / 9,
    String header = '',
    String footer = '',
    bool fill = true,
  }) {
    if (rows < 1 ||
        rows > 4 ||
        columns < 1 ||
        columns > 4 ||
        cells.isEmpty ||
        cells.any((cell) => cell < 0 || cell >= rows * columns))
      return null;
    final rs = cells.map((c) => c ~/ columns).toList()..sort();
    final cs = cells.map((c) => c % columns).toList()..sort();
    final candidate = NoteImageLayout(
      rows: rows,
      columns: columns,
      row: rs.first,
      column: cs.first,
      rowSpan: rs.last - rs.first + 1,
      columnSpan: cs.last - cs.first + 1,
      imageIndex: imageIndex,
      aspectRatio: aspectRatio,
      header: header,
      footer: footer,
      fill: fill,
    );
    if (!candidate.isValid ||
        candidate.cells.length != cells.length ||
        !candidate.cells.containsAll(cells))
      return null;
    return candidate;
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'rows': rows,
    'columns': columns,
    'row': row,
    'column': column,
    'row_span': rowSpan,
    'column_span': columnSpan,
    'image_index': imageIndex,
    'aspect_ratio': aspectRatio,
    'header': header,
    'footer': footer,
    'fill': fill,
  };

  static NoteImageLayout? fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != 1) return null;
    int? integer(String key) {
      final value = raw[key];
      return value is num && value.isFinite && value == value.roundToDouble()
          ? value.toInt()
          : null;
    }

    final values = [
      'rows',
      'columns',
      'row',
      'column',
      'row_span',
      'column_span',
      'image_index',
    ].map(integer).toList();
    if (values.any((value) => value == null)) return null;
    final ratio = raw['aspect_ratio'];
    if (ratio is! num) return null;
    final result = NoteImageLayout(
      rows: values[0]!,
      columns: values[1]!,
      row: values[2]!,
      column: values[3]!,
      rowSpan: values[4]!,
      columnSpan: values[5]!,
      imageIndex: values[6]!,
      aspectRatio: ratio.toDouble(),
      header: raw['header'] is String ? raw['header'] as String : '',
      footer: raw['footer'] is String ? raw['footer'] as String : '',
      fill: raw['fill'] != false,
    );
    return result.isValid ? result : null;
  }
}

NoteImageLayout? noteImageLayoutFromFormat(String? raw) {
  try {
    final data = jsonDecode(raw ?? '');
    return data is Map ? NoteImageLayout.fromJson(data['image_layout']) : null;
  } catch (_) {
    return null;
  }
}

/// Update layout only; preserve formatting hashes, ranges and other metadata.
String? noteFormatWithImageLayout(String? raw, NoteImageLayout? layout) {
  Map<String, dynamic> data = {};
  if (raw != null && raw.trim().isNotEmpty) {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>)
      throw const FormatException('Invalid note metadata');
    data = Map<String, dynamic>.from(parsed);
  }
  if (layout == null) {
    data.remove('image_layout');
  } else {
    if (!layout.isValid) throw const FormatException('Invalid image layout');
    data['image_layout'] = layout.toJson();
  }
  return data.isEmpty ? null : jsonEncode(data);
}

String? mergeNoteFormattingAndImageLayout({
  required String? original,
  required String? formatted,
  required NoteImageLayout? layout,
}) {
  Map<String, dynamic> data = {};
  if (original?.trim().isNotEmpty == true) {
    final parsed = jsonDecode(original!);
    if (parsed is! Map<String, dynamic>)
      throw const FormatException('Invalid note metadata');
    data = Map<String, dynamic>.from(parsed);
  }
  for (final key in ['format_version', 'base_text_hash', 'spans']) {
    data.remove(key);
  }
  if (formatted?.trim().isNotEmpty == true) {
    final parsed = jsonDecode(formatted!);
    if (parsed is! Map<String, dynamic>)
      throw const FormatException('Invalid note formatting');
    data.addAll(parsed);
  }
  return noteFormatWithImageLayout(
    data.isEmpty ? null : jsonEncode(data),
    layout,
  );
}

class PresentationBlockAlignments {
  const PresentationBlockAlignments({
    this.title = TextAlign.center,
    this.body = TextAlign.left,
    this.footer = TextAlign.center,
    this.citation = TextAlign.right,
  });
  final TextAlign title, body, footer, citation;
  static TextAlign decode(Object? value, TextAlign fallback) => switch (value) {
    'left' => TextAlign.left,
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    'justify' => TextAlign.justify,
    _ => fallback,
  };
  factory PresentationBlockAlignments.fromFormat(String? raw) {
    try {
      final parsed = jsonDecode(raw ?? '{}');
      final data = parsed['block_alignment'];
      if (data is! Map) return const PresentationBlockAlignments();
      return PresentationBlockAlignments(
        title: decode(data['title'], TextAlign.center),
        body: decode(data['body'], TextAlign.left),
        footer: decode(data['footer'], TextAlign.center),
        citation: decode(data['citation'], TextAlign.right),
      );
    } catch (_) {
      return const PresentationBlockAlignments();
    }
  }
  Map<String, String> toJson() => {
    'title': title.name,
    'body': body.name,
    'footer': footer.name,
    'citation': citation.name,
  };
  String withFormat(String? raw) {
    final data = Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map);
    data['block_alignment'] = toJson();
    return jsonEncode(data);
  }
}

bool presentationLinksWithNext(String? raw) {
  try {return (jsonDecode(raw??'{}') as Map)['link_with_next']==true;} catch(_){return false;}
}
String presentationFormatWithLink(String? raw,bool linked) {
  final data=Map<String,dynamic>.from(jsonDecode(raw??'{}') as Map);
  data['link_with_next']=linked;return jsonEncode(data);
}
