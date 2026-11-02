import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The complete source paired with the verified LOF recordings. Older editions
/// retain their IDs, content and study data.
class LessonsReadingEdition {
  static const itemId = 'library_item_publisher_lof_complete_2017';
  static const legacyItemId =
      'library_item_research_pioneer_at_jones_lessons_on_faith';
  static const sourceHash =
      '14a067c0b0a6cdf8cdf8fbbcf3205bdf261d69d7288512ffe041c7034a4a1c66';
  static const shelfDeliveryKey = 'library.lof_reading_edition_shelf_v2';

  /// Replace the older shelf shortcut once; keep its book and study data.
  /// A later user removal of the complete edition is respected.
  static Future<void> offerOnExistingShelf(
    Database db,
    Set<String> available,
  ) async {
    if (!available.contains(itemId)) return;
    await db.transaction((txn) async {
      final receipt = await txn.query(
        'app_settings',
        where: 'key=?',
        whereArgs: [shelfDeliveryKey],
      );
      if (receipt.isNotEmpty) return;
      final rows = await txn.query(
        'app_settings',
        where: 'key=?',
        whereArgs: ['elibrary_top_shelf_v1'],
      );
      final raw = rows.isEmpty ? null : rows.single['value']?.toString();
      dynamic decoded;
      try {
        decoded = raw == null ? <dynamic>[] : jsonDecode(raw);
      } on FormatException {
        return;
      }
      if (decoded is! List || decoded.any((id) => id is! String)) return;
      final ids = decoded.cast<String>().toList();
      if (available.contains(legacyItemId) &&
          ids.contains(legacyItemId)) {
        final position = ids.indexOf(legacyItemId);
        ids.removeWhere((id) => id == legacyItemId);
        if (!ids.contains(itemId)) ids.insert(position, itemId);
        await txn.update(
          'app_settings',
          {'value': jsonEncode(ids)},
          where: 'key=?',
          whereArgs: ['elibrary_top_shelf_v1'],
        );
      }
      await txn.insert('app_settings', {'key': shelfDeliveryKey, 'value': '1'});
    });
  }
}
