import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

Future<void> _clearUserDatabase(Directory documentsDir) async {
  await UserDatabase.instance.close();
  final dbPath = p.join(documentsDir.path, 'BiblicalHeritage', 'v2', 'user.db');
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$dbPath$suffix');
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<Database> _openUserDatabase() async {
  return UserDatabase.instance.database;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('tag_global_support_');
    documentsDir = await Directory.systemTemp.createTemp(
      'tag_global_documents_',
    );
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
  });

  setUp(() async {
    await _clearUserDatabase(documentsDir);
  });

  tearDownAll(() async {
    await _clearUserDatabase(documentsDir);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  test('summary identity is tag-only across categories', () async {
    final repo = HashTagRepository();
    final db = await _openUserDatabase();
    await repo.ensureSchema();

    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryA',
      'verse_ref': '43:1:1',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 1,
      'created_at': 1,
    });
    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryB',
      'verse_ref': '43:1:2',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 2,
      'created_at': 2,
    });

    final summaries = await repo.loadSummaries();
    expect(summaries.where((summary) => summary.tag == '#Faith'), hasLength(1));
    expect(summaries.firstWhere((summary) => summary.tag == '#Faith').count, 2);
  });

  test('rename blocks when the destination tag already exists', () async {
    final repo = HashTagRepository();
    final db = await _openUserDatabase();
    await repo.ensureSchema();

    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryA',
      'verse_ref': '43:1:1',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 1,
      'created_at': 1,
    });
    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Hope',
      'category': 'CategoryB',
      'verse_ref': '43:1:2',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 2,
      'created_at': 2,
    });

    final count = await repo.renameTag(
      oldTag: '#Hope',
      newTag: '#Faith',
      category: 'CategoryB',
      categoryKnown: true,
    );

    expect(count, 0);
    final faithRows = await db.query(
      'hash_tags',
      where: 'tag = ?',
      whereArgs: ['#Faith'],
    );
    expect(faithRows, hasLength(1));
    final hopeRows = await db.query(
      'hash_tags',
      where: 'tag = ?',
      whereArgs: ['#Hope'],
    );
    expect(hopeRows, hasLength(1));
  });

  test('temporary import names are suffixed predictably', () {
    expect(buildTemporaryImportTagName('#Faith'), '#Faith-import');
    expect(buildTemporaryImportTagName('#Faith-import'), '#Faith-import');
    expect(
      buildTemporaryImportTagName('#Faith', suffixIndex: 2),
      '#Faith-import-2',
    );
  });

  test(
    'duplicate imports create import-suffixed tags and keep cards attached',
    () async {
      final repo = HashTagRepository();
      await repo.ensureSchema();

      const text = '''
#Faith (1 item)

John 3:16
For God so loved the world that he gave his only begotten Son.
''';

      final first = await repo.importSharedListFromText(
        text,
        targetCategory: 'Study',
      );
      final second = await repo.importSharedListFromText(
        text,
        targetCategory: 'Study',
      );
      final third = await repo.importSharedListFromText(
        text,
        targetCategory: 'Study',
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(third, isNotNull);
      expect(first!.tag, '#Faith');
      expect(second!.tag, '#Faith-import');
      expect(third!.tag, '#Faith-import-2');

      final faithEntries = await repo.loadEntries('#Faith');
      final importEntries = await repo.loadEntries('#Faith-import');
      final importEntries2 = await repo.loadEntries('#Faith-import-2');
      expect(faithEntries, hasLength(1));
      expect(importEntries, hasLength(1));
      expect(importEntries2, hasLength(1));
    },
  );

  test('changing category does not change membership', () async {
    final repo = HashTagRepository();
    final db = await _openUserDatabase();
    await repo.ensureSchema();

    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryA',
      'verse_ref': '43:1:1',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 1,
      'created_at': 1,
    });

    final before = await repo.loadEntries('#Faith', category: 'CategoryA');
    final moved = await repo.saveTagCategory(
      '#Faith',
      'CategoryB',
      currentCategory: 'CategoryA',
      currentCategoryKnown: true,
    );
    final afterA = await repo.loadEntries('#Faith', category: 'CategoryA');
    final afterB = await repo.loadEntries('#Faith', category: 'CategoryB');

    expect(moved, isTrue);
    expect(before, hasLength(1));
    expect(afterA, hasLength(1));
    expect(afterB, hasLength(1));
  });

  test('category filters do not alter tag membership', () async {
    final repo = HashTagRepository();
    final db = await _openUserDatabase();
    await repo.ensureSchema();

    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryA',
      'verse_ref': '43:1:1',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 1,
      'created_at': 1,
    });
    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryB',
      'verse_ref': '43:1:2',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 2,
      'created_at': 2,
    });

    final entriesA = await repo.loadEntries('#Faith', category: 'CategoryA');
    final entriesB = await repo.loadEntries('#Faith', category: 'CategoryB');
    expect(entriesA, hasLength(2));
    expect(entriesB, hasLength(2));
  });

  test('duplicate diagnostics report repeated tag names', () async {
    final repo = HashTagRepository();
    final db = await _openUserDatabase();
    await repo.ensureSchema();

    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryA',
      'verse_ref': '43:1:1',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 1,
      'created_at': 1,
    });
    await db.insert('hash_tags', {
      'user_id': 1,
      'tag': '#Faith',
      'category': 'CategoryB',
      'verse_ref': '43:1:2',
      'book_number': 43,
      'chapter_number': 1,
      'verse_number': 2,
      'created_at': 2,
    });

    final duplicates = await repo.loadDuplicateTagNames();
    expect(duplicates, contains('#faith'));
    expect(await repo.debugDuplicateTagReport(), contains('#faith'));
  });
}
