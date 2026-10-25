import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/presentation/bible_playback_skip.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';
import 'package:studybible2/features/reader/presentation/bible_visible_location_controller.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  final locations = <BibleVisibleLocation>[];
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE bible_blocks (id INTEGER PRIMARY KEY, book_number INTEGER, chapter INTEGER, block_index INTEGER)',
    );
    locations.clear();
    for (var book = 1; book <= 3; book++) {
      for (var chapter = 1; chapter <= 2; chapter++) {
        for (var verse = 1; verse <= 3; verse++) {
          final id = locations.length + 1;
          locations.add(
            BibleVisibleLocation(
              blockId: id,
              bookNumber: book,
              chapter: chapter,
              verse: verse,
            ),
          );
          await db.insert('bible_blocks', {
            'id': id,
            'book_number': book,
            'chapter': chapter,
            'block_index': verse,
          });
        }
      }
    }
  });
  tearDown(() => db.close());
  for (final unit in [
    null,
    BibleLoopUnit.verse,
    BibleLoopUnit.chapter,
    BibleLoopUnit.book,
  ]) {
    test(
      '$unit skips in both directions and stops at Bible boundaries',
      () async {
        Future<BibleVisibleLocation?> skip(int id, bool forward) =>
            loadBiblePlaybackSkipTarget(
              db,
              current: locations[id - 1],
              loop: unit,
              forward: forward,
            );
        final nextId = switch (unit) {
          BibleLoopUnit.chapter || null => 10,
          BibleLoopUnit.book => 13,
          _ => 9,
        };
        final previousId = switch (unit) {
          BibleLoopUnit.chapter || null => 4,
          BibleLoopUnit.book => 1,
          _ => 7,
        };
        expect((await skip(8, true))?.blockId, nextId);
        expect((await skip(8, false))?.blockId, previousId);
        expect(await skip(1, false), isNull);
        expect(await skip(18, true), isNull);
      },
    );
  }
  for (final savedLoop in [null, ...BibleLoopUnit.values]) {
    test(
      'idle arrows ignore saved $savedLoop and navigate one chapter',
      () async {
        final unit = bibleNavigationUnit(audioPlaying: false, loop: savedLoop);
        expect(unit, BibleLoopUnit.chapter);
        final forward = await loadBiblePlaybackSkipTarget(
          db,
          current: locations[7],
          loop: unit,
          forward: true,
        );
        final backward = await loadBiblePlaybackSkipTarget(
          db,
          current: locations[7],
          loop: unit,
          forward: false,
        );
        expect(forward, locations[9]);
        expect(backward, locations[3]);
      },
    );
    test('playing arrows retain saved $savedLoop scope', () {
      expect(
        bibleNavigationUnit(audioPlaying: true, loop: savedLoop),
        savedLoop ?? BibleLoopUnit.chapter,
      );
    });
  }

  test('verse and chapter skips cross book boundaries', () async {
    for (final unit in [BibleLoopUnit.verse, BibleLoopUnit.chapter]) {
      final next = await loadBiblePlaybackSkipTarget(
        db,
        current: locations[5],
        loop: unit,
        forward: true,
      );
      expect(next, locations[6]);
      final previous = await loadBiblePlaybackSkipTarget(
        db,
        current: locations[6],
        loop: unit,
        forward: false,
      );
      expect(
        previous,
        unit == BibleLoopUnit.verse ? locations[5] : locations[3],
      );
    }
  });
}
