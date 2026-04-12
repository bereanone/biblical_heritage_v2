import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/user_database.dart';

class NavigationHistoryEntry {
  const NavigationHistoryEntry({
    required this.blockId,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.updatedAt,
  });

  factory NavigationHistoryEntry.fromMap(Map<String, Object?> row) {
    return NavigationHistoryEntry(
      blockId: row['block_id'] as int,
      book: row['book'] as int,
      chapter: row['chapter'] as int,
      verse: row['verse'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  final int blockId;
  final int book;
  final int chapter;
  final int verse;
  final int updatedAt;
}

class NavigationHistoryService {
  NavigationHistoryService._();

  static final NavigationHistoryService instance = NavigationHistoryService._();

  Future<NavigationHistoryEntry?> fetchLatest() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'navigation_history',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NavigationHistoryEntry.fromMap(rows.first);
  }

  Future<void> saveSelection({
    required int blockId,
    required int book,
    required int chapter,
    required int verse,
  }) async {
    final db = await UserDatabase.instance.database;
    await db.insert(
      'navigation_history',
      {
        'id': 1,
        'block_id': blockId,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
