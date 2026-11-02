import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  test(
    'every shipped LOF cue has a valid digest and a source-owned text destination',
    () async {
      sqfliteFfiInit();
      final bundle =
          jsonDecode(
                await File('assets/bundled_library/audio.json').readAsString(),
              )
              as Map;
      final spec = (bundle['packages'] as List).cast<Map>().singleWhere(
        (p) => p['id'] == 'lof',
      );
      final member = (spec['files'] as List).cast<Map>().singleWhere(
        (p) => p['name'] == 'audio-manifest.json',
      );
      final raw = await File(member['asset'] as String).readAsBytes();
      expect(sha256.convert(raw).toString(), spec['sha256']);
      final manifest = jsonDecode(utf8.decode(raw)) as Map;
      final db = await databaseFactoryFfi.openDatabase(
        File('assets/bundled_library/catalog.db').absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(db.close);
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['library_item_publisher_lof_complete_2017'],
        orderBy: 'display_order',
      );
      final items = [
        for (final row in rows)
          if (![
            'image',
            'horizontalRule',
            'unsupported',
          ].contains(row['block_type']))
            LibrarySpeechItem(
              cursor: '${row['display_order']}',
              nextCursor: '${(row['display_order'] as int) + 1}',
              text: row['plain_text'] as String,
              isHeading: row['block_type'] == 'heading',
            ),
      ];
      String normalize(String text) => text
          .toLowerCase()
          .replaceAll(RegExp(r'\[\d+\]'), '')
          .replaceAll('’', "'")
          .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
          .trim();
      var count = 0;
      for (final track in manifest['tracks'] as List) {
        for (final c in track['cues'] as List) {
          final text = c['text'] as String;
          final digest = c['text_sha256'] as String?;
          if (digest != null)
            expect(
              digest,
              sha256.convert(utf8.encode(normalize(text))).toString(),
              reason: 'cue ${c['source_cursor']}',
            );
          final cue = RecordedLibraryAudioCue(
            Duration(milliseconds: c['start_ms'] as int),
            text,
            textDigest: digest,
            sourceCursor: c['source_cursor'] as String?,
          );
          expect(
            recordedCueItemIndex(cue, items),
            greaterThanOrEqualTo(0),
            reason: 'missing source mapping for ${c['source_cursor']}',
          );
          count++;
        }
      }
      var openingCount = 0;
      for (final track in manifest['tracks'] as List) {
        final first = (track['cues'] as List).first as Map;
        final match = items.indexWhere(
          (item) => item.sourceCursor == first['source_cursor'],
        );
        expect(match, greaterThanOrEqualTo(0));
        final headings = recordedChapterOpeningItems(items, match).toList();
        expect(
          headings,
          isNotEmpty,
          reason: 'Missing opening for ${track['title']}',
        );
        openingCount += headings.length;
        if (first['source_cursor'] == '592') {
          expect(headings.map((item) => item.sourceCursor).toSet(), {
            '590',
            '591',
          });
        }
      }
      expect(openingCount, 53);
      expect(count, 699);
    },
  );
}
