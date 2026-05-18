import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/reader/data/tags/legacy_tag_adapter.dart';
import 'package:studybible2/features/reader/data/tags/tag_models.dart';

Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('legacy_tag_adapter_');

  final path = p.join(tempDir.path, 'user.db');
  final db = await openDatabase(
    path,
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
          user_id INTEGER NOT NULL,
          tag TEXT NOT NULL,
          category TEXT,
          verse_ref TEXT NOT NULL,
          book_number INTEGER NOT NULL,
          chapter_number INTEGER NOT NULL,
          verse_number INTEGER NOT NULL,
          token_number INTEGER,
          note_text TEXT,
          sort_order INTEGER,
          presentation_slide_number INTEGER,
          created_at INTEGER NOT NULL,
          created_at_utc TEXT,
          updated_at_utc TEXT,
          deleted_at_utc TEXT,
          device_id TEXT,
          revision INTEGER DEFAULT 1,
          sync_status TEXT DEFAULT 'pending',
          last_synced_at TEXT,
          change_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE dollar_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
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
          created_at_utc TEXT,
          updated_at_utc TEXT,
          deleted_at_utc TEXT,
          device_id TEXT,
          revision INTEGER DEFAULT 1,
          sync_status TEXT DEFAULT 'pending',
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
    'adapts legacy hash_tags and dollar_tags into canonical models',
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
      await db.insert('app_settings', {
        'key': 'tags.category.#Grace',
        'value': 'Favorites',
      });
      await db.insert('app_settings', {
        'key': r'tags.category.dollar.$Chain',
        'value': 'Study Lists',
      });

      await db.insert('hash_tags', {
        'user_id': 1,
        'tag': '#Grace',
        'category': 'Favorites',
        'verse_ref': '43:3:16',
        'book_number': 43,
        'chapter_number': 3,
        'verse_number': 16,
        'token_number': 4,
        'note_text': 'Legacy quick note',
        'sort_order': 2,
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
        'category': 'Favorites',
        'verse_ref': '43:3:17',
        'book_number': 43,
        'chapter_number': 3,
        'verse_number': 17,
        'token_number': null,
        'note_text': null,
        'sort_order': 3,
        'created_at': 110,
        'created_at_utc': '2026-01-01T00:01:00Z',
        'updated_at_utc': '2026-01-01T00:01:01Z',
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
        'category': 'Favorites',
        'verse_ref': 'note:999',
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'note_text': 'Standalone quick note',
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

      await db.insert('dollar_tags', {
        'user_id': 1,
        'tag': r'$Chain',
        'category': 'Study Lists',
        'verse_ref': '43:1:1',
        'book_number': 43,
        'chapter_number': 1,
        'verse_number': 1,
        'token_number': 12,
        'content_html': '<p>Verse content <img src="images/chart.png"></p>',
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
      await db.insert('dollar_tags', {
        'user_id': 1,
        'tag': r'$Chain',
        'category': 'Study Lists',
        'verse_ref': 'note:999',
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'content_html': '<p>Note only content</p>',
        'source_author': '',
        'source_work_title': '',
        'source_title_acronym': '',
        'source_chapter_title': '',
        'source_chapter_number': '',
        'source_page_number': '',
        'source_paragraph_number': '',
        'source_year': '',
        'study_order': 2,
        'created_at': 210,
        'created_at_utc': '2026-01-01T01:10:00Z',
        'updated_at_utc': '2026-01-01T01:10:01Z',
        'deleted_at_utc': null,
        'device_id': 'device-b',
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });

      final adapter = LegacyTagAdapter(databaseProvider: () async => db);

      final quickGroups = await adapter.loadGroups(mode: TagMode.quick);
      final quickTagGroup = quickGroups.firstWhere(
        (group) => !group.isCategoryGroup,
      );
      expect(quickTagGroup.mode, TagMode.quick);
      expect(quickTagGroup.name, '#Grace');
      expect(quickTagGroup.isDefault, isTrue);
      expect(quickTagGroup.parentGroupId, isNotNull);

      final quickItems = await adapter.loadItems(
        mode: TagMode.quick,
        groupId: quickTagGroup.id,
      );
      expect(quickItems, hasLength(3));
      expect(quickItems.first.kind, TagItemKind.verseReference);
      expect(quickItems.first.noteText, 'Legacy quick note');
      expect(quickItems.first.anchor.kind, TagAnchorKind.verseReference);
      expect(quickItems.first.anchor.bookNumber, 43);
      final quickNoteOnlyItem = quickItems.last;
      expect(quickNoteOnlyItem.kind, TagItemKind.noteOnly);
      expect(quickNoteOnlyItem.anchor.kind, TagAnchorKind.noteOnly);
      expect(quickNoteOnlyItem.noteText, 'Standalone quick note');

      final quickDefault = await adapter.loadDefaultGroup(mode: TagMode.quick);
      expect(quickDefault?.name, '#Grace');

      final studyGroups = await adapter.loadGroups(mode: TagMode.studyList);
      final studyTagGroup = studyGroups.firstWhere(
        (group) => !group.isCategoryGroup,
      );
      expect(studyTagGroup.mode, TagMode.studyList);
      expect(studyTagGroup.name, r'$Chain');
      expect(studyTagGroup.isDefault, isTrue);

      final studyItems = await adapter.loadItems(
        mode: TagMode.studyList,
        groupId: studyTagGroup.id,
      );
      expect(studyItems, hasLength(2));
      expect(studyItems.first.sortOrder, 1);
      expect(studyItems.first.kind, TagItemKind.verseReference);
      expect(studyItems.first.noteText, contains('Verse content'));

      final noteOnlyItem = studyItems.last;
      expect(noteOnlyItem.kind, TagItemKind.noteOnly);
      expect(noteOnlyItem.anchor.kind, TagAnchorKind.noteOnly);

      final media = await adapter.loadMedia(
        mode: TagMode.studyList,
        itemId: studyItems.first.id,
      );
      expect(media, hasLength(1));
      expect(media.single.relativePath, 'images/chart.png');
      expect(media.single.mediaType, 'image');
    },
  );
}
