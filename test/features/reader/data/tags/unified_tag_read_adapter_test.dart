import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/user_v2_schema.dart';
import 'package:studybible2/features/reader/data/tags/unified_tag_models.dart';
import 'package:studybible2/features/reader/data/tags/unified_tag_read_adapter.dart';

Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('unified_tag_adapter_');
  final dbPath = p.join(tempDir.path, 'user.db');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, version) async {
      await UserV2Schema.ensure(db, deviceId: 'test-device');
      await db.execute('ALTER TABLE hash_tags ADD COLUMN note_text TEXT');
    },
  );
  return (db: db, dir: tempDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reads legacy hash, legacy dollar, normalized, and unknown items',
    () async {
      final testDb = await _openTestDatabase();
      final db = testDb.db;
      final tempDir = testDb.dir;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(p.join(tempDir.path, 'user.db'));
        await tempDir.delete(recursive: true);
      });

      await db.insert('app_settings', {
        'key': 'tags.default.hash',
        'value': '#Grace',
      });
      await db.insert('app_settings', {
        'key': 'tags.default.dollar',
        'value': r'$Chain',
      });

      await db.insert('hash_tags', {
        'user_id': 1,
        'tag': '#Grace',
        'verse_ref': '43:3:16',
        'book_number': 43,
        'chapter_number': 3,
        'verse_number': 16,
        'token_number': 4,
        'note_text': 'Legacy quick note',
        'sort_order': 2,
        'presentation_slide_number': 7,
        'presentation_slide_region': 'left',
        'created_at': 100,
        'created_at_utc': '2026-01-01T00:00:00Z',
        'updated_at_utc': '2026-01-01T00:00:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-a',
        'revision': 2,
        'sync_status': 'synced',
        'last_synced_at': '2026-01-01T00:00:02Z',
        'change_id': 'chg-1',
      });
      await db.insert('hash_tags', {
        'user_id': 1,
        'tag': '#Grace',
        'verse_ref': 'mystery:1',
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'note_text': null,
        'sort_order': 4,
        'created_at': 120,
        'created_at_utc': '2026-01-01T00:02:00Z',
        'updated_at_utc': '2026-01-01T00:02:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-a',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('hash_tags', {
        'user_id': 1,
        'tag': '#Grace',
        'verse_ref': '2:2:35-37',
        'book_number': 2,
        'chapter_number': 2,
        'verse_number': 35,
        'token_number': null,
        'note_text': null,
        'sort_order': 5,
        'created_at': 130,
        'created_at_utc': '2026-01-01T00:03:00Z',
        'updated_at_utc': '2026-01-01T00:03:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-a',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });

      await db.insert('dollar_tags', {
        'user_id': 1,
        'tag': r'$Chain',
        'verse_ref': 'note:999',
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'content_html': '<p>Legacy note slide <img src="images/chart.png"></p>',
        'note_format_json':
            '{"kind":"elibrary_note","source_title":"Legacy Work","source_location":"GC 623.2","source_reference_text":"GC 623.2","source_relative_path":"Media/Legacy/chart.png","source_page_number":623,"source_paragraph_number":2,"source_paragraph":"Legacy paragraph","excerpt":"Legacy excerpt","stable_ref":"stable-1"}',
        'source_author': '',
        'source_work_title': '',
        'source_title_acronym': '',
        'source_chapter_title': '',
        'source_chapter_number': '',
        'source_page_number': '',
        'source_paragraph_number': '',
        'source_year': '',
        'study_order': 1,
        'created_at': 200,
        'created_at_utc': '2026-01-01T01:00:00Z',
        'updated_at_utc': '2026-01-01T01:00:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-b',
        'revision': 3,
        'sync_status': 'synced',
        'last_synced_at': '2026-01-01T01:00:02Z',
        'change_id': 'chg-2',
      });

      await db.insert('tag_groups', {
        'id': 'group-1',
        'parent_group_id': null,
        'tag_kind': 'hash',
        'name': '#Unified',
        'description': null,
        'sort_order': 1,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:00Z',
        'created_at': '2026-01-01T02:00:00Z',
        'updated_at': '2026-01-01T02:00:00Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('tag_items', {
        'id': 'item-1',
        'tag_group_id': 'group-1',
        'tag_kind': 'hash',
        'book_id': 43,
        'chapter': 3,
        'verse_start': 16,
        'verse_end': 17,
        'reference_code': 'John 3:16-17',
        'presentation_slide_number': 2,
        'presentation_slide_region': 'right',
        'note_text': 'Unified range note',
        'note_format_json': null,
        'sort_order': 1,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:01Z',
        'created_at': '2026-01-01T02:00:01Z',
        'updated_at': '2026-01-01T02:00:01Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('tag_items', {
        'id': 'item-2',
        'tag_group_id': 'group-1',
        'tag_kind': 'hash',
        'book_id': 0,
        'chapter': 0,
        'verse_start': 0,
        'verse_end': 0,
        'reference_code': null,
        'presentation_slide_number': null,
        'presentation_slide_region': null,
        'note_text': 'Unified note',
        'note_format_json': null,
        'sort_order': 2,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:02Z',
        'created_at': '2026-01-01T02:00:02Z',
        'updated_at': '2026-01-01T02:00:02Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('tag_items', {
        'id': 'item-3',
        'tag_group_id': 'group-1',
        'tag_kind': 'hash',
        'book_id': 0,
        'chapter': 0,
        'verse_start': 0,
        'verse_end': 0,
        'reference_code': null,
        'presentation_slide_number': null,
        'presentation_slide_region': null,
        'note_text': null,
        'note_format_json': null,
        'sort_order': 3,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:03Z',
        'created_at': '2026-01-01T02:00:03Z',
        'updated_at': '2026-01-01T02:00:03Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('tag_items', {
        'id': 'item-4',
        'tag_group_id': 'group-1',
        'tag_kind': 'hash',
        'book_id': 6,
        'chapter': 2,
        'verse_start': 2,
        'verse_end': 2,
        'reference_code': null,
        'presentation_slide_number': null,
        'presentation_slide_region': null,
        'note_text': null,
        'note_format_json': null,
        'sort_order': 4,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:04Z',
        'created_at': '2026-01-01T02:00:04Z',
        'updated_at': '2026-01-01T02:00:04Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      await db.insert('tag_item_media', {
        'id': 'media-1',
        'tag_item_id': 'item-1',
        'media_type': 'image',
        'relative_path': 'Media/Unified/chart.png',
        'caption': 'Chart',
        'file_hash': 'hash-1',
        'file_size': 1234,
        'sort_order': 1,
        'source_device_name': null,
        'legacy_group_id': null,
        'legacy_item_id': null,
        'legacy_import_package_id': null,
        'imported_at': '2026-01-01T02:00:04Z',
        'created_at': '2026-01-01T02:00:04Z',
        'updated_at': '2026-01-01T02:00:04Z',
        'deleted_at': null,
        'device_id': 'device-c',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });

      final adapter = UnifiedTagReadAdapter(
        databaseProvider: () async => db,
        bookNamesProvider: () async => {2: 'Exodus', 6: 'Joshua', 43: 'John'},
      );
      final snapshot = await adapter.loadSnapshot();
      final chains = snapshot.chains;

      expect(chains, isNotEmpty);

      final legacyHash = chains.firstWhere((chain) => chain.name == '#Grace');
      expect(legacyHash.storageKind, UnifiedTagStorageKind.hash);
      expect(legacyHash.isDefault, isTrue);
      expect(legacyHash.items.length, 3);
      expect(legacyHash.items.first.sortOrder, 2);
      expect(legacyHash.items.first.itemType, UnifiedTagItemType.bibleVerse);
      expect(legacyHash.items.first.displayTitle, 'John 3:16');
      expect(legacyHash.items.last.displayTitle, 'Exodus 2:35-37');
      expect(legacyHash.items.first.layoutHint?.presentationSlideNumber, 7);
      expect(legacyHash.items.first.media, isEmpty);
      expect(legacyHash.items[1].itemType, UnifiedTagItemType.unknownLegacy);
      expect(legacyHash.items.last.itemType, UnifiedTagItemType.bibleRange);

      final legacyDollar = chains.firstWhere(
        (chain) => chain.name == r'$Chain',
      );
      expect(legacyDollar.storageKind, UnifiedTagStorageKind.dollar);
      expect(legacyDollar.isDefault, isTrue);
      expect(legacyDollar.items.length, 1);
      expect(
        legacyDollar.items.first.itemType,
        UnifiedTagItemType.eLibraryRange,
      );
      expect(legacyDollar.items.first.elibraryAnchor, isNotNull);
      expect(legacyDollar.items.first.media, isNotEmpty);

      final unified = chains.firstWhere((chain) => chain.name == '#Unified');
      expect(unified.storageKind, UnifiedTagStorageKind.unified);
      expect(unified.items.length, 4);
      expect(unified.items.first.itemType, UnifiedTagItemType.bibleRange);
      expect(unified.items.first.displayTitle, 'John 3:16-17');
      expect(unified.items.last.displayTitle, 'Joshua 2:2');
      expect(
        unified.items.first.media.single.relativePath,
        'Media/Unified/chart.png',
      );
      expect(unified.items[1].itemType, UnifiedTagItemType.note);
      expect(unified.items[2].itemType, UnifiedTagItemType.unknownLegacy);
      expect(unified.items.last.itemType, UnifiedTagItemType.bibleVerse);
      expect(unified.items.first.bibleAnchor?.verseEnd, 17);
      expect(unified.items.first.layoutHint?.presentationSlideRegion, 'right');
    },
  );
}
