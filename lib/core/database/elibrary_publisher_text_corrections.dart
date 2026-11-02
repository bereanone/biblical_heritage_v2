import 'dart:convert';
import 'lof_paragraph_correction.dart';
import 'lof_reference_correction.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Narrow, repeatable publisher corrections. Source EPUBs and stable anchors
/// remain intact; every changed content row retains its previous values.
class ELibraryPublisherTextCorrections {
  static const wor10214Before =
      '“That like as Christ was raised up fro the dead by the glory of the Father, even so we also should walk in newness of life.”';
  static const wor10214After =
      '“That like as Christ was raised up from the dead by the glory of the Father, even so we also should walk in newness of life.”';
  static const _sources = <String>{
    '887a248acb34648cc510af7a0d729964d4a3736e9698e36a71583b3a6b34b4d6',
    '49474b9b27e5fc4828aac88f07753acaf9b1930ef2efa3ea9bc5132ba9a70b83',
  };

  /// Apply the same published correction before the direct EPUB reader parses
  /// its text and markup. The original source file and its digest are retained.
  static String correctedEpubHtml({
    required String sourceHash,
    required String href,
    required String html,
  }) {
    if (!_sources.contains(sourceHash) ||
        href.replaceAll(String.fromCharCode(92), '/').toLowerCase() !=
            'oebps/content26.xhtml') {
      return html;
    }
    const before = 'data-refcode="WOR 102.14">$wor10214Before</p>';
    const after = 'data-refcode="WOR 102.14">$wor10214After</p>';
    if (before.allMatches(html).length != 1) return html;
    return html.replaceFirst(before, after);
  }

  static Future<int> apply(Database db, {String? itemId}) async {
    return db.transaction((txn) async {
      final items = await txn.query(
        'library_items',
        columns: ['id', 'file_hash'],
        where: itemId == null ? null : 'id = ?',
        whereArgs: itemId == null ? null : [itemId],
      );
      var changed = 0;
      for (final item in items) {
        if (item['file_hash'] == LofParagraphCorrection.sourceHash) {
          changed += await LofParagraphCorrection.apply(
            txn,
            item['id'] as String,
          );
          changed += await LofReferenceCorrection.apply(
            txn,
            item['id'] as String,
          );
        }
        if (!_sources.contains(item['file_hash'])) continue;
        final id = item['id'] as String;
        final rows = await txn.query(
          'library_document_blocks',
          where:
              'library_item_id = ? AND source_refcode = ? AND plain_text = ?',
          whereArgs: [id, 'WOR 102.14', wor10214Before],
        );
        for (final row in rows) {
          final formatted = row['formatted_content'] as String;
          if (!formatted.contains('raised up fro the dead')) continue;
          await txn.execute(
            '''CREATE TABLE IF NOT EXISTS library_publisher_text_repairs (
            correction_id TEXT NOT NULL, block_id TEXT NOT NULL,
            previous_row_json TEXT NOT NULL, applied_at TEXT NOT NULL,
            PRIMARY KEY(correction_id, block_id))''',
          );
          await txn.insert(
            'library_publisher_text_repairs',
            {
              'correction_id': 'wor-102-14-from-v1',
              'block_id': row['id'],
              'previous_row_json': jsonEncode(row),
              'applied_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          final correctedFormat = formatted.replaceAll(
            'raised up fro the dead',
            'raised up from the dead',
          );
          final separator = String.fromCharCode(0);
          final hash = sha256
              .convert(
                utf8.encode(
                  '${row['block_type']}$separator$wor10214After$separator$correctedFormat',
                ),
              )
              .toString();
          changed += await txn.update(
            'library_document_blocks',
            {
              'plain_text': wor10214After,
              'formatted_content': correctedFormat,
              'content_hash': hash,
            },
            where: 'id = ? AND plain_text = ?',
            whereArgs: [row['id'], wor10214Before],
          );
          // Search copies are content only. Never rewrite notes or markups.
          for (final table in ['library_text_blocks', 'elibrary_ref_index']) {
            final exists = await txn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              [table],
            );
            if (exists.isEmpty) continue;
            await txn.update(
              table,
              {'plain_text': wor10214After},
              where: 'library_item_id = ? AND plain_text = ?',
              whereArgs: [id, wor10214Before],
            );
          }
        }
      }
      return changed;
    });
  }
}
