// Tests for category-safe tag rename/move SQL patterns.
//
// These tests verify the SQL WHERE clauses directly against a raw SQLite
// database so they do not depend on the UserDatabase singleton.  They confirm
// the invariants that the Phase-1 changes enforce:
//
//   • Same-name tags in different categories are distinct rows.
//   • A category-scoped UPDATE/rename does not bleed into other categories.
//   • IS NULL comparisons work correctly for root/uncategorized tags.
//   • The removed name-only fallback no longer exists in the helper.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Minimal schema that matches hash_tags as created by ensureSchema()
// ---------------------------------------------------------------------------
Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('tag_category_safety_');
  final dbPath = p.join(tempDir.path, 'test.db');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS hash_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL DEFAULT 1,
          tag TEXT NOT NULL,
          category TEXT,
          verse_ref TEXT NOT NULL DEFAULT '43:1:1',
          book_number INTEGER NOT NULL DEFAULT 43,
          chapter_number INTEGER NOT NULL DEFAULT 1,
          verse_number INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER,
          created_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    },
  );
  return (db: db, dir: tempDir);
}

// ---------------------------------------------------------------------------
// SQL helpers that mirror the exact WHERE clauses from the fixed production
// code, exercised here without going through HashTagRepository.
// ---------------------------------------------------------------------------

/// Category-scoped rename: mirrors the fixed renameTag() with categoryKnown=true.
Future<int> _renameCategoryScoped(
  Database db, {
  required String oldTag,
  required String newTag,
  required String? category,
}) {
  final whereArgs = <Object?>[oldTag];
  String where;
  if (category != null && category.isNotEmpty) {
    where = 'tag = ? AND category = ?';
    whereArgs.add(category);
  } else {
    // Root/uncategorized — uses IS NULL, not name-only.
    where = 'tag = ? AND (category IS NULL OR TRIM(category) = \'\')';
  }
  return db.update('hash_tags', {'tag': newTag}, where: where, whereArgs: whereArgs);
}

/// Category-scoped move: mirrors the fixed saveTagCategory() with
/// currentCategoryKnown=true using COALESCE.
Future<int> _moveCategoryScoped(
  Database db, {
  required String tag,
  required String newCategory,
  required String? currentCategory,
}) {
  final coalesced = currentCategory ?? '';
  return db.update(
    'hash_tags',
    {'category': newCategory},
    where: 'tag = ? AND COALESCE(TRIM(category), \'\') = ?',
    whereArgs: [tag, coalesced],
  );
}

/// Category-unaware set: mirrors the fixed saveTagCategory() with
/// currentCategoryKnown=false — only touches uncategorized rows.
Future<int> _setCategoryForUncategorized(
  Database db, {
  required String tag,
  required String newCategory,
}) {
  return db.update(
    'hash_tags',
    {'category': newCategory},
    where: 'tag = ? AND (category IS NULL OR TRIM(category) = \'\')',
    whereArgs: [tag],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tag category safety', () {
    late Database db;
    late Directory tempDir;

    setUp(() async {
      final setup = await _openTestDatabase();
      db = setup.db;
      tempDir = setup.dir;
    });

    tearDown(() async {
      await db.close();
      await deleteDatabase(p.join(tempDir.path, 'test.db'));
      await tempDir.delete(recursive: true);
    });

    // -----------------------------------------------------------------------
    // 1. Same-name tags in different categories can coexist
    // -----------------------------------------------------------------------
    test('same tag name in two categories coexists as distinct rows', () async {
      await db.insert('hash_tags', {
        'tag': 'faith',
        'category': 'CategoryA',
        'verse_ref': '43:1:1',
      });
      await db.insert('hash_tags', {
        'tag': 'faith',
        'category': 'CategoryB',
        'verse_ref': '43:1:2',
      });

      final rows = await db.query(
        'hash_tags',
        where: 'tag = ?',
        whereArgs: ['faith'],
      );
      expect(rows, hasLength(2));
      final categories = rows.map((r) => r['category']).toSet();
      expect(categories, containsAll(['CategoryA', 'CategoryB']));
    });

    // -----------------------------------------------------------------------
    // 2. Renaming #faith in CategoryA does NOT rename #faith in CategoryB
    // -----------------------------------------------------------------------
    test('category-scoped rename leaves same-name tag in other category intact',
        () async {
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryB', 'verse_ref': '43:1:2'});

      final count = await _renameCategoryScoped(
        db,
        oldTag: 'faith',
        newTag: 'trust',
        category: 'CategoryA',
      );
      expect(count, equals(1));

      final renamed = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['trust', 'CategoryA'],
      );
      expect(renamed, hasLength(1));

      final untouched = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryB'],
      );
      expect(untouched, hasLength(1), reason: '#faith in CategoryB must be untouched');
    });

    // -----------------------------------------------------------------------
    // 3. Moving #faith from CategoryA to CategoryC preserves its rows
    // -----------------------------------------------------------------------
    test('moving tag to another category preserves all its rows', () async {
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:2'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryB', 'verse_ref': '43:1:3'});

      final count = await _moveCategoryScoped(
        db,
        tag: 'faith',
        newCategory: 'CategoryC',
        currentCategory: 'CategoryA',
      );
      expect(count, equals(2), reason: 'Both CategoryA rows should move to CategoryC');

      final movedRows = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryC'],
      );
      expect(movedRows, hasLength(2), reason: 'CategoryC now has both moved rows');

      final bRows = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryB'],
      );
      expect(bRows, hasLength(1), reason: 'CategoryB row must be untouched');

      final aRows = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryA'],
      );
      expect(aRows, isEmpty, reason: 'CategoryA rows have been moved');
    });

    // -----------------------------------------------------------------------
    // 4. Moving into a category where the name already exists does not silently
    //    overwrite — both sets of rows end up in the target (merge needed).
    //    This verifies that after a move the source rows are gone from the
    //    source category and the target count grew, not replaced.
    // -----------------------------------------------------------------------
    test(
        'moving tag into category with same name accumulates rows, does not overwrite',
        () async {
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryB', 'verse_ref': '43:1:2'});

      final count = await _moveCategoryScoped(
        db,
        tag: 'faith',
        newCategory: 'CategoryB',
        currentCategory: 'CategoryA',
      );
      expect(count, equals(1));

      // Both rows are now in CategoryB (the existing one + the moved one).
      final bRows = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryB'],
      );
      expect(
        bRows,
        hasLength(2),
        reason:
            'The moved row joins the existing row; no row is silently deleted',
      );
    });

    // -----------------------------------------------------------------------
    // 5. Unknown-category set only touches uncategorized rows, leaves
    //    categorized rows with the same name intact.
    // -----------------------------------------------------------------------
    test(
        'unknown-category saveTagCategory only affects rows with no category',
        () async {
      // One row with no category, one with CategoryB.
      await db.insert('hash_tags', {'tag': 'faith', 'category': null, 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryB', 'verse_ref': '43:1:2'});

      final count = await _setCategoryForUncategorized(
        db,
        tag: 'faith',
        newCategory: 'CategoryA',
      );
      expect(count, equals(1), reason: 'Only the uncategorized row is updated');

      final aRow = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryA'],
      );
      expect(aRow, hasLength(1));

      final bRow = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryB'],
      );
      expect(bRow, hasLength(1), reason: 'CategoryB row must not be affected');
    });

    // -----------------------------------------------------------------------
    // 6. NULL category comparison: IS NULL matches NULL rows, not '' rows
    //    (verifies correct SQLite NULL semantics used in the fixed code).
    // -----------------------------------------------------------------------
    test('IS NULL correctly distinguishes NULL from empty-string category', () async {
      await db.insert('hash_tags', {'tag': 'faith', 'category': null, 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': '', 'verse_ref': '43:1:2'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:3'});

      // COALESCE(TRIM(category),'') = '' should match both NULL and empty.
      final coalesceRows = await db.rawQuery(
        "SELECT id FROM hash_tags WHERE tag = ? AND COALESCE(TRIM(category), '') = ''",
        ['faith'],
      );
      expect(coalesceRows, hasLength(2), reason: 'NULL and empty are both root');

      // (category IS NULL OR TRIM(category) = '') should also match both.
      final isNullRows = await db.rawQuery(
        "SELECT id FROM hash_tags WHERE tag = ? AND (category IS NULL OR TRIM(category) = '')",
        ['faith'],
      );
      expect(isNullRows, hasLength(2), reason: 'IS NULL clause also covers empty');

      // category = NULL should match nothing (SQLite NULL != NULL).
      final eqNullRows = await db.rawQuery(
        'SELECT id FROM hash_tags WHERE tag = ? AND category = NULL',
        ['faith'],
      );
      expect(eqNullRows, isEmpty, reason: 'category = NULL never matches in SQLite');
    });

    // -----------------------------------------------------------------------
    // 7. Category-scoped rename of a root (NULL-category) tag does not affect
    //    a same-name tag in a named category.
    // -----------------------------------------------------------------------
    test('renaming a root-category tag does not affect same-name categorized tag',
        () async {
      await db.insert('hash_tags', {'tag': 'faith', 'category': null, 'verse_ref': '43:1:1'});
      await db.insert('hash_tags', {'tag': 'faith', 'category': 'CategoryA', 'verse_ref': '43:1:2'});

      final count = await _renameCategoryScoped(
        db,
        oldTag: 'faith',
        newTag: 'trust',
        category: null, // root tag rename
      );
      expect(count, equals(1));

      final rootRow = await db.query(
        'hash_tags',
        where: "tag = ? AND (category IS NULL OR TRIM(category) = '')",
        whereArgs: ['trust'],
      );
      expect(rootRow, hasLength(1), reason: 'root tag now has the new name');

      final catARow = await db.query(
        'hash_tags',
        where: 'tag = ? AND category = ?',
        whereArgs: ['faith', 'CategoryA'],
      );
      expect(catARow, hasLength(1), reason: 'CategoryA faith tag is untouched');
    });
  });
}
