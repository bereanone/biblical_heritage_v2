import 'dart:convert';

import '../../../library/data/library_citation_display_helper.dart';
import '../tag_quick_apply_helper.dart';

/// The kinds of entry a tag can hold, as the app stores them. A `HashTagEntry`
/// has no type field, so the kind is read from how the entry was created:
///
/// * [scripture]: a Bible verse or verse range (book, chapter and verse all
///   set). The identifier is the reference, the content is the verse text.
/// * [eLibraryPassage]: a quote saved from an eLibrary book. It has no Bible
///   anchor; `note_format_json` carries `kind: elibrary_note` plus the source
///   title and location. The identifier is the work and location, the content
///   is the quoted passage.
/// * [note]: everything else without a Bible anchor: standalone notes, `$`-tag
///   slides and image-only items. There is no separate content; the note is
///   the material. The identifier is the entry's own title.
enum TagEntryType { scripture, eLibraryPassage, note }

TagEntryType tagEntryTypeOf(HashTagEntry entry) {
  if (entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0) {
    return TagEntryType.scripture;
  }
  if (ELibraryPassageSource.tryParse(entry) != null) {
    return TagEntryType.eLibraryPassage;
  }
  return TagEntryType.note;
}

/// The parts of an eLibrary passage entry that speech needs.
class ELibraryPassageSource {
  const ELibraryPassageSource({
    required this.title,
    required this.acronym,
    required this.location,
    required this.pageNumber,
    required this.paragraphNumber,
    required this.excerpt,
    required this.selectedText,
    required this.sourceParagraph,
  });

  final String title;
  final String acronym;

  /// The location as authored: `sourceReferenceText` if it is presentable,
  /// else `sourceLocation`. Empty when neither is.
  final String location;
  final int? pageNumber;
  final int? paragraphNumber;
  final String excerpt;
  final String selectedText;
  final String sourceParagraph;

  static ELibraryPassageSource? tryParse(HashTagEntry entry) {
    final raw = entry.noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      String text(String key) => decoded[key]?.toString().trim() ?? '';
      int? number(String key) => int.tryParse(decoded[key]?.toString() ?? '');
      final referenceText = librarySafeUserFacingReferenceText(
        text('source_reference_text'),
      );
      final locationText = librarySafeUserFacingReferenceText(
        text('source_location'),
      );
      return ELibraryPassageSource(
        title: librarySafeUserFacingReferenceText(text('source_title')) ?? '',
        acronym: text('source_title_acronym'),
        location: referenceText ?? locationText ?? '',
        pageNumber: number('source_page_number'),
        paragraphNumber: number('source_paragraph_number'),
        excerpt: text('excerpt'),
        selectedText: text('selected_text_snapshot'),
        sourceParagraph: text('source_paragraph'),
      );
    } catch (_) {
      return null;
    }
  }

  /// What is read aloud to say where the passage comes from, e.g. "Steps to
  /// Christ, page 12, paragraph 3". Null when nothing presentable is known.
  String? get spokenReference {
    var where = location;
    if (where.isEmpty && pageNumber != null && paragraphNumber != null) {
      where = '$pageNumber.$paragraphNumber';
    }
    where = _withoutLeadingName(where, title);
    where = _withoutLeadingName(where, acronym);
    where = _spokenLocation(where);
    if (title.isEmpty) return where.isEmpty ? null : where;
    return where.isEmpty ? title : '$title, $where';
  }
}

/// Drops [name] from the start of [text] ("SC 12.3" with acronym "SC" becomes
/// "12.3") so the title is not said twice or an initialism spelled out.
String _withoutLeadingName(String text, String name) {
  if (name.isEmpty || text.length < name.length) return text;
  if (!text.toLowerCase().startsWith(name.toLowerCase())) return text;
  // Only a whole word: "SC" must not be cut out of "Schemes".
  if (RegExp(r'\p{L}', unicode: true).hasMatch(text[name.length])) return text;
  return text
      .substring(name.length)
      .replaceFirst(RegExp(r'^[\s,;:—–-]+'), '')
      .trim();
}

/// Rewrites citation shorthand into words: "12.3" is page 12, paragraph 3
/// (the eLibrary's page.paragraph convention), "¶4" is paragraph 4.
String _spokenLocation(String location) => location
    .replaceAllMapped(
      RegExp(r'(\d{1,4})\s*\.\s*(\d{1,3})'),
      (m) => 'page ${m[1]}, paragraph ${m[2]}',
    )
    .replaceAllMapped(RegExp(r'¶\s*(\d{1,3})'), (m) => 'paragraph ${m[1]}')
    .replaceAll(RegExp(r'\bch\.\s*(?=\d)', caseSensitive: false), 'chapter ')
    .replaceAll(RegExp(r'\s*[—–]\s*'), ', ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The quoted text of an eLibrary passage and the user's own note on it, split
/// the way the detail screen's export does. When the entry was saved the note
/// text is the quote itself, so a note equal to the quote is not a note and
/// must not be read twice.
({String content, String note}) splitELibraryPassage(
  ELibraryPassageSource source, {
  required String noteText,
  required String displayTextOverride,
}) {
  String firstOf(List<String> options) =>
      options.firstWhere((t) => t.isNotEmpty, orElse: () => '');
  final content = firstOf([
    displayTextOverride,
    source.excerpt,
    source.selectedText,
    noteText,
    source.sourceParagraph,
  ]);
  String flat(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  final isNote = noteText.isNotEmpty && flat(noteText) != flat(content);
  return (content: content, note: isNote ? noteText : '');
}
