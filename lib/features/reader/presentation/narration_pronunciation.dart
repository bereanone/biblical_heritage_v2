import 'dart:convert';

const defaultNarrationPronunciations = <String, String>{
  'Sodom': 'Soddum',
  'Gomorrah': 'go-morrah',
  'hast': 'hasst',
  'live for ever': 'liv for ever',
  'live forever': 'liv forever',
};

Map<String, String> decodeNarrationPronunciations(String? value) {
  if (value == null) return Map.of(defaultNarrationPronunciations);
  try {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        if (entry.key.trim().isNotEmpty &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty)
          entry.key.trim(): (entry.value as String).trim(),
    };
  } catch (_) {
    return Map.of(defaultNarrationPronunciations);
  }
}

/// Applies each whole-word correction once to speech input, never stored text.
String prepareNarrationPronunciation(
  String text, {
  Map<String, String> corrections = defaultNarrationPronunciations,
}) {
  if (corrections.isEmpty) return text;
  final normalized = {
    for (final entry in corrections.entries)
      if (entry.key.trim().isNotEmpty)
        entry.key.trim().toLowerCase(): entry.value,
  };
  final words = normalized.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (words.isEmpty) return text;
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}_])(?:${words.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}_])',
    caseSensitive: false,
    unicode: true,
  );
  return text.replaceAllMapped(
    pattern,
    (match) => normalized[match[0]!.toLowerCase()]!,
  );
}

/// Retain old spelling workarounds while the shared dictionary takes over.
/// The snapshot is written once; corrections edited afterward still win.
Future<Map<String, String>> loadDeferredNarrationPronunciations({
  required Map<String, String> rules,
  required Future<String?> Function(String) load,
  required Future<void> Function(String, String) save,
}) async {
  const key = 'narration_deferred_pronunciations_v2';
  final current = await load(key);
  if (current != null) return decodeNarrationPronunciations(current);
  final previous = await load('narration_deferred_pronunciations_v1');
  final deferred = previous == null
      ? Map<String, String>.of(rules)
      : decodeNarrationPronunciations(previous);
  const churches = {
    'ephesus',
    'smyrna',
    'pergamos',
    'thyatira',
    'sardis',
    'philadelphia',
    'laodicea',
  };
  for (final entry in rules.entries) {
    if (churches.contains(entry.key.trim().toLowerCase())) {
      deferred.removeWhere(
        (key, _) => key.toLowerCase() == entry.key.toLowerCase(),
      );
      deferred[entry.key] = entry.value;
    }
  }
  await save(key, jsonEncode(deferred));
  return deferred;
}
