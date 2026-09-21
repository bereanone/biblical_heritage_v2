import 'dart:convert';
import 'narration_pronunciation.dart';

/// Speech-only sidecar. Changed source text never receives stored word offsets.
class BiblePronunciationMap {
  BiblePronunciationMap(String json, String lexicon)
    : _verses =
          (jsonDecode(json) as Map<String, dynamic>)['verses']
              as Map<String, dynamic>,
      _knownWords = lexicon
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.split(RegExp(r'\s+')).first.toLowerCase())
          .toSet();
  final Map<String, dynamic> _verses;
  final Set<String> _knownWords;

  String prepare(
    String text, {
    int? blockId,
    required Map<String, String> corrections,
    Map<String, String> deferredCorrections = const {},
    bool preferDictionary = true,
  }) {
    final deferred = {
      for (final e in deferredCorrections.entries) e.key.toLowerCase(): e.value,
    };
    // Only the user's old workarounds are deferred. New or edited corrections win.
    final active = <String, String>{
      for (final e in corrections.entries)
        if (!preferDictionary ||
            deferred[e.key.toLowerCase()] != e.value ||
            !_knownWords.contains(e.key.trim().toLowerCase()))
          e.key: e.value,
    };
    final protected = <RegExpMatch>[];
    for (final key in active.keys) {
      protected.addAll(
        RegExp(
          '(?<![\\p{L}\\p{N}_])${RegExp.escape(key)}(?![\\p{L}\\p{N}_])',
          caseSensitive: false,
          unicode: true,
        ).allMatches(text),
      );
    }
    var spoken = text;
    final entry = _verses['$blockId'] as Map<String, dynamic>?;
    if (preferDictionary && entry != null) {
      final original = entry['text'] as String;
      // Optional chapter/verse announcements precede the exact verse.
      if (original.isNotEmpty &&
          (text == original || text.endsWith(' $original'))) {
        final offset = text.length - original.length;
        for (final raw in (entry['patches'] as List<dynamic>).reversed) {
          final p = raw as Map<String, dynamic>;
          final start = (p['start'] as num).toInt();
          final end = (p['end'] as num).toInt();
          if (start < 0 ||
              end > original.length ||
              start >= end ||
              original.substring(start, end) != p['word']) {
            continue;
          }
          if (protected.any(
            (m) => m.start < offset + end && m.end > offset + start,
          )) {
            continue;
          }
          spoken = spoken.replaceRange(
            offset + start,
            offset + end,
            p['alias'] as String,
          );
        }
      }
    }
    // Normalize only after source-offset patches and saved correction matching.
    // Kokoro splits typographic apostrophes into separate spoken tokens.
    return prepareNarrationPronunciation(
      spoken,
      corrections: active,
    ).replaceAllMapped(
      RegExp(r"(?<=\p{L})[’‘ʼ](?=\p{L})", unicode: true),
      (_) => "'",
    );
  }
}
