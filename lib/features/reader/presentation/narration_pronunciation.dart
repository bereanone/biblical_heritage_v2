import 'dart:convert';

const defaultNarrationPronunciations = <String, String>{
  'Sodom': 'Soddum',
  'Gomorrah': 'go-morrah',
  'hast': 'hasst',
  'live for ever': 'liv for ever',
  'live forever': 'liv forever',
};

String _pronunciationKey(String value) => value.trim().toLowerCase();

Map<String, String> decodeNarrationPronunciations(
  String? value, {
  bool includeDefaults = true,
}) {
  Map<String, String> defaults() =>
      includeDefaults ? Map.of(defaultNarrationPronunciations) : {};
  if (value == null) return defaults();
  try {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    final versioned = decoded['version'] == 2 && decoded['rules'] is Map;
    final saved = versioned
        ? Map<String, dynamic>.from(decoded['rules'] as Map)
        : decoded;
    // An explicitly cleared legacy dictionary meant "no corrections".
    if (!versioned && saved.isEmpty) return {};
    final rules = defaults();
    final disabled = versioned && decoded['disabledDefaults'] is List
        ? (decoded['disabledDefaults'] as List)
              .whereType<String>()
              .map(_pronunciationKey)
              .toSet()
        : <String>{};
    rules.removeWhere((key, _) => disabled.contains(_pronunciationKey(key)));
    for (final entry in saved.entries) {
      if (entry.key.trim().isEmpty ||
          entry.value is! String ||
          (entry.value as String).trim().isEmpty)
        continue;
      rules.removeWhere(
        (key, _) => _pronunciationKey(key) == _pronunciationKey(entry.key),
      );
      rules[entry.key.trim()] = (entry.value as String).trim();
    }
    return rules;
  } catch (_) {
    return defaults();
  }
}

/// Persist intentional removals separately so a future default can be added
/// without resurrecting a correction the user explicitly removed.
String encodeNarrationPronunciations(Map<String, String> rules) {
  final keys = rules.keys.map(_pronunciationKey).toSet();
  return jsonEncode({
    'version': 2,
    'rules': rules,
    'disabledDefaults': [
      for (final key in defaultNarrationPronunciations.keys)
        if (!keys.contains(_pronunciationKey(key))) key,
    ],
  });
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
  if (current != null)
    return decodeNarrationPronunciations(current, includeDefaults: false);
  final previous = await load('narration_deferred_pronunciations_v1');
  final deferred = previous == null
      ? Map<String, String>.of(rules)
      : decodeNarrationPronunciations(previous, includeDefaults: false);
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
