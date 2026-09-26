import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An explicit, source-scoped reading choice. Titles and citation prefixes are
/// never identities here. Older copies, their content and user data stay intact.
class LibraryReadingCopyReview {
  const LibraryReadingCopyReview({
    required this.itemId,
    required this.fingerprint,
    required this.preferredItemId,
    required this.preferredFingerprint,
    required this.label,
    required this.reason,
  });

  final String itemId;
  final String fingerprint;
  final String preferredItemId;
  final String preferredFingerprint;
  final String label;
  final String reason;

  bool get isAlternate => itemId != preferredItemId;

  static Future<String?> sourceFingerprint(
    DatabaseExecutor db,
    String itemId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT li.deleted_at, li.index_status, dc.source_hash, dc.status
      FROM library_items li
      LEFT JOIN library_document_conversion dc ON dc.library_item_id = li.id
      WHERE li.id = ?
    ''',
      [itemId],
    );
    if (rows.isEmpty || rows.single['deleted_at'] != null) return null;
    final row = rows.single;
    if (row['index_status'] == 'needs_attention') return null;
    final sourceHash = row['source_hash']?.toString() ?? '';
    if (row['status'] == 'complete' && sourceHash.isNotEmpty) {
      final blocks = await db.rawQuery(
        'SELECT 1 FROM library_document_blocks WHERE library_item_id = ? LIMIT 1',
        [itemId],
      );
      return blocks.isEmpty ? null : 'canonical-sha256:$sourceHash';
    }
    // A failed/in-progress replacement must not retain an earlier approval.
    if (row['status'] != null) return null;
    final blocks = await db.rawQuery(
      '''
      SELECT epub_href, paragraph_index, plain_text
      FROM library_text_blocks WHERE library_item_id = ?
      ORDER BY id
    ''',
      [itemId],
    );
    if (blocks.isEmpty) return null;
    return 'legacy-text-sha256:${sha256.convert(utf8.encode(jsonEncode(blocks)))}';
  }

  /// Only current, readable, reviewed revisions can suppress an alternative.
  /// A changed source or missing preferred copy makes the originals visible.
  static Future<Map<String, LibraryReadingCopyReview>> loadActive(
    DatabaseExecutor db,
  ) async {
    final tables = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='library_reading_copy_reviews'",
    );
    if (tables.isEmpty) return const {};
    final rows = await db.rawQuery('''
      SELECT r.* FROM library_reading_copy_reviews r
      WHERE r.id = (
        SELECT MAX(latest.id) FROM library_reading_copy_reviews latest
        WHERE latest.library_item_id = r.library_item_id
      )
    ''');
    final fingerprints = <String, String?>{};
    for (final row in rows) {
      for (final key in ['library_item_id', 'preferred_item_id']) {
        final id = row[key] as String;
        if (!fingerprints.containsKey(id)) {
          fingerprints[id] = await sourceFingerprint(db, id);
        }
      }
    }
    final valid = <String, LibraryReadingCopyReview>{};
    for (final row in rows) {
      final id = row['library_item_id'] as String;
      final preferred = row['preferred_item_id'] as String;
      if (fingerprints[id] != row['source_fingerprint'] ||
          fingerprints[preferred] != row['preferred_fingerprint']) {
        continue;
      }
      valid[id] = LibraryReadingCopyReview(
        itemId: id,
        fingerprint: row['source_fingerprint'] as String,
        preferredItemId: preferred,
        preferredFingerprint: row['preferred_fingerprint'] as String,
        label: row['edition_label'] as String,
        reason: row['review_note'] as String,
      );
    }
    // A preferred copy must also have its own current approval. This prevents
    // old choices forming chains when the user later selects another revision.
    return Map.fromEntries(
      valid.entries.where((entry) {
        final preferred = valid[entry.value.preferredItemId];
        return preferred != null && !preferred.isAlternate;
      }),
    );
  }

  /// Append a review as one transaction; never rewrite or retire source rows.
  static Future<void> record(
    Database db,
    List<LibraryReadingCopyReview> reviews,
  ) async {
    if (reviews.isEmpty) throw ArgumentError('A review must contain a copy.');
    final preferredIds = reviews.map((r) => r.preferredItemId).toSet();
    final ids = reviews.map((r) => r.itemId).toSet();
    if (preferredIds.length != 1 ||
        ids.length != reviews.length ||
        !ids.contains(preferredIds.single)) {
      throw ArgumentError(
        'Review one preferred copy and its explicit alternatives.',
      );
    }
    await db.transaction((txn) async {
      final preferredFingerprint = await sourceFingerprint(
        txn,
        preferredIds.single,
      );
      for (final review in reviews) {
        final fingerprint = await sourceFingerprint(txn, review.itemId);
        if (fingerprint == null ||
            fingerprint != review.fingerprint ||
            preferredFingerprint != review.preferredFingerprint ||
            review.label.trim().isEmpty ||
            review.reason.trim().isEmpty) {
          throw StateError(
            'Reading-copy review no longer matches ${review.itemId}.',
          );
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (final review in reviews) {
        await txn.insert('library_reading_copy_reviews', {
          'library_item_id': review.itemId,
          'source_fingerprint': review.fingerprint,
          'preferred_item_id': review.preferredItemId,
          'preferred_fingerprint': review.preferredFingerprint,
          'edition_label': review.label,
          'review_note': review.reason,
          'reviewed_at': now,
        });
      }
    });
  }
}
