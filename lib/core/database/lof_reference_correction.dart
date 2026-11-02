import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lof_paragraph_correction.dart';
import 'lof_reference_data.dart';

/// Published locators attached to this exact reading edition. These are display
/// metadata: narration text, stable anchors and user annotations stay intact.
class LofReferenceCorrection {
  static const correctionId = 'lof-published-references-v1';
  static final entries = (jsonDecode(lofReferenceDataJson) as List)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList(growable: false);

  static Future<int> apply(DatabaseExecutor db, String itemId) async {
    final items = await db.query(
      'library_items',
      columns: ['file_hash'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (items.length != 1 ||
        items.single['file_hash'] != LofParagraphCorrection.sourceHash)
      return 0;
    final columns = (await db.rawQuery(
      'PRAGMA table_info(library_document_blocks)',
    )).map((row) => row['name']).toSet();
    // Some minimal scratch databases intentionally omit reference support.
    if (!columns.containsAll(['source_refcode', 'reference_context'])) return 0;
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: [itemId],
    );
    final byOrder = {for (final row in rows) row['display_order']: row};
    var changed = 0;
    for (final entry in entries) {
      final row = byOrder[entry['display_order']];
      if (row == null || row['block_type'] != 'paragraph') continue;
      final text = row['plain_text'] as String? ?? '';
      if (sha256.convert(utf8.encode(text)).toString() !=
          entry['text_sha256']) {
        continue; // A changed paragraph must be revalidated, never guessed.
      }
      final formatted = Map<String, dynamic>.from(
        jsonDecode(row['formatted_content'] as String) as Map,
      );
      final metadata = Map<String, dynamic>.from(
        formatted['metadata'] as Map? ?? {},
      );
      final existing = row['source_refcode']?.toString().trim() ?? '';
      if (existing.isNotEmpty &&
          metadata['reference_correction'] != correctionId) {
        continue; // Preserve independent or user-supplied reference metadata.
      }
      if (existing == entry['code'] &&
          row['reference_witness'] == entry['witness'] &&
          metadata['reference_correction'] == correctionId)
        continue;
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS library_publisher_text_repairs (
        correction_id TEXT NOT NULL, block_id TEXT NOT NULL,
        previous_row_json TEXT NOT NULL, applied_at TEXT NOT NULL,
        PRIMARY KEY(correction_id, block_id))''',
      );
      await db.insert(
        'library_publisher_text_repairs',
        {
          'correction_id': correctionId,
          'block_id': row['id'],
          'previous_row_json': jsonEncode(row),
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      formatted['metadata'] = {
        ...metadata,
        'reference_correction': correctionId,
        'reference_origin': 'verified_source_alignment',
        'reference_witness': entry['witness'],
        'reference_context': entry['context'],
      };
      final encoded = jsonEncode(formatted);
      final separator = String.fromCharCode(0);
      await db.update(
        'library_document_blocks',
        {
          'source_refcode': entry['code'],
          'reference_prefix': entry['prefix'],
          'reference_page': entry['page'],
          'reference_paragraph': entry['paragraph'],
          'reference_origin': 'verified_source_alignment',
          'reference_witness': entry['witness'],
          'reference_context': entry['context'],
          'formatted_content': encoded,
          'content_hash': sha256
              .convert(
                utf8.encode(
                  '${row['block_type']}$separator$text$separator$encoded',
                ),
              )
              .toString(),
        },
        where: 'id = ? AND library_item_id = ?',
        whereArgs: [row['id'], itemId],
      );
      changed++;
    }
    return changed;
  }
}
