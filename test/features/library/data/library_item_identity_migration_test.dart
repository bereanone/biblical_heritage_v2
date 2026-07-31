import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_item_identity.dart';

/// Synthetic proof of the Pioneer ID-migration repair path:
/// [migrateManagedLibraryItemId] must transactionally move every row owned
/// by a `library_item_id`/`id` from an orphaned old ID to the authoritative
/// visible ID, refuse on any collision, roll back atomically on failure,
/// and leave no orphan rows behind. All fixtures here are synthetic; no
/// production data is touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory rootDir;
  late Database db;

  const oldId = 'library_item_research_pioneer_orphan_generation';
  const newId = 'library_item_research_pioneer_a_t_jones_visible_id';

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    rootDir = await Directory.systemTemp.createTemp('library_item_migration_');
    db = await openDatabase(p.join(rootDir.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    await rootDir.delete(recursive: true);
  });

  Future<void> seedLibraryItem(
    String id, {
    String? lastOpened,
    String? epubCfi,
    String? anchorId,
    int? spineIndex,
    int? paragraphIndex,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': 'A Real Book',
      'file_name': 'book.epub',
      'relative_path': 'Pioneers/book.epub',
      'file_format': 'epub',
      'source_type': 'pioneer_epub_import',
      'last_opened': lastOpened,
      'epub_cfi': epubCfi,
      'anchor_id': anchorId,
      'spine_index': spineIndex,
      'paragraph_index': paragraphIndex,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
      'revision': 1,
      'sync_status': 'pending',
    });
  }

  /// Every table this migration is responsible for, seeded with exactly one
  /// synthetic row owned by [oldId]. Mirrors the full dependent-row set that
  /// `elibrary_sdp_cleanup.dart` treats as authoritative for a library item.
  Future<void> seedAllOwnedTables(String itemId) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': 1,
      'source_hash': 'hash',
      'status': 'complete',
    });
    await db.insert('library_document_sections', <String, Object?>{
      'id': '$itemId-section',
      'library_item_id': itemId,
      'display_order': 0,
      'title': 'Section',
      'source_href': 'ch1.html',
      'content_hash': 'hash',
    });
    await db.insert('library_document_blocks', <String, Object?>{
      'id': '$itemId-block',
      'library_item_id': itemId,
      'section_id': '$itemId-section',
      'display_order': 0,
      'block_type': 'paragraph',
      'plain_text': 'Body text.',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'hash',
    });
    await db.insert('library_block_source_map', <String, Object?>{
      'library_item_id': itemId,
      'block_id': '$itemId-block',
      'source_href': 'ch1.html',
      'legacy_block_index': 0,
      'legacy_paragraph_index': 0,
    });
    await db.insert('library_document_conversion_staging', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': 1,
      'source_hash': 'hash',
      'status': 'converting',
      'created_at': now,
    });
    await db.insert('library_document_sections_staging', <String, Object?>{
      'id': '$itemId-section-staging',
      'library_item_id': itemId,
      'display_order': 0,
      'title': 'Section',
      'source_href': 'ch1.html',
      'content_hash': 'hash',
    });
    await db.insert('library_document_blocks_staging', <String, Object?>{
      'id': '$itemId-block-staging',
      'library_item_id': itemId,
      'section_id': '$itemId-section-staging',
      'display_order': 0,
      'block_type': 'paragraph',
      'plain_text': 'Staged body text.',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'hash',
    });
    await db.insert('library_block_source_map_staging', <String, Object?>{
      'library_item_id': itemId,
      'block_id': '$itemId-block-staging',
      'source_href': 'ch1.html',
      'legacy_block_index': 0,
      'legacy_paragraph_index': 0,
    });
    await db.insert('library_navigation_items', <String, Object?>{
      'id': '$itemId-nav',
      'library_item_id': itemId,
      'label': 'Chapter 1',
      'href': 'ch1.html',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    await db.insert('library_links', <String, Object?>{
      'id': '$itemId-link',
      'library_item_id': itemId,
      'book_id': 1,
      'chapter': 1,
      'verse_start': 1,
      'verse_end': 1,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    await db.insert('library_text_blocks', <String, Object?>{
      'library_item_id': itemId,
      'epub_href': 'ch1.html',
      'paragraph_index': 0,
      'plain_text': 'Body text.',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('elibrary_ref_index', <String, Object?>{
      'library_item_id': itemId,
      'book_abbrev': 'GC',
      'href': 'ch1.html',
      'paragraph_index': 0,
      'page_number': 1,
      'paragraph_on_page': 1,
      'ref_code': 'GC 1.1',
      'stable_ref': 'GC 1.1',
      'ref_source': 'synthetic',
    });
    await db.insert('library_item_contributors', <String, Object?>{
      'library_item_id': itemId,
      'contributor_id': 'contributor-a-t-jones',
      'role': 'author',
      'created_at': now,
    });
    await db.insert('elibrary_markups', <String, Object?>{
      'library_item_id': itemId,
      'epub_href': 'canonical:$itemId-block',
      'start_block_index': 0,
      'start_char_offset': 0,
      'end_block_index': 0,
      'end_char_offset': 4,
      'ref_start': 'GC 1.1',
      'ref_end': 'GC 1.1',
      'compact_ref': 'GC 1.1',
      'selected_text_snapshot': 'Body',
      'markup_type': 'highlight',
      'color': 'yellow',
      'note_text': 'A user note that must survive migration untouched.',
      'created_at': now,
      'updated_at': now,
    });
  }

  const ownedTables = <String>[
    'library_document_conversion',
    'library_document_sections',
    'library_document_blocks',
    'library_block_source_map',
    'library_document_conversion_staging',
    'library_document_sections_staging',
    'library_document_blocks_staging',
    'library_block_source_map_staging',
    'library_navigation_items',
    'library_links',
    'library_text_blocks',
    'elibrary_ref_index',
    'library_item_contributors',
    'elibrary_markups',
  ];

  Future<int> countFor(String table, String itemId) async {
    final rows = await db.query(
      table,
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    return rows.length;
  }

  test(
    'migrates every dependent table (1-9, 16): canonical conversion, '
    'sections, blocks, source-map, all staging tables, navigation, '
    'reference-index, links, text blocks, contributors, and markups',
    () async {
      await seedLibraryItem(oldId);
      await seedAllOwnedTables(oldId);

      await migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId);

      for (final table in ownedTables) {
        expect(
          await countFor(table, oldId),
          0,
          reason: '$table must have no rows left under the orphan old ID',
        );
        expect(
          await countFor(table, newId),
          1,
          reason: '$table must own exactly one row under the new visible ID',
        );
      }

      final itemRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: <Object?>[newId],
      );
      expect(itemRows, hasLength(1));
      expect(
        await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>[oldId],
        ),
        isEmpty,
        reason: 'the old visible library_items row must not remain (no orphan)',
      );
    },
  );

  test('10/17: reading position and user-owned markup content are preserved '
      'exactly, not merely relocated', () async {
    await seedLibraryItem(
      oldId,
      lastOpened: '2026-01-02T03:04:05.000Z',
      epubCfi: 'epubcfi(/6/14!/4/2/2)',
      anchorId: 'anchor-42',
      spineIndex: 3,
      paragraphIndex: 17,
    );
    await seedAllOwnedTables(oldId);

    await migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId);

    final item = (await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[newId],
    )).single;
    expect(item['last_opened'], '2026-01-02T03:04:05.000Z');
    expect(item['epub_cfi'], 'epubcfi(/6/14!/4/2/2)');
    expect(item['anchor_id'], 'anchor-42');
    expect(item['spine_index'], 3);
    expect(item['paragraph_index'], 17);

    final markup = (await db.query(
      'elibrary_markups',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[newId],
    )).single;
    expect(
      markup['note_text'],
      'A user note that must survive migration untouched.',
    );
    expect(markup['color'], 'yellow');
  });

  test(
    '12: refuses migration when the target visible ID already has a '
    'canonical library_items row, leaving the orphan row untouched',
    () async {
      await seedLibraryItem(oldId);
      await seedLibraryItem(newId);
      await seedAllOwnedTables(oldId);

      await expectLater(
        migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId),
        throwsA(isA<StateError>()),
      );

      expect(
        await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>[oldId],
        ),
        hasLength(1),
        reason: 'refusal must not delete or alter the orphan row',
      );
      expect(await countFor('library_document_conversion', oldId), 1);
    },
  );

  test(
    '12: refuses migration when the target ID already owns rows in a '
    'dependent table even if library_items itself has no collision',
    () async {
      await seedLibraryItem(oldId);
      await seedAllOwnedTables(oldId);
      // A prior partial/manual copy already left a marker row for the
      // target ID in one dependent table without a library_items row.
      await db.insert('library_navigation_items', <String, Object?>{
        'id': '$newId-preexisting-nav',
        'library_item_id': newId,
        'label': 'Pre-existing',
        'href': 'preexisting.html',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'device_id': 'test-device',
      });

      await expectLater(
        migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId),
        throwsA(isA<StateError>()),
      );

      expect(
        (await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>[oldId],
        )),
        hasLength(1),
        reason: 'refusal must leave the orphan library_items row in place',
      );
    },
  );

  test(
    '11: transaction rolls back atomically on a late-table collision — '
    'tables migrated earlier in the sequence must not be left half-moved',
    () async {
      await seedLibraryItem(oldId);
      await seedAllOwnedTables(oldId);
      // elibrary_markups is processed last among itemOwnedTables. Force a
      // collision there so the update aborts after every earlier table in
      // the loop has already been rewritten in-transaction.
      await db.insert('elibrary_markups', <String, Object?>{
        'library_item_id': newId,
        'epub_href': 'canonical:preexisting',
        'start_block_index': 0,
        'start_char_offset': 0,
        'end_block_index': 0,
        'end_char_offset': 1,
        'selected_text_snapshot': 'X',
        'markup_type': 'highlight',
        'color': 'blue',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      await expectLater(
        migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId),
        throwsA(isA<StateError>()),
      );

      // Every table processed before the colliding one must have rolled
      // back to still own their row under the OLD id, proving the whole
      // operation is one atomic transaction rather than table-by-table.
      for (final table in ownedTables) {
        if (table == 'elibrary_markups') continue;
        expect(
          await countFor(table, oldId),
          1,
          reason: '$table must be rolled back to the old ID after failure',
        );
        expect(await countFor(table, newId), 0);
      }
      expect(
        await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>[oldId],
        ),
        hasLength(1),
        reason: 'library_items rename must also roll back',
      );
    },
  );

  test('no-op when the old ID does not exist (nothing to migrate)', () async {
    await expectLater(
      migrateManagedLibraryItemId(db: db, oldId: oldId, newId: newId),
      completes,
    );
  });

  test('no-op when old and new IDs are identical', () async {
    await seedLibraryItem(oldId);
    await migrateManagedLibraryItemId(db: db, oldId: oldId, newId: oldId);
    expect(
      await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: <Object?>[oldId],
      ),
      hasLength(1),
    );
  });
}
