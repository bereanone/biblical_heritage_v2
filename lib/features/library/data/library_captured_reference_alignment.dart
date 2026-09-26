import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Source types whose text was captured from a web page rather than authored
/// as an EPUB. None of them carries embedded reference codes, so the citation
/// ("CS 2.1") is synthesized from the work abbreviation plus the section /
/// page and paragraph position at import time.
const Set<String> capturedReferenceSourceTypes = <String>{
  'pioneer_captured_html',
  'captured_html',
};

/// `reference_origin` recorded on canonical blocks whose code came from this
/// alignment, so it stays distinguishable from authored and verified codes.
const String capturedReferenceOrigin = 'synthetic_capture_section_paragraph';

/// Hands the reference codes the capture import already synthesized into
/// `elibrary_ref_index` to the canonical paragraph blocks parsed from the same
/// capture.
///
/// The two structures are keyed differently (the index uses synthetic
/// per-section hrefs; canonical blocks use the capture's own href and a
/// document-wide order), so they cannot be joined on href + paragraph index.
/// They are, however, two parses of the same paragraphs in the same order, so
/// each index row is matched to the next canonical paragraph with identical
/// text. A paragraph with no match is left without a code rather than given a
/// neighbour's.
class CapturedReferenceAlignment {
  CapturedReferenceAlignment._(this._rows);

  /// How far ahead of the cursor a matching row is searched for, to ride out
  /// a paragraph one parse dropped or merged without matching a repeated line
  /// ("Amen.") much later in the book.
  static const int _lookahead = 4;

  final List<({String text, String refCode})> _rows;
  int _cursor = 0;

  bool get isEmpty => _rows.isEmpty;

  /// Loads the alignment for [libraryItemId], or null when the item is not a
  /// capture or has no synthesized codes.
  static Future<CapturedReferenceAlignment?> load(
    Database db,
    String libraryItemId,
  ) async {
    final items = await db.query(
      'library_items',
      columns: const <String>['source_type'],
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    final sourceType = items.firstOrNull?['source_type']
        ?.toString()
        .trim()
        .toLowerCase();
    if (sourceType == null ||
        !capturedReferenceSourceTypes.contains(sourceType)) {
      return null;
    }
    final rows = await db.query(
      'elibrary_ref_index',
      columns: const <String>['plain_text', 'ref_code'],
      where: "library_item_id = ? AND TRIM(COALESCE(ref_code, '')) != ''",
      whereArgs: <Object?>[libraryItemId],
      orderBy: 'id ASC',
    );
    final alignment =
        CapturedReferenceAlignment._(<({String text, String refCode})>[
          for (final row in rows)
            (
              text: _normalize(row['plain_text']?.toString() ?? ''),
              refCode: row['ref_code']!.toString().trim(),
            ),
        ]);
    return alignment.isEmpty ? null : alignment;
  }

  /// The synthesized code for the next canonical paragraph, [paragraphText],
  /// or null when it does not line up with the index.
  String? nextCodeFor(String paragraphText) {
    final text = _normalize(paragraphText);
    if (text.isEmpty) return null;
    final end = (_cursor + _lookahead + 1).clamp(0, _rows.length);
    for (var i = _cursor; i < end; i++) {
      if (_rows[i].text == text) {
        _cursor = i + 1;
        return _rows[i].refCode;
      }
    }
    return null;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
