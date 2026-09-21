import 'dart:math' as math;

import '../../../library/data/library_citation_display_helper.dart';
import '../tag_quick_apply_helper.dart';
import 'tag_playback_entry_speech.dart';
import 'tag_playback_models.dart';

typedef BlockIdResolver =
    Future<int?> Function(int bookNumber, int chapter, int verse);

const _ordinals = {'1': 'First', '2': 'Second', '3': 'Third'};

/// How a reference is read aloud: "John 3, verse 16" / "First John 1, verses
/// 8 to 9". Digits like "3:16" are ambiguous to the synthesizer, and "1 John"
/// would be read as "one John".
String spokenBibleReference({
  required String bookName,
  required int chapter,
  required int verseStart,
  required int verseEnd,
}) {
  var name = bookName.trim();
  if (name == 'Psalms') name = 'Psalm';
  final numbered = RegExp(r'^([1-3])\s+(.+)$').firstMatch(name);
  if (numbered != null) {
    name = '${_ordinals[numbered.group(1)]} ${numbered.group(2)}';
  }
  final end = math.max(verseStart, verseEnd);
  final verses = end > verseStart
      ? 'verses $verseStart to $end'
      : 'verse $verseStart';
  return '$name $chapter, $verses';
}

/// Splits prose into clips of whole sentences no longer than [maxChars]
/// (a single longer sentence stays whole). Short clips start sooner, are
/// prefetched independently, and keep memory per buffered clip small.
/// Paragraph breaks always start a new clip.
List<String> splitIntoSpeechChunks(String text, {int maxChars = 320}) {
  final chunks = <String>[];
  for (final paragraph in text.split(RegExp(r'\n+'))) {
    final clean = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) continue;
    var current = '';
    for (final sentence in clean.split(RegExp(r'(?<=[.!?])\s+'))) {
      if (current.isEmpty) {
        current = sentence;
      } else if (current.length + 1 + sentence.length <= maxChars) {
        current = '$current $sentence';
      } else {
        chunks.add(current);
        current = sentence;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
  }
  return chunks;
}

/// Plain text of stored `$`-tag HTML (same rules the detail screen displays).
String plainTextFromStoredHtml(String input) {
  return input
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

/// Converts a tag's entries (already in display order) into speech items.
/// Every entry yields an item, even one with nothing to say, so positions
/// match the list the user sees; the controller skips silent items.
class TagPlaybackPlanner {
  TagPlaybackPlanner({
    required this.bookNames,
    required this.resolveBlockId,
    this.maxNoteChunkChars = 320,
  });

  final Map<int, String> bookNames;
  final BlockIdResolver resolveBlockId;
  final int maxNoteChunkChars;

  Future<List<TagPlaybackItem>> plan(List<HashTagEntry> entries) async {
    return [for (final entry in entries) await _planEntry(entry)];
  }

  String _noteText(HashTagEntry entry) {
    final note = entry.noteText?.trim() ?? '';
    if (note.isNotEmpty) return note;
    return plainTextFromStoredHtml(entry.contentHtml ?? '');
  }

  Future<int?> _blockId(int book, int chapter, int verse) async {
    try {
      return await resolveBlockId(book, chapter, verse);
    } catch (_) {
      return null; // Speech still works; only the verse's patches are lost.
    }
  }

  Future<TagPlaybackItem> _planEntry(HashTagEntry entry) async {
    return switch (tagEntryTypeOf(entry)) {
      TagEntryType.scripture => _planScripture(entry),
      TagEntryType.eLibraryPassage => _planELibraryPassage(entry),
      TagEntryType.note => _planNote(entry),
    };
  }

  List<TagSpeechClip> _noteClips(String text) => [
    for (final chunk in splitIntoSpeechChunks(
      text,
      maxChars: maxNoteChunkChars,
    ))
      TagSpeechClip(text: chunk, kind: TagClipKind.note),
  ];

  /// Every entry says what it is before its content when the reference is on.
  /// An entry with no content of its own still gets that lead-in as a clip of
  /// its own, so it is announced (and its note read) rather than skipped.
  List<TagSpeechClip> _contentClips({
    required String? reference,
    required List<String> content,
    required TagClipKind kind,
  }) {
    if (content.isEmpty) {
      return [
        if (reference != null)
          TagSpeechClip(text: '', kind: kind, reference: reference),
      ];
    }
    return [
      for (var i = 0; i < content.length; i++)
        TagSpeechClip(
          text: content[i],
          kind: kind,
          reference: i == 0 ? reference : null,
        ),
    ];
  }

  Future<TagPlaybackItem> _planScripture(HashTagEntry entry) async {
    final noteClips = _noteClips(_noteText(entry));
    final bookName = bookNames[entry.bookNumber] ?? 'Book ${entry.bookNumber}';
    final label = bibleRangeReferenceLabel(
      bookName: bookName,
      chapter: entry.chapter,
      verseStart: entry.verse,
      verseEnd: entry.verseEnd,
    );
    final spokenReference = spokenBibleReference(
      bookName: bookName,
      chapter: entry.chapter,
      verseStart: entry.verse,
      verseEnd: entry.verseEnd,
    );
    final override = entry.displayTextOverride?.trim() ?? '';
    final verseText = override.isNotEmpty ? override : entry.verseText.trim();
    final verseClips = await _verseClips(
      entry,
      spokenReference: spokenReference,
      verseText: verseText,
      edited: override.isNotEmpty,
    );
    return TagPlaybackItem(
      entryId: entry.id,
      label: label.isEmpty ? entry.verseRef : label,
      preview: verseText.isNotEmpty
          ? verseText
          : (noteClips.isEmpty ? '' : noteClips.first.body),
      // A verse whose text is missing still says where it is.
      contentClips: verseClips.isNotEmpty
          ? verseClips
          : _contentClips(
              reference: spokenReference,
              content: const [],
              kind: TagClipKind.verse,
            ),
      noteClips: noteClips,
    );
  }

  Future<TagPlaybackItem> _planELibraryPassage(HashTagEntry entry) async {
    final source = ELibraryPassageSource.tryParse(entry)!;
    final split = splitELibraryPassage(
      source,
      noteText: _noteText(entry),
      displayTextOverride: entry.displayTextOverride?.trim() ?? '',
    );
    final content = splitIntoSpeechChunks(
      split.content,
      maxChars: maxNoteChunkChars,
    );
    final noteClips = _noteClips(split.note);
    final userTitle = entry.userTitle?.trim() ?? '';
    // The work and location identify the passage, as on the detail screen; the
    // user's own title only stands in when the source is unknown.
    final reference =
        source.spokenReference ?? (userTitle.isEmpty ? null : userTitle);
    final display = [
      if (source.title.isNotEmpty) source.title,
      if (source.location.isNotEmpty) source.location,
    ].join(' — ');
    return TagPlaybackItem(
      entryId: entry.id,
      label: display.isNotEmpty
          ? display
          : (userTitle.isNotEmpty ? userTitle : 'eLibrary quote'),
      preview: content.isNotEmpty
          ? content.first
          : (noteClips.isEmpty ? '' : noteClips.first.body),
      contentClips: _contentClips(
        reference: reference,
        content: content,
        kind: TagClipKind.passage,
      ),
      noteClips: noteClips,
    );
  }

  /// Note-only entries (standalone notes, `$`-tag slides, image-only items):
  /// the note is the material, so it is the only content. Images are never
  /// spoken. The identifier is the entry's own title, or its reference code;
  /// an untitled note has none and is simply read.
  Future<TagPlaybackItem> _planNote(HashTagEntry entry) async {
    final noteClips = _noteClips(_noteText(entry));
    final userTitle = entry.userTitle?.trim() ?? '';
    final referenceCode =
        librarySafeUserFacingReferenceText(entry.referenceCode) ?? '';
    final reference = userTitle.isNotEmpty
        ? userTitle
        : (referenceCode.isEmpty ? null : referenceCode);
    return TagPlaybackItem(
      entryId: entry.id,
      label: userTitle.isNotEmpty ? userTitle : 'Note',
      preview: noteClips.isEmpty ? '' : noteClips.first.body,
      contentClips: _contentClips(
        reference: reference,
        content: const [],
        kind: TagClipKind.note,
      ),
      noteClips: noteClips,
    );
  }

  Future<List<TagSpeechClip>> _verseClips(
    HashTagEntry entry, {
    required String spokenReference,
    required String verseText,
    required bool edited,
  }) async {
    if (verseText.isEmpty) return const <TagSpeechClip>[];
    TagSpeechClip clip(String text, int? blockId, {String? reference}) =>
        TagSpeechClip(
          text: text,
          kind: TagClipKind.verse,
          blockId: blockId,
          reference: reference,
        );

    final length = entry.verseEnd > entry.verse
        ? entry.verseEnd - entry.verse + 1
        : 1;
    final lines = verseText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    // One clip per verse so each keeps its own pronunciation patches. This
    // relies on the range text being one line per verse; otherwise fall back
    // to a single clip without patches.
    if (!edited && length > 1 && lines.length == length) {
      final clips = <TagSpeechClip>[];
      for (var i = 0; i < lines.length; i++) {
        final blockId = await _blockId(
          entry.bookNumber,
          entry.chapter,
          entry.verse + i,
        );
        clips.add(
          clip(lines[i], blockId, reference: i == 0 ? spokenReference : null),
        );
      }
      return clips;
    }
    final blockId = length == 1
        ? await _blockId(entry.bookNumber, entry.chapter, entry.verse)
        : null;
    final body = lines.join(' ');
    return [clip(body, blockId, reference: spokenReference)];
  }
}
