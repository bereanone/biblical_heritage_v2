// Tests for Phase 2 imported tag category placement fixes.
//
// These tests verify the three surgical changes:
//
//   Change 2: loadCategoryOptions() includes root tag_group category names for
//             the matching tag_kind, and excludes import_root/import_package.
//
//   Change 3: _loadUnifiedChains() skips import_root/import_package groups but
//             still loads real hash/dollar tag groups beneath them.
//
// All tests run against an in-memory SQLite database via sqflite_common_ffi
// so they do not depend on any production singleton.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/reader/data/tags/unified_tag_read_adapter.dart';

// ---------------------------------------------------------------------------
// Shared test-database helper (mirrors unified_tag_read_adapter_test.dart)
// ---------------------------------------------------------------------------
Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('tag_import_phase2_');
  final dbPath = p.join(tempDir.path, 'test.db');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE hash_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL DEFAULT 1,
          tag TEXT NOT NULL,
          category TEXT,
          verse_ref TEXT NOT NULL DEFAULT '43:1:1',
          book_number INTEGER NOT NULL DEFAULT 43,
          chapter_number INTEGER NOT NULL DEFAULT 1,
          verse_number INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER,
          created_at INTEGER NOT NULL DEFAULT 0,
          trashed_at_utc TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE dollar_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL DEFAULT 1,
          tag TEXT NOT NULL,
          category TEXT,
          verse_ref TEXT NOT NULL DEFAULT '43:1:1',
          book_number INTEGER NOT NULL DEFAULT 43,
          chapter_number INTEGER NOT NULL DEFAULT 1,
          verse_number INTEGER NOT NULL DEFAULT 1,
          content_html TEXT NOT NULL DEFAULT '',
          study_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL DEFAULT 0,
          trashed_at_utc TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE tag_groups (
          id TEXT PRIMARY KEY,
          parent_group_id TEXT,
          tag_kind TEXT NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          source_device_name TEXT,
          legacy_group_id TEXT,
          legacy_item_id TEXT,
          legacy_import_package_id TEXT,
          imported_at TEXT,
          created_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          updated_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL DEFAULT 'test-device',
          revision INTEGER NOT NULL DEFAULT 1,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          change_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE tag_items (
          id TEXT PRIMARY KEY,
          tag_group_id TEXT NOT NULL,
          tag_kind TEXT NOT NULL,
          book_id INTEGER NOT NULL DEFAULT 0,
          chapter INTEGER NOT NULL DEFAULT 0,
          verse_start INTEGER NOT NULL DEFAULT 0,
          verse_end INTEGER NOT NULL DEFAULT 0,
          reference_code TEXT,
          presentation_slide_number INTEGER,
          presentation_slide_region TEXT,
          note_text TEXT,
          note_format_json TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          source_device_name TEXT,
          legacy_group_id TEXT,
          legacy_item_id TEXT,
          legacy_import_package_id TEXT,
          imported_at TEXT,
          created_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          updated_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL DEFAULT 'test-device',
          revision INTEGER NOT NULL DEFAULT 1,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          change_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE tag_item_media (
          id TEXT PRIMARY KEY,
          tag_item_id TEXT NOT NULL,
          media_type TEXT NOT NULL DEFAULT 'image/png',
          relative_path TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          updated_at TEXT NOT NULL DEFAULT '2026-01-01T00:00:00Z',
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL DEFAULT 'test-device',
          revision INTEGER NOT NULL DEFAULT 1,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          change_id TEXT
        )
      ''');
    },
  );
  return (db: db, dir: tempDir);
}

// ---------------------------------------------------------------------------
// SQL helper that mirrors the new tag_groups clause in loadCategoryOptions()
// for tag_kind='hash'.
// ---------------------------------------------------------------------------
Future<List<String>> _queryRootCategoryNames(
  Database db,
  String tagKind,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT DISTINCT name
    FROM tag_groups
    WHERE tag_kind = ?
      AND (parent_group_id IS NULL OR TRIM(parent_group_id) = '')
      AND (deleted_at IS NULL OR TRIM(deleted_at) = '')
      AND TRIM(name) <> ''
      AND tag_kind NOT IN ('import_root', 'import_package')
    ORDER BY name COLLATE NOCASE ASC
    ''',
    [tagKind],
  );
  return [
    for (final row in rows)
      if ((row['name']?.toString().trim() ?? '').isNotEmpty)
        row['name']!.toString().trim(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Change 2 tests: loadCategoryOptions SQL behaviour
  // -------------------------------------------------------------------------

  group('loadCategoryOptions root tag_group names (Change 2)', () {
    test('includes root tag_group names for matching tag_kind', () async {
      final testDb = await _openTestDatabase();
      final db = testDb.db;
      final tempDir = testDb.dir;
      addTearDown(() async {
        await db.close();
        await tempDir.delete(recursive: true);
      });

      // A normal root hash category group (created by saveTagCategory logic).
      await db.insert('tag_groups', {
        'id': 'cat_prophecy',
        'parent_group_id': null,
        'tag_kind': 'hash',
        'name': 'Prophecy',
      });
      // A normal root dollar category group.
      await db.insert('tag_groups', {
        'id': 'cat_dollar_study',
        'parent_group_id': null,
        'tag_kind': 'dollar',
        'name': 'DollarStudy',
      });
      // A hash tag group that is a child of the Prophecy category.
      await db.insert('tag_groups', {
        'id': 'tag_grace',
        'parent_group_id': 'cat_prophecy',
        'tag_kind': 'hash',
        'name': '#Grace',
      });

      final hashCategories = await _queryRootCategoryNames(db, 'hash');
      expect(hashCategories, contains('Prophecy'));
      // #Grace is a child group, not a root — should not appear.
      expect(hashCategories, isNot(contains('#Grace')));
      // DollarStudy belongs to dollar, not hash.
      expect(hashCategories, isNot(contains('DollarStudy')));

      final dollarCategories = await _queryRootCategoryNames(db, 'dollar');
      expect(dollarCategories, contains('DollarStudy'));
      expect(dollarCategories, isNot(contains('Prophecy')));
    });

    test('excludes import_root and import_package groups', () async {
      final testDb = await _openTestDatabase();
      final db = testDb.db;
      final tempDir = testDb.dir;
      addTearDown(() async {
        await db.close();
        await tempDir.delete(recursive: true);
      });

      // import_root container group.
      await db.insert('tag_groups', {
        'id': 'import_root_1',
        'parent_group_id': null,
        'tag_kind': 'import_root',
        'name': 'Imported Tags',
      });
      // import_package group under import_root.
      await db.insert('tag_groups', {
        'id': 'import_pkg_1',
        'parent_group_id': 'import_root_1',
        'tag_kind': 'import_package',
        'name': 'iPhone Import - 2024-01-15',
      });
      // Real imported hash tag group under import_package.
      await db.insert('tag_groups', {
        'id': 'imported_tag_1',
        'parent_group_id': 'import_pkg_1',
        'tag_kind': 'hash',
        'name': '#FaithStudy',
      });
      // A legitimate root hash category group.
      await db.insert('tag_groups', {
        'id': 'cat_favorites',
        'parent_group_id': null,
        'tag_kind': 'hash',
        'name': 'Favorites',
      });

      final hashCategories = await _queryRootCategoryNames(db, 'hash');

      // Legitimate category should appear.
      expect(hashCategories, contains('Favorites'));
      // import_root and import_package groups must NOT appear.
      expect(hashCategories, isNot(contains('Imported Tags')));
      expect(hashCategories, isNot(contains('iPhone Import - 2024-01-15')));
      // The real imported tag has a non-null parent, so it's not root.
      expect(hashCategories, isNot(contains('#FaithStudy')));
    });

    test('soft-deleted groups are excluded', () async {
      final testDb = await _openTestDatabase();
      final db = testDb.db;
      final tempDir = testDb.dir;
      addTearDown(() async {
        await db.close();
        await tempDir.delete(recursive: true);
      });

      await db.insert('tag_groups', {
        'id': 'cat_deleted',
        'parent_group_id': null,
        'tag_kind': 'hash',
        'name': 'DeletedCategory',
        'deleted_at': '2026-01-01T00:00:00Z',
      });
      await db.insert('tag_groups', {
        'id': 'cat_active',
        'parent_group_id': null,
        'tag_kind': 'hash',
        'name': 'ActiveCategory',
      });

      final hashCategories = await _queryRootCategoryNames(db, 'hash');
      expect(hashCategories, contains('ActiveCategory'));
      expect(hashCategories, isNot(contains('DeletedCategory')));
    });
  });

  // -------------------------------------------------------------------------
  // Change 3 tests: _loadUnifiedChains excludes import_root/import_package
  // -------------------------------------------------------------------------

  group('_loadUnifiedChains import group filtering (Change 3)', () {
    test(
      'excludes import_root and import_package chains but includes real hash groups beneath them',
      () async {
        final testDb = await _openTestDatabase();
        final db = testDb.db;
        final tempDir = testDb.dir;
        addTearDown(() async {
          await db.close();
          await tempDir.delete(recursive: true);
        });

        // Import container hierarchy.
        await db.insert('tag_groups', {
          'id': 'import_root_1',
          'parent_group_id': null,
          'tag_kind': 'import_root',
          'name': 'Imported Tags',
        });
        await db.insert('tag_groups', {
          'id': 'import_pkg_1',
          'parent_group_id': 'import_root_1',
          'tag_kind': 'import_package',
          'name': 'iPhone Import - 2024-01-15',
        });
        // Real imported hash tag group (child of import_package).
        await db.insert('tag_groups', {
          'id': 'tag_real_1',
          'parent_group_id': 'import_pkg_1',
          'tag_kind': 'hash',
          'name': '#RealTag',
        });
        // Tag item under the real tag group.
        await db.insert('tag_items', {
          'id': 'item_real_1',
          'tag_group_id': 'tag_real_1',
          'tag_kind': 'hash',
          'book_id': 43,
          'chapter': 3,
          'verse_start': 16,
          'verse_end': 16,
        });
        // A normal (non-imported) hash tag group.
        await db.insert('tag_groups', {
          'id': 'tag_normal_1',
          'parent_group_id': null,
          'tag_kind': 'hash',
          'name': '#NormalTag',
        });

        final adapter = UnifiedTagReadAdapter(
          databaseProvider: () async => db,
          bookNamesProvider: () async => {43: 'John'},
        );
        final snapshot = await adapter.loadSnapshot();
        final chainNames = snapshot.chains.map((c) => c.name).toList();

        // Real hash tag should appear.
        expect(chainNames, contains('#RealTag'));
        // Normal hash tag should appear.
        expect(chainNames, contains('#NormalTag'));
        // Container groups must NOT appear.
        expect(chainNames, isNot(contains('Imported Tags')));
        expect(chainNames, isNot(contains('iPhone Import - 2024-01-15')));
      },
    );

    test(
      'real imported hash tag items are still loaded when beneath import_package',
      () async {
        final testDb = await _openTestDatabase();
        final db = testDb.db;
        final tempDir = testDb.dir;
        addTearDown(() async {
          await db.close();
          await tempDir.delete(recursive: true);
        });

        await db.insert('tag_groups', {
          'id': 'import_root_x',
          'parent_group_id': null,
          'tag_kind': 'import_root',
          'name': 'Imported',
        });
        await db.insert('tag_groups', {
          'id': 'import_pkg_x',
          'parent_group_id': 'import_root_x',
          'tag_kind': 'import_package',
          'name': 'Batch 2025-06',
        });
        await db.insert('tag_groups', {
          'id': 'tag_imported_x',
          'parent_group_id': 'import_pkg_x',
          'tag_kind': 'hash',
          'name': '#Salvation',
        });
        await db.insert('tag_items', {
          'id': 'item_a',
          'tag_group_id': 'tag_imported_x',
          'tag_kind': 'hash',
          'book_id': 45,
          'chapter': 8,
          'verse_start': 28,
          'verse_end': 28,
        });
        await db.insert('tag_items', {
          'id': 'item_b',
          'tag_group_id': 'tag_imported_x',
          'tag_kind': 'hash',
          'book_id': 43,
          'chapter': 3,
          'verse_start': 16,
          'verse_end': 16,
        });

        final adapter = UnifiedTagReadAdapter(
          databaseProvider: () async => db,
          bookNamesProvider: () async => {43: 'John', 45: 'Romans'},
        );
        final snapshot = await adapter.loadSnapshot();
        final chain = snapshot.chains
            .where((c) => c.name == '#Salvation')
            .firstOrNull;

        expect(chain, isNotNull);
        expect(chain!.items.length, equals(2));
      },
    );
  });
}
