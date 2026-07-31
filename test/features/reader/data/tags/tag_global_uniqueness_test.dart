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

String _entryKind(HashTagEntry entry) =>
    entry.bookNumber > 0 ? 'scripture' : 'note';

String _realisticHashExport(String tag, List<String> blocks) =>
    '''
*The following is a formatted sharing list for use in the Biblical Heritage #StudyBible app. Learn more at BiblicalHeritage.net for tutorials, downloads, shared lists, and related links.*

$tag (${blocks.length} items)

${blocks.join('\n\n')}
''';

String _reExportLoaded(String tag, List<HashTagEntry> entries) {
  var noteNumber = 0;
  final blocks = <String>[];
  for (final entry in entries) {
    if (entry.bookNumber > 0) {
      blocks.add('John ${entry.chapter}:${entry.verse}\nCanonical verse text');
    } else {
      noteNumber++;
      final friendlyTag = tag.replaceFirst(RegExp(r'^[#\$@]+'), '');
      blocks.add('$friendlyTag Note $noteNumber\n${entry.noteText ?? ''}');
    }
  }
  return _realisticHashExport(tag, blocks);
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

  group('mixed #tag import order', () {
    final cases = <String, ({List<String> blocks, List<String> kinds})>{
      'alternating items': (
        blocks: [
          'John 3:16\nFor God so loved the world.',
          'Mixed Note 1\nNote A',
          'John 3:17\nGod sent not his Son to condemn the world.',
          'Mixed Note 2\nNote B',
        ],
        kinds: ['scripture', 'note', 'scripture', 'note'],
      ),
      'notes surrounding a scripture': (
        blocks: [
          'Mixed Note 1\nNote A',
          'John 3:16\nFor God so loved the world.',
          'Mixed Note 2\nNote B',
        ],
        kinds: ['note', 'scripture', 'note'],
      ),
      'consecutive item types': (
        blocks: [
          'John 3:16\nFor God so loved the world.',
          'John 3:17\nGod sent not his Son to condemn the world.',
          'Mixed Note 1\nNote A',
          'Mixed Note 2\nNote B',
          'John 3:18\nHe that believeth on him is not condemned.',
        ],
        kinds: ['scripture', 'scripture', 'note', 'note', 'scripture'],
      ),
      'duplicate references': (
        blocks: [
          'John 3:16\nFor God so loved the world.',
          'Mixed Note 1\nNote A',
          'John 3:16\nFor God so loved the world.',
          'Mixed Note 2\nNote B',
        ],
        kinds: ['scripture', 'note', 'scripture', 'note'],
      ),
      'scripture only': (
        blocks: [
          'John 3:16\nFor God so loved the world.',
          'John 3:17\nGod sent not his Son to condemn the world.',
        ],
        kinds: ['scripture', 'scripture'],
      ),
      'note only': (
        blocks: ['Mixed Note 1\nNote A', 'Mixed Note 2\nNote B'],
        kinds: ['note', 'note'],
      ),
    };

    for (final testCase in cases.entries) {
      test('${testCase.key} persists and loads in source order', () async {
        final repo = HashTagRepository();
        final result = await repo.importSharedListFromText(
          _realisticHashExport('#Mixed', testCase.value.blocks),
          targetCategory: 'Imported',
        );

        expect(result, isNotNull);
        final entries = await repo.loadEntries(result!.tag);
        expect(entries.map(_entryKind).toList(), testCase.value.kinds);
        expect(entries.map((entry) => entry.sortOrder).toList(), [
          for (var i = 1; i <= entries.length; i++) i,
        ]);
        expect(
          entries
              .where((entry) => entry.bookNumber == 0)
              .map((e) => e.noteText),
          testCase.value.blocks
              .where((block) => block.startsWith('Mixed Note'))
              .map((block) => block.split('\n').skip(1).join('\n')),
        );
      });
    }

    test(
      'export import export preserves loaded type and content sequence',
      () async {
        final repo = HashTagRepository();
        final first = await repo.importSharedListFromText(
          _realisticHashExport('#RoundTrip', [
            'John 3:16\nFor God so loved the world.',
            'RoundTrip Note 1\nExplanation A',
            'John 3:17\nGod sent not his Son to condemn the world.',
            'RoundTrip Note 2\nExplanation B',
          ]),
        );
        final firstEntries = await repo.loadEntries(first!.tag);
        final second = await repo.importSharedListFromText(
          _reExportLoaded('#RoundTripCopy', firstEntries),
        );
        final secondEntries = await repo.loadEntries(second!.tag);

        expect(secondEntries.map(_entryKind), firstEntries.map(_entryKind));
        expect(
          secondEntries.map((e) => e.noteText ?? e.verseRef),
          firstEntries.map((e) => e.noteText ?? e.verseRef),
        );
      },
    );
  });

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
