import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/bundled_library_content.dart';
import 'package:studybible2/features/library/data/lessons_reading_edition.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

class DiskAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'desktop subset installs only the bounded new edition and preserves older content',
    () async {
      final root = await Directory.systemTemp.createTemp('lof-delivery-');
      final db = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      await ELibrarySchema.ensure(db);
      try {
        final old = {
          'id': LessonsReadingEdition.legacyItemId,
          'title': 'My older edition',
          'file_name': 'old.html',
          'relative_path': 'old.html',
          'last_opened': 'saved',
          'paragraph_index': 17,
          'created_at': 'personal',
          'updated_at': 'personal',
          'device_id': 'personal',
        };
        await db.insert('library_items', old);
        final before = (await db.query('library_items')).single;
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: root.path,
            assets: DiskAssets(),
            onlyItemIds: {LessonsReadingEdition.itemId},
          ),
          1,
        );
        expect((await db.query('library_items')).length, 2);
        expect(
          (await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: [LessonsReadingEdition.legacyItemId],
          )).single,
          before,
        );
        expect(
          await File(
            '${root.path}/Research/ManagedBundles/lof-reading-copy-v1/Lessons-on-Faith.epub',
          ).exists(),
          isTrue,
        );
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: root.path,
            assets: DiskAssets(),
            onlyItemIds: {LessonsReadingEdition.itemId},
          ),
          0,
        );
        await expectLater(
          BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: root.path,
            assets: DiskAssets(),
            onlyItemIds: {'unknown'},
          ),
          throwsFormatException,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'all 699 actual recording cues map to their exact source and all 27 chapter destinations',
    () async {
      final audio =
          jsonDecode(
                await File('assets/bundled_library/audio.json').readAsString(),
              )
              as Map;
      final spec = (audio['packages'] as List).cast<Map>().singleWhere(
        (x) => x['id'] == 'lof',
      );
      expect(spec['requires_source_sha256'], LessonsReadingEdition.sourceHash);
      final files = (spec['files'] as List).cast<Map>();
      final raw = await File(
        files.singleWhere((x) => x['name'] == 'audio-manifest.json')['asset']
            as String,
      ).readAsBytes();
      expect(sha256.convert(raw).toString(), spec['sha256']);
      final manifest = jsonDecode(utf8.decode(raw)) as Map;
      final db = await openReadOnlyDatabase(
        File('assets/bundled_library/catalog.db').absolute.path,
        singleInstance: false,
      );
      try {
        final blocks = await db.query(
          'library_document_blocks',
          where: 'library_item_id=?',
          whereArgs: [LessonsReadingEdition.itemId],
          orderBy: 'display_order',
        );
        final speech = blocks
            .where(
              (b) =>
                  ![
                    'image',
                    'horizontalRule',
                    'unsupported',
                  ].contains(b['block_type']) &&
                  b['plain_text'].toString().trim().isNotEmpty,
            )
            .map(
              (b) => LibrarySpeechItem(
                cursor: '${b['display_order']}',
                nextCursor: '${(b['display_order'] as int) + 1}',
                text: b['plain_text'] as String,
              ),
            )
            .toList();
        var next = 0, count = 0;
        final recorded = <String>{};
        final chapterStarts = <String>[];
        for (final track in manifest['tracks'] as List) {
          final cues = (track['cues'] as List).cast<Map>();
          chapterStarts.add(cues.first['source_cursor'] as String);
          for (final q in cues) {
            final cue = RecordedLibraryAudioCue(
              Duration(milliseconds: q['start_ms'] as int),
              q['text'] as String,
              textDigest: q['text_sha256'] as String,
              sourceCursor: q['source_cursor'] as String,
            );
            final matched = recordedCueItemIndex(cue, speech, startIndex: next);
            expect(matched, greaterThanOrEqualTo(0));
            expect(speech[matched].cursor, q['source_cursor']);
            next = matched;
            recorded.add(speech[matched].cursor);
            count++;
          }
        }
        expect(count, 699);
        final nav = await db.query(
          'library_document_navigation',
          where: 'library_item_id=?',
          whereArgs: [LessonsReadingEdition.itemId],
          orderBy: 'display_order',
        );
        expect(nav.length, 27);
        for (var i = 0; i < nav.length; i++) {
          final heading = blocks.singleWhere(
            (b) => b['id'] == nav[i]['target_block_id'],
          );
          final dest = await recordedCursorForNavigation(
            cursor: '${heading['display_order']}',
            recordedCursors: recorded,
            load: (cursor) async {
              for (final item in speech) {
                if (int.parse(item.cursor) >= int.parse(cursor)) return item;
              }
              return null;
            },
          );
          expect(dest, chapterStarts[i], reason: nav[i]['label'].toString());
        }
      } finally {
        await db.close();
      }
    },
  );
}
