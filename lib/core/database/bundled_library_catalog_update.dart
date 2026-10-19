import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Updates only publisher-managed book content. Reading data and annotations
/// remain in place; this service never receives or opens the study-list DB.
class BundledLibraryCatalogUpdate {
  static const contentTables = <String>[
    'library_text_blocks',
    'library_navigation_items',
    'library_links',
    'elibrary_ref_index',
    'library_document_sections',
    'library_document_blocks',
    'library_block_source_map',
    'library_document_navigation',
    'library_document_conversion',
    'library_research_index_conversion',
    'library_document_asset_sets',
    'library_document_assets',
  ];

  static Future<int> apply({
    required Database destination,
    required Database source,
    required Set<String> managedItemIds,
    required String revision,
    String? resourceRoot,
  }) async {
    if (revision.trim().isEmpty ||
        managedItemIds.isEmpty ||
        managedItemIds.any((id) => id.trim().isEmpty)) {
      throw const FormatException(
        'A content revision and managed book IDs are required',
      );
    }
    final items = <String, Map<String, Object?>>{};
    final rowsByItem = <String, Map<String, List<Map<String, Object?>>>>{};
    final blobs = <String, Map<String, Object?>>{};
    final sourceHashes = <String>{};
    final witnesses = <String, List<Map<String, Object?>>>{};
    // Fully validate the donor before beginning any destination mutation.
    for (final id in managedItemIds) {
      final rows = await source.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.length != 1) throw FormatException('Missing bundled book: $id');
      items[id] = Map<String, Object?>.of(rows.single);
      if (items[id]!['deleted_at'] != null)
        throw FormatException('Bundled book is marked deleted: $id');
      final content = <String, List<Map<String, Object?>>>{};
      for (final table in contentTables) {
        content[table] = await source.query(
          table,
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
      }
      if (content['library_text_blocks']!.isEmpty &&
          content['library_document_blocks']!.isEmpty) {
        throw FormatException('Bundled book has no readable text: $id');
      }
      for (final asset in content['library_document_assets']!) {
        final hash = asset['asset_sha256'] as String;
        if (blobs.containsKey(hash)) continue;
        final assetRows = await source.query(
          'library_asset_blobs',
          where: 'sha256 = ?',
          whereArgs: [hash],
        );
        if (assetRows.length != 1)
          throw FormatException('Missing bundled image: $hash');
        final blob = assetRows.single;
        final data = blob['data'] as List<int>;
        if (blob['byte_length'] != data.length ||
            sha256.convert(data).toString() != hash) {
          throw const FormatException('Bundled image integrity check failed');
        }
        blobs[hash] = blob;
      }
      for (final conversion in content['library_document_conversion']!) {
        if (conversion['status'] != 'complete' ||
            content['library_document_blocks']!.isEmpty) {
          throw FormatException('Incomplete bundled document: $id');
        }
        final hash = conversion['source_hash']?.toString();
        if (hash != null && hash.isNotEmpty) sourceHashes.add(hash);
      }
      rowsByItem[id] = content;
    }
    for (final table in [
      'library_source_reference_map',
      'library_source_page_profiles',
    ]) {
      witnesses[table] = [];
      for (final hash in sourceHashes) {
        witnesses[table]!.addAll(
          await source.query(
            table,
            where: 'source_hash = ?',
            whereArgs: [hash],
          ),
        );
      }
    }
    return destination.transaction((txn) async {
      await txn.execute(
        'CREATE TABLE IF NOT EXISTS bundled_library_updates ('
        'library_item_id TEXT PRIMARY KEY, revision TEXT NOT NULL)',
      );
      var changed = 0;
      for (final entry in witnesses.entries) {
        for (final row in entry.value) {
          await txn.insert(
            entry.key,
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final id in managedItemIds) {
        final installed = await txn.query(
          'bundled_library_updates',
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
        if (installed.isNotEmpty && installed.single['revision'] == revision)
          continue;
        final existing = await txn.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [id],
        );
        // A new bundle is not permission to restore a book the user removed.
        if (existing.isNotEmpty && existing.single['deleted_at'] != null)
          continue;
        final item = Map<String, Object?>.of(items[id]!);
        final cover = item['cover_path']?.toString() ?? '';
        if (resourceRoot != null &&
            cover.startsWith('Research/ManagedBundles/')) {
          item['cover_path'] = p.join(resourceRoot, cover);
        }
        if (existing.isNotEmpty) {
          for (final field in ['last_opened', 'date_added', 'created_at']) {
            item[field] = existing.single[field];
          }
          // UPDATE, never REPLACE: replacing the parent can cascade into notes.
          await txn.update(
            'library_items',
            item,
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.insert('library_items', item);
        }
        // Child-first removal preserves foreign-key correctness.
        for (final table in [
          'library_document_assets',
          'library_document_asset_sets',
          'library_document_navigation',
          'library_block_source_map',
          'library_document_blocks',
          'library_document_sections',
          'library_document_conversion',
          'library_research_index_conversion',
          'library_links',
          'library_navigation_items',
          'library_text_blocks',
          'elibrary_ref_index',
        ]) {
          await txn.delete(
            table,
            where: 'library_item_id = ?',
            whereArgs: [id],
          );
        }
        for (final blob in blobs.values) {
          await txn.insert(
            'library_asset_blobs',
            blob,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        for (final table in contentTables) {
          for (final sourceRow in rowsByItem[id]![table]!) {
            final row = Map<String, Object?>.of(sourceRow);
            // Integer IDs are local allocation details, not portable IDs.
            if (table == 'library_text_blocks' || table == 'elibrary_ref_index')
              row.remove('id');
            await txn.insert(table, row);
          }
        }
        await txn.insert('bundled_library_updates', {
          'library_item_id': id,
          'revision': revision,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        changed++;
      }
      return changed;
    });
  }
}
