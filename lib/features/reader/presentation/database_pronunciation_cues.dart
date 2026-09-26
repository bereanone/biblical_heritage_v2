import 'dart:convert';
import 'package:crypto/crypto.dart';

List<Map<String, dynamic>>? databasePronunciationPatches(
  String text,
  String raw,
  Map<String, Set<String>> knownPronunciations,
) {
  const schemaVersion = 1;
  const tokenizerVersion = 'ascii-apostrophe-v1';
  const engine = 'sherpa-onnx-kokoro';
  const phonemeFormat = 'kokoro-model-symbols';

  try {
    final json = jsonDecode(raw) as Map<String, dynamic>?;
    if (json == null) return null;

    if (json['schema_version'] != schemaVersion ||
        json['tokenizer_version'] != tokenizerVersion ||
        json['engine'] != engine ||
        json['phoneme_format'] != phonemeFormat) {
      return null;
    }

    final textSha256 = sha256.convert(utf8.encode(text)).toString();
    if (json['text_sha256'] != textSha256) return null;

    final words = json['words'] as List<dynamic>?;
    if (words == null || words.isEmpty) return null;

    final tokenRegex = RegExp(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*");
    final tokens = tokenRegex.allMatches(text).toList();
    if (tokens.length != words.length) return null;

    final patches = <Map<String, dynamic>>[];
    final usedIndices = <int>{}, usedRanges = <String>{};

    for (int i = 0; i < words.length; i++) {
      final wordObj = words[i] as Map<String, dynamic>?;
      if (wordObj == null) return null;

      final token = tokens[i];
      final rawWord = token.group(0);
      final startUtf16 = token.start;
      final endUtf16 = token.end;

      if (wordObj['i'] is! int ||
          wordObj['i'] != i ||
          wordObj['word'] != rawWord ||
          wordObj['start_utf16'] != startUtf16 ||
          wordObj['end_utf16'] != endUtf16) {
        return null;
      }

      final status = wordObj['review_status'] as String?;
      if (status != 'reviewed') continue;

      final alias = wordObj['alias'] as String?;
      if (alias == null || alias.isEmpty) continue;

      final aliasKey = alias.toLowerCase();
      final validPhonemes = knownPronunciations[aliasKey];
      if (validPhonemes == null || validPhonemes.isEmpty) continue;

      final phonemes = wordObj['phonemes'] as List<dynamic>?;
      if (phonemes == null ||
          phonemes.length != 1 ||
          phonemes[0] is! String ||
          !validPhonemes.contains(phonemes[0])) {
        continue;
      }

      final rangeKey = '$startUtf16-$endUtf16';
      if (usedIndices.contains(i) || usedRanges.contains(rangeKey)) {
        return null;
      }

      usedIndices.add(i);
      usedRanges.add(rangeKey);

      patches.add({
        'start': startUtf16,
        'end': endUtf16,
        'word': rawWord,
        'alias': alias,
      });
    }

    if (patches.isEmpty) return null;

    patches.sort((a, b) => a['start'].compareTo(b['start']));
    return patches;
  } catch (_) {
    return null;
  }
}
