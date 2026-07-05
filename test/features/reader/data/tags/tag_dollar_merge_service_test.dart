import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/reader/data/tags/tag_dollar_merge_service.dart';
import 'package:studybible2/features/reader/data/tags/unified_tag_models.dart';
import 'package:studybible2/features/reader/data/tags/unified_tag_read_adapter.dart';

Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('tag_dollar_merge_');
  final dbPath = p.join(tempDir.path, 'user.db');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE hash_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tag TEXT NOT NULL,
          created_at INTEGER,
          trashed_at_utc TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE dollar_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tag TEXT NOT NULL,
          category TEXT,
          verse_ref TEXT NOT NULL,
          book_number INTEGER NOT NULL,
          chapter_number INTEGER NOT NULL,
          verse_number INTEGER NOT NULL,
          token_number INTEGER,
          content_html TEXT NOT NULL,
          source_author TEXT,
          source_work_title TEXT,
          source_title_acronym TEXT,
          source_chapter_title TEXT,
          source_chapter_number TEXT,
          source_page_number TEXT,
          source_paragraph_number TEXT,
          source_year TEXT,
          study_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at_utc TEXT,
          deleted_at_utc TEXT,
          device_id TEXT,
          revision INTEGER DEFAULT 1,
          sync_status TEXT DEFAULT 'pending',
          last_synced_at TEXT,
          change_id TEXT,
          legacy_import_package_id TEXT,
          note_text TEXT,
          note_format_json TEXT,
          presentation_slide_number INTEGER,
          presentation_slide_region TEXT,
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL,
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
          book_id INTEGER NOT NULL,
          chapter INTEGER NOT NULL,
          verse_start INTEGER NOT NULL,
          verse_end INTEGER NOT NULL,
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
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL,
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
          media_type TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          caption TEXT,
          file_hash TEXT,
          file_size INTEGER,
          sort_order INTEGER NOT NULL DEFAULT 0,
          source_device_name TEXT,
          legacy_group_id TEXT,
          legacy_item_id TEXT,
          legacy_import_package_id TEXT,
          imported_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          trashed_at TEXT,
          device_id TEXT NOT NULL,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'copies legacy dollar tags into unified storage without deleting originals',
    () async {
      final testDb = await _openTestDatabase();
      final db = testDb.db;
      final tempDir = testDb.dir;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(p.join(tempDir.path, 'user.db'));
        await tempDir.delete(recursive: true);
      });

      await db.insert('hash_tags', {'tag': r'$LegacyChain', 'created_at': 50});

      await db.insert('dollar_tags', {
        'tag': r'$LegacyChain',
        'category': 'Imported Study',
        'verse_ref': '43:1:1',
        'book_number': 43,
        'chapter_number': 1,
        'verse_number': 1,
        'token_number': 12,
        'content_html': '<p><img src="images/figure.png"></p>',
        'source_author': 'Alice',
        'source_work_title': 'Legacy Notes',
        'source_title_acronym': 'LN',
        'source_chapter_title': 'Chapter One',
        'source_chapter_number': '1',
        'source_page_number': '45',
        'source_paragraph_number': '3',
        'source_year': '2026',
        'study_order': 1,
        'created_at': 100,
        'updated_at_utc': '2026-01-01T00:00:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-a',
        'revision': 2,
        'sync_status': 'synced',
        'last_synced_at': '2026-01-01T00:00:02Z',
        'change_id': 'chg-1',
        'legacy_import_package_id': 'pkg-1',
        'note_text': null,
        'note_format_json': null,
      });
      await db.insert('dollar_tags', {
        'tag': r'$LegacyChain',
        'category': 'Imported Study',
        'verse_ref': 'note:200',
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'content_html': '<p>Legacy note</p>',
        'source_author': 'Alice',
        'source_work_title': 'Legacy Notes',
        'source_title_acronym': 'LN',
        'source_chapter_title': 'Chapter Two',
        'source_chapter_number': '2',
        'source_page_number': '46',
        'source_paragraph_number': '4',
        'source_year': '2026',
        'study_order': 2,
        'created_at': 200,
        'updated_at_utc': '2026-01-01T00:01:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-a',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
        'legacy_import_package_id': 'pkg-2',
        'note_text': null,
        'note_format_json': jsonEncode({
          'kind': 'elibrary_note',
          'source_location': 'p. 46',
          'source_title': 'Legacy Notes',
          'source_title_acronym': 'LN',
          'source_reference_text': 'Legacy Notes p. 46',
        }),
      });

      final service = TagDollarMergeService(
        databaseProvider: () async => db,
        deviceIdProvider: () async => 'device-test',
      );

      expect(await service.hasLegacyDollarTags(), isTrue);

      final dryRun = await service.mergeLegacyDollarTags(dryRun: true);
      expect(dryRun.legacyChainsFound, 1);
      expect(dryRun.legacyItemsFound, 2);
      expect(dryRun.legacyMediaFound, 1);
      expect(dryRun.chainsCreated, 1);
      expect(dryRun.itemsCopied, 2);
      expect(dryRun.mediaCopied, 1);
      expect(dryRun.warnings, isNotEmpty);

      final firstMerge = await service.mergeLegacyDollarTags();
      expect(firstMerge.legacyChainsFound, 1);
      expect(firstMerge.chainsCreated, 1);
      expect(firstMerge.itemsCopied, 2);
      expect(firstMerge.mediaCopied, 1);
      expect(firstMerge.reusedMappings, 0);

      final importedGroupRows = await db.query(
        'tag_groups',
        where: 'legacy_group_id = ?',
        whereArgs: [r'dollar_tags|$LegacyChain'],
      );
      expect(importedGroupRows, hasLength(1));
      expect(
        importedGroupRows.single['name'].toString(),
        startsWith(r'Imported $:'),
      );

      final importedGroupId = importedGroupRows.single['id'].toString();
      final importedItems = await db.query(
        'tag_items',
        where: 'tag_group_id = ?',
        whereArgs: [importedGroupId],
        orderBy: 'sort_order ASC, created_at ASC, id ASC',
      );
      expect(importedItems, hasLength(2));
      expect(importedItems.first['legacy_item_id'].toString(), '1');
      expect(importedItems.last['legacy_item_id'].toString(), '2');
      expect(
        importedItems.first['legacy_group_id'].toString(),
        r'dollar_tags|$LegacyChain',
      );
      expect(
        jsonDecode(importedItems.first['note_format_json'].toString()),
        isA<Map<String, dynamic>>(),
      );
      expect(
        (jsonDecode(importedItems.first['note_format_json'].toString())
            as Map<String, dynamic>)['legacy_item_type'],
        'image',
      );
      expect(
        (jsonDecode(importedItems.last['note_format_json'].toString())
            as Map<String, dynamic>)['legacy_item_type'],
        'eLibraryRange',
      );

      final mediaRows = await db.query(
        'tag_item_media',
        where: 'legacy_group_id = ?',
        whereArgs: [r'dollar_tags|$LegacyChain'],
      );
      expect(mediaRows, hasLength(1));
      expect(mediaRows.single['relative_path'].toString(), 'images/figure.png');

      final secondMerge = await service.mergeLegacyDollarTags();
      expect(secondMerge.chainsCreated, 0);
      expect(secondMerge.itemsCopied, 0);
      expect(secondMerge.mediaCopied, 0);
      expect(secondMerge.reusedMappings, greaterThan(0));

      final dollarCountAfterRows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM dollar_tags',
      );
      final dollarCountAfter = (dollarCountAfterRows.first['cnt'] as num)
          .toInt();
      expect(dollarCountAfter, 2);

      final adapter = UnifiedTagReadAdapter(
        databaseProvider: () async => db,
        bookNamesProvider: () async => {
          43: 'John',
          2: 'Exodus',
          6: 'Joshua',
        },
      );
      final snapshot = await adapter.loadSnapshot();
      final importedChain = snapshot.chains.firstWhere(
        (chain) => chain.legacyGroupId == r'dollar_tags|$LegacyChain',
      );
      expect(importedChain.storageKind, UnifiedTagStorageKind.unified);
      expect(importedChain.items, hasLength(2));
      expect(importedChain.items.first.media, hasLength(1));
      expect(
        importedChain.items.last.itemType,
        UnifiedTagItemType.eLibraryRange,
      );
    },
  );
}
