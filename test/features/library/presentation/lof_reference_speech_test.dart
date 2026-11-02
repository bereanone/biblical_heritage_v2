import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_narration_text.dart';

void main() {
  test('every actual LOF abbreviation family expands before speech', () {
    final delivery = jsonDecode(File('assets/bundled_library/audio.json').readAsStringSync()) as Map;
    final spec = (delivery['packages'] as List).cast<Map>().singleWhere((p) => p['id'] == 'lof');
    final member = (spec['files'] as List).cast<Map>().singleWhere((f) => f['name'] == 'audio-manifest.json');
    final manifest = jsonDecode(File(member['asset'] as String).readAsStringSync()) as Map;
    final missingFamilies = RegExp(r'\b(?:Heb\.|Phil\.|Gal\.|Eph\.|Thess\.|Deut\.|Sam\.|Isa\.|Col\.|Num\.|Tim\.|Eze\.|Zech\.)\s+\d+\s*:', caseSensitive: false);
    var passages = 0;
    var covered = 0;
    for (final track in manifest['tracks'] as List) {
      for (final cue in track['cues'] as List) {
        final printed = cue['text'] as String;
        covered += missingFamilies.allMatches(printed).length;
        final spoken = prepareLibraryNarrationText(printed);
        expect(missingFamilies.hasMatch(spoken), isFalse, reason: printed);
        if (printed.contains('Habakkuk (2:4)')) {
          expect(spoken, contains('Habakkuk chapter two verse four'));
          passages++;
        }
      }
    }
    expect(covered, 74);
    expect(passages, 1);
  });
}
