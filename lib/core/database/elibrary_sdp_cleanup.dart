import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String kBogusSdpCleanupMigrationKey =
    'cleanup_bogus_sdp_catalog_item_20260703';

class ELibraryBogusSdpCleanupReport {
  const ELibraryBogusSdpCleanupReport({
    required this.alreadyApplied,
    required this.matchedItemId,
    required this.matchedTitle,
    required this.matchedAuthor,
    required this.matchedCollectionName,
    required this.removed,
    required this.navigationRowsDeleted,
    required this.textBlockRowsDeleted,
    required this.refIndexRowsDeleted,
    required this.linkRowsDeleted,
    required this.contributorRowsDeleted,
    required this.markupRowsDeleted,
    required this.message,
  });

  final bool alreadyApplied;
  final String? matchedItemId;
  final String? matchedTitle;
  final String? matchedAuthor;
  final String? matchedCollectionName;
  final bool removed;
  final int navigationRowsDeleted;
  final int textBlockRowsDeleted;
  final int refIndexRowsDeleted;
  final int linkRowsDeleted;
  final int contributorRowsDeleted;
  final int markupRowsDeleted;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'already_applied': alreadyApplied,
      'matched_item_id': matchedItemId,
      'matched_title': matchedTitle,
      'matched_author': matchedAuthor,
      'matched_collection_name': matchedCollectionName,
      'removed': removed,
      'navigation_rows_deleted': navigationRowsDeleted,
      'text_block_rows_deleted': textBlockRowsDeleted,
      'ref_index_rows_deleted': refIndexRowsDeleted,
      'link_rows_deleted': linkRowsDeleted,
      'contributor_rows_deleted': contributorRowsDeleted,
      'markup_rows_deleted': markupRowsDeleted,
      'message': message,
    };
  }
}

class ELibraryBogusSdpCleanupService {
  ELibraryBogusSdpCleanupService._();

  static final ELibraryBogusSdpCleanupService instance =
      ELibraryBogusSdpCleanupService._();

  Future<ELibraryBogusSdpCleanupReport> run(
    Database db, {
    void Function(String message)? log,
  }) async {
    final alreadyApplied = await _cleanupAlreadyApplied(db);
    if (alreadyApplied) {
      return const ELibraryBogusSdpCleanupReport(
        alreadyApplied: true,
        matchedItemId: null,
        matchedTitle: null,
        matchedAuthor: null,
        matchedCollectionName: null,
        removed: false,
        navigationRowsDeleted: 0,
        textBlockRowsDeleted: 0,
        refIndexRowsDeleted: 0,
        linkRowsDeleted: 0,
        contributorRowsDeleted: 0,
        markupRowsDeleted: 0,
        message: 'Bogus SDP cleanup migration already applied.',
      );
    }

    final candidate = await _findCandidate(db);
    if (candidate == null) {
      final report = const ELibraryBogusSdpCleanupReport(
        alreadyApplied: false,
        matchedItemId: null,
        matchedTitle: null,
        matchedAuthor: null,
        matchedCollectionName: null,
        removed: false,
        navigationRowsDeleted: 0,
        textBlockRowsDeleted: 0,
        refIndexRowsDeleted: 0,
        linkRowsDeleted: 0,
        contributorRowsDeleted: 0,
        markupRowsDeleted: 0,
        message: 'No matching bogus SDP catalog item was found.',
      );
      await _recordMigration(db, report);
      log?.call(report.message);
      return report;
    }

    final counts = await _countDependentRows(db, candidate.id);
    await db.transaction((txn) async {
      await txn.delete(
        'library_navigation_items',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'library_links',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'library_item_contributors',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'elibrary_markups',
        where: 'library_item_id = ?',
        whereArgs: [candidate.id],
      );
      await txn.delete(
        'library_items',
        where: 'id = ?',
        whereArgs: [candidate.id],
      );
      await _recordMigration(
        txn,
        ELibraryBogusSdpCleanupReport(
          alreadyApplied: false,
          matchedItemId: candidate.id,
          matchedTitle: candidate.title,
          matchedAuthor: candidate.author,
          matchedCollectionName: candidate.collectionName,
          removed: true,
          navigationRowsDeleted: counts.navigationRows,
          textBlockRowsDeleted: counts.textBlocks,
          refIndexRowsDeleted: counts.refIndexRows,
          linkRowsDeleted: counts.linkRows,
          contributorRowsDeleted: counts.contributorLinks,
          markupRowsDeleted: counts.markups,
          message:
              'Removed bogus SDP catalog item ${candidate.id}; '
              'deleted ${counts.navigationRows} navigation rows, '
              '${counts.textBlocks} text blocks, '
              '${counts.refIndexRows} ref index rows, '
              '${counts.linkRows} link rows, '
              '${counts.contributorLinks} contributor links, '
              '${counts.markups} markups.',
        ),
      );
    });

    final report = ELibraryBogusSdpCleanupReport(
      alreadyApplied: false,
      matchedItemId: candidate.id,
      matchedTitle: candidate.title,
      matchedAuthor: candidate.author,
      matchedCollectionName: candidate.collectionName,
      removed: true,
      navigationRowsDeleted: counts.navigationRows,
      textBlockRowsDeleted: counts.textBlocks,
      refIndexRowsDeleted: counts.refIndexRows,
      linkRowsDeleted: counts.linkRows,
      contributorRowsDeleted: counts.contributorLinks,
      markupRowsDeleted: counts.markups,
      message:
          'Removed bogus SDP catalog item ${candidate.id}; '
          'deleted ${counts.navigationRows} navigation rows, '
          '${counts.textBlocks} text blocks, '
          '${counts.refIndexRows} ref index rows, '
          '${counts.linkRows} link rows, '
          '${counts.contributorLinks} contributor links, '
          '${counts.markups} markups.',
    );
    log?.call(report.message);
    return report;
  }

  Future<bool> _cleanupAlreadyApplied(DatabaseExecutor db) async {
    final rows = await db.query(
      'elibrary_schema_migrations',
      columns: const ['migration_key'],
      where: 'migration_key = ? AND status = ?',
      whereArgs: [kBogusSdpCleanupMigrationKey, 'completed'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<_BogusSdpCandidate?> _findCandidate(Database db) async {
    final rows = await db.query(
      'library_items',
      columns: const [
        'id',
        'title',
        'author',
        'collection_name',
        'source_type',
        'relative_path',
      ],
      where: '''
        deleted_at IS NULL
        AND LOWER(TRIM(COALESCE(title, ''))) = ?
        AND LOWER(TRIM(COALESCE(author, ''))) = ?
        AND LOWER(COALESCE(collection_name, '')) LIKE ?
        AND LOWER(TRIM(COALESCE(source_type, ''))) = ?
      ''',
      whereArgs: [
        'sdp',
        'uriah smith',
        '%adventist pioneer%',
        'egw_html_capture',
      ],
      orderBy: 'created_at ASC, id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = row['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return _BogusSdpCandidate(
      id: id,
      title: row['title']?.toString().trim() ?? '',
      author: row['author']?.toString().trim() ?? '',
      collectionName: row['collection_name']?.toString().trim() ?? '',
    );
  }

  Future<_BogusSdpDependentCounts> _countDependentRows(
    DatabaseExecutor db,
    String itemId,
  ) async {
    return _BogusSdpDependentCounts(
      navigationRows: await _countRows(db, 'library_navigation_items', itemId),
      textBlocks: await _countRows(db, 'library_text_blocks', itemId),
      refIndexRows: await _countRows(db, 'elibrary_ref_index', itemId),
      linkRows: await _countRows(db, 'library_links', itemId),
      contributorLinks: await _countRows(
        db,
        'library_item_contributors',
        itemId,
      ),
      markups: await _countRows(db, 'elibrary_markups', itemId),
    );
  }

  Future<int> _countRows(
    DatabaseExecutor db,
    String tableName,
    String itemId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM "$tableName" WHERE library_item_id = ?',
      [itemId],
    );
    return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<void> _recordMigration(
    DatabaseExecutor db,
    ELibraryBogusSdpCleanupReport report,
  ) async {
    final now = _utcNow();
    await db.insert('elibrary_schema_migrations', <String, Object?>{
      'migration_key': kBogusSdpCleanupMigrationKey,
      'from_version': 1,
      'to_version': 1,
      'applied_at': now,
      'status': 'completed',
      'details': jsonEncode(report.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

class _BogusSdpCandidate {
  const _BogusSdpCandidate({
    required this.id,
    required this.title,
    required this.author,
    required this.collectionName,
  });

  final String id;
  final String title;
  final String author;
  final String collectionName;
}

class _BogusSdpDependentCounts {
  const _BogusSdpDependentCounts({
    required this.navigationRows,
    required this.textBlocks,
    required this.refIndexRows,
    required this.linkRows,
    required this.contributorLinks,
    required this.markups,
  });

  final int navigationRows;
  final int textBlocks;
  final int refIndexRows;
  final int linkRows;
  final int contributorLinks;
  final int markups;
}

String _utcNow() {
  final now = DateTime.now().toUtc();
  final iso = now.toIso8601String();
  return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
}
