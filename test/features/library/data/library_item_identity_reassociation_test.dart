import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_item_identity.dart';

/// Synthetic proof of [reassociateOrphanCanonicalGeneration]: the primitive
/// that actually fixes the production Pioneer defect, where 420 canonical
/// generations exist under IDs with no owning `library_items` row at all
/// while the visible catalog card for the same physical book has none of
/// its own. [migrateManagedLibraryItemId] cannot do this (it requires the
/// old ID to own a live row), so this is a separate, purpose-built
/// operation. All fixtures are synthetic; no production data is touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory rootDir;
  late Database db;

  const orphanId = 'library_item_pioneer_epub_import_id_0019598e_ccd0_486c';
  const visibleId =
      'library_item_pioneer_epub_import_importedpioneerepubs_a_real_pioneer_work_epub';
  const legacyId = 'library_item_research_pioneer_a_t_jones_CWCP_ATJ';

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    rootDir = await Directory.systemTemp.createTemp('orphan_reassoc_');
    db = await openDatabase(p.join(rootDir.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    await rootDir.delete(recursive: true);
  });

  Future<void> seedVisibleItem(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': 'A Real Pioneer Work',
      'file_name': 'work.epub',
      'relative_path': 'ImportedPioneerEpubs/work.epub',
      'file_format': 'epub',
      'source_type': 'pioneer_epub_import',
      'index_status': 'metadata_only',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
  }

  /// Seeds an orphaned canonical generation: dependent-table rows owned by
  /// [itemId], but deliberately NO `library_items` row for it — exactly the
  /// real production shape.
  Future<void> seedOrphanGeneration(String itemId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': 4,
      'source_hash': 'orphan-hash',
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
      'plain_text': 'Orphaned body text.',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'hash',
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
  }

  test('grafts an orphaned generation onto the visible item without touching '
      'the visible library_items row', () async {
    await seedVisibleItem(visibleId);
    await seedOrphanGeneration(orphanId);

    await reassociateOrphanCanonicalGeneration(
      db: db,
      orphanGenerationId: orphanId,
      visibleItemId: visibleId,
    );

    for (final table in const [
      'library_document_conversion',
      'library_document_sections',
      'library_document_blocks',
      'library_navigation_items',
      'elibrary_ref_index',
    ]) {
      expect(
        await db.query(
          table,
          where: 'library_item_id = ?',
          whereArgs: [orphanId],
        ),
        isEmpty,
        reason: '$table must have no rows left under the orphan ID',
      );
      expect(
        await db.query(
          table,
          where: 'library_item_id = ?',
          whereArgs: [visibleId],
        ),
        hasLength(1),
        reason: '$table must now own exactly one row for the visible item',
      );
    }

    final visibleRow = (await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [visibleId],
    )).single;
    expect(
      visibleRow['title'],
      'A Real Pioneer Work',
      reason: "the visible item's own metadata must be untouched",
    );
  });

  test('migrateManagedLibraryItemId is a true no-op on a pure orphan — proving '
      'why a separate primitive is required', () async {
    await seedVisibleItem(visibleId);
    await seedOrphanGeneration(orphanId);

    await migrateManagedLibraryItemId(
      db: db,
      oldId: orphanId,
      newId: visibleId,
    );

    expect(
      await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: [orphanId],
      ),
      hasLength(1),
      reason:
          'migrateManagedLibraryItemId must not have moved anything: the '
          'orphan owns no library_items row, so it silently no-ops',
    );
  });

  test('refuses reassociation onto a visible item that already owns a '
      'canonical generation of its own', () async {
    await seedVisibleItem(visibleId);
    await seedOrphanGeneration(orphanId);
    // The visible item is not actually empty — it already has its own
    // generation (e.g. Christ Our Righteousness, already repaired).
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': visibleId,
      'canonicalizer_version': 5,
      'source_hash': 'own-hash',
      'status': 'complete',
    });

    await expectLater(
      reassociateOrphanCanonicalGeneration(
        db: db,
        orphanGenerationId: orphanId,
        visibleItemId: visibleId,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: [orphanId],
      ),
      hasLength(1),
      reason: 'refusal must roll back — orphan data must stay in place',
    );
  });

  test('refuses reassociation when the "orphan" ID actually still owns a live '
      'library_items row', () async {
    await seedVisibleItem(visibleId);
    await seedVisibleItem(orphanId);
    await seedOrphanGeneration(orphanId);

    await expectLater(
      reassociateOrphanCanonicalGeneration(
        db: db,
        orphanGenerationId: orphanId,
        visibleItemId: visibleId,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('refuses reassociation onto a visible ID that does not exist', () async {
    await seedOrphanGeneration(orphanId);

    await expectLater(
      reassociateOrphanCanonicalGeneration(
        db: db,
        orphanGenerationId: orphanId,
        visibleItemId: visibleId,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('no-op when the orphan and visible IDs are identical', () async {
    await seedVisibleItem(visibleId);
    await expectLater(
      reassociateOrphanCanonicalGeneration(
        db: db,
        orphanGenerationId: visibleId,
        visibleItemId: visibleId,
      ),
      completes,
    );
  });

  test(
    'legacy-ID composite: reassociate then rename ends with everything '
    'under the legacy ID and nothing left at the path-based visible ID',
    () async {
      // The real production shape for the four pinned legacy IDs: the
      // orphan generation sits at the legacy ID, and a path-based visible
      // item owns nothing of its own.
      await seedVisibleItem(visibleId);
      await seedOrphanGeneration(legacyId);

      // Step 1: graft the legacy generation onto the current visible item.
      await reassociateOrphanCanonicalGeneration(
        db: db,
        orphanGenerationId: legacyId,
        visibleItemId: visibleId,
      );
      // Step 2: rename the now-fully-populated visible item to the legacy
      // ID. This only works because step 1 left legacyId completely empty
      // (both library_items and every dependent table), satisfying
      // migrateManagedLibraryItemId's own collision checks.
      await migrateManagedLibraryItemId(
        db: db,
        oldId: visibleId,
        newId: legacyId,
      );

      expect(
        await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [visibleId],
        ),
        isEmpty,
      );
      final finalRow = (await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [legacyId],
      )).single;
      expect(finalRow['title'], 'A Real Pioneer Work');

      for (final table in const [
        'library_document_conversion',
        'library_document_sections',
        'library_document_blocks',
        'library_navigation_items',
        'elibrary_ref_index',
      ]) {
        expect(
          await db.query(
            table,
            where: 'library_item_id = ?',
            whereArgs: [legacyId],
          ),
          hasLength(1),
          reason: '$table must end up owned by the legacy ID',
        );
        expect(
          await db.query(
            table,
            where: 'library_item_id = ?',
            whereArgs: [visibleId],
          ),
          isEmpty,
        );
      }
    },
  );
}
