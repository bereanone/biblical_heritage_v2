import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Only this verified source can use the prepared WOR positions and recordings.
/// Matching is a local digest comparison; it never invokes an AI or reindexes.
class OptionalBookCompanions {
  static const worSource =
      '887a248acb34648cc510af7a0d729964d4a3736e9698e36a71583b3a6b34b4d6';
  static bool matchesWor(String? hash) => hash == worSource;
  static String? sourceFingerprint(String? fileHash, String? sourceWorkId) {
    if (fileHash != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(fileHash))
      return fileHash;
    const prefix = 'user_epub_sha256_';
    if (sourceWorkId?.startsWith(prefix) == true) {
      final hash = sourceWorkId!.substring(prefix.length);
      if (RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) return hash;
    }
    return null;
  }

  /// Call with the digest computed from the actual imported file, before local
  /// parsing. Apply existing navigation/reference work, never the book text.
  static Future<bool> apply({
    required Database db,
    required String itemId,
    required String sourceHash,
    AssetBundle? assets,
  }) async {
    if (!matchesWor(sourceHash)) return false;
    final data =
        jsonDecode(
              await (assets ?? rootBundle).loadString(
                'assets/bundled_library/wor-companion.json',
              ),
            )
            as Map;
    if (data['source_sha256'] != sourceHash) {
      throw const FormatException('Book companion does not match this source');
    }
    final navigation = (data['navigation'] as List).cast<Map>();
    final ids = {
      for (final row in navigation) row['id']: '$itemId:companion:${row['id']}',
    };
    await db.transaction((txn) async {
      for (final raw in data['reference_map'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        if (row['source_hash'] != sourceHash)
          throw const FormatException('Mismatched reference index');
        await txn.insert(
          'library_source_reference_map',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // Preserve a user's existing navigation. A new import gets the prepared TOC.
      final existing = await txn.query(
        'library_navigation_items',
        columns: ['id'],
        where: 'library_item_id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (existing.isEmpty) {
        for (final raw in navigation) {
          await txn.insert('library_navigation_items', <String, Object?>{
            ...Map<String, Object?>.from(raw),
            'id': ids[raw['id']],
            'library_item_id': itemId,
            'parent_id': ids[raw['parent_id']],
          });
        }
      }
      await txn.update(
        'library_items',
        {'cover_path': data['cover_asset']},
        where: 'id = ?',
        whereArgs: [itemId],
      );
    });
    return true;
  }
}
