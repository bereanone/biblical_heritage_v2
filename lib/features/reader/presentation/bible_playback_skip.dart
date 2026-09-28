import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bible_loop_announcement_settings.dart';
import 'bible_visible_location_controller.dart';

/// Resolve from canonical rows, not the currently loaded reader window.
/// At the beginning/end of the Bible there is no destination (no wrapping).
Future<BibleVisibleLocation?> loadBiblePlaybackSkipTarget(
  DatabaseExecutor db, {
  required BibleVisibleLocation current,
  required BibleLoopUnit? loop,
  required bool forward,
}) async {
  final comparison = forward ? '>' : '<';
  final order = forward ? 'ASC' : 'DESC';
  final String where;
  final List<Object?> args;
  switch (loop) {
    case BibleLoopUnit.book:
      where = 'book_number $comparison ? AND chapter = 1 AND block_index = 1';
      args = [current.bookNumber];
    case BibleLoopUnit.chapter:
      where =
          '(book_number $comparison ? OR (book_number = ? AND chapter $comparison ?)) AND block_index = 1';
      args = [current.bookNumber, current.bookNumber, current.chapter];
    case BibleLoopUnit.verse:
    case null:
      where = 'id $comparison ?';
      args = [current.blockId];
  }
  final rows = await db.query(
    'bible_blocks',
    columns: ['id', 'book_number', 'chapter', 'block_index'],
    where: where,
    whereArgs: args,
    orderBy: 'id $order',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final row = rows.single;
  return BibleVisibleLocation(
    blockId: (row['id'] as num).toInt(),
    bookNumber: (row['book_number'] as num).toInt(),
    chapter: (row['chapter'] as num).toInt(),
    verse: (row['block_index'] as num).toInt(),
  );
}
