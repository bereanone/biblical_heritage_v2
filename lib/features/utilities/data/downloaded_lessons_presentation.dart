import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Presentation applied only after a user-requested Lessons on Faith download.
/// It changes catalog metadata, never the downloaded document or its text.
class DownloadedLessonsPresentation {
  static const shelfKey = 'elibrary_top_shelf_v1';
  static const coverPath = 'assets/library_covers/LOF_ATJ.png';

  static bool matches(String title) =>
      title.trim().toLowerCase() == 'lessons on faith';

  static Future<bool> apply({
    required Database libraryDb,
    required Database settingsDb,
    required String itemId,
    required String title,
    required bool downloadSucceeded,
  }) async {
    if (!downloadSucceeded || !matches(title)) return false;
    final rows = await libraryDb.query(
      'library_items',
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    // Read/update the shelf inside one transaction to retain concurrent ordering.
    await settingsDb.transaction((txn) async {
      final setting = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [shelfKey],
        limit: 1,
      );
      final raw = setting.isEmpty ? null : setting.single['value']?.toString();
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw);
      if (decoded is! List || decoded.any((id) => id is! String)) {
        throw const FormatException('Existing Top Shelf preference is invalid');
      }
      final ids = decoded.cast<String>().toList();
      if (!ids.contains(itemId)) {
        ids.add(itemId);
        await txn.insert('app_settings', {
          'key': shelfKey,
          'value': jsonEncode(ids),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await libraryDb.update(
      'library_items',
      {'cover_path': coverPath},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
    );
    return true;
  }
}
