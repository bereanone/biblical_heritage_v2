import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/audio_timeline_migration.dart';

void main() {
  final cases =
      jsonDecode(
            File(
              'test/fixtures/library_audio_timeline.json',
            ).readAsStringSync(),
          )
          as List;
  for (final row in cases) {
    test(row['name'] as String, () {
      expect(
        remapLibraryAudioPosition(
          Map<String, dynamic>.from(row['saved'] as Map),
          Map<String, dynamic>.from(row['migration'] as Map),
          row['tracks'] as List,
        ),
        row['expected'],
      );
    });
  }
}
