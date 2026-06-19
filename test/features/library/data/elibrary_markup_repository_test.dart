import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/elibrary_markup_repository.dart';

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

Future<void> _seedMarkup({
  required Database db,
  required String libraryItemId,
  required String epubHref,
  required String markupType,
  required String color,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'elibrary_markups',
    <String, Object?>{
      'library_item_id': libraryItemId,
      'epub_href': epubHref,
      'start_block_index': 1,
      'start_char_offset': 0,
      'end_block_index': 1,
      'end_char_offset': 10,
      'start_token_index': null,
      'end_token_index': null,
      'ref_start': 'AA 1.1',
      'ref_end': 'AA 1.1',
      'compact_ref': 'AA 1.1',
      'selected_text_snapshot': 'sample text',
      'markup_type': markupType,
      'color': color,
      'note_text': markupType == 'note' ? 'legacy note' : null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<int> _countMarkups(
  Database db, {
  required String libraryItemId,
}) async {
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS cnt
    FROM elibrary_markups
    WHERE library_item_id = ? AND deleted_at IS NULL
    ''',
    [libraryItemId],
  );
  return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('elibrary_markup_support_');
    documentsDir = await Directory.systemTemp.createTemp('elibrary_markup_documents_');
    libraryRootDir = await Directory.systemTemp.createTemp('elibrary_markup_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  test('falls back to user.db markups when eLibrary.db is empty', () async {
    final userDb = await UserDatabase.instance.database;
    await ELibraryDatabase.instance.database;
    await _seedMarkup(
      db: userDb,
      libraryItemId: 'item-1',
      epubHref: 'OEBPS/content01.xhtml',
      markupType: 'note',
      color: '#ff0000',
    );

    final bySection = await ElibraryMarkupRepository()
        .loadMarkupsBySectionForItem('item-1');

    expect(bySection['OEBPS/content01.xhtml'], isNotNull);
    expect(bySection['OEBPS/content01.xhtml']!.single.markupType, 'note');
    expect(
      await ElibraryMarkupRepository()
          .loadHighlightsBySectionForItem('item-1'),
      isEmpty,
    );
  });

  test('writes highlights to eLibrary.db and reads them back', () async {
    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;

    final saved = await ElibraryMarkupRepository().saveHighlight(
      libraryItemId: 'item-2',
      epubHref: 'OEBPS/content02.xhtml',
      startBlockIndex: 2,
      startCharOffset: 5,
      endBlockIndex: 2,
      endCharOffset: 17,
      refStart: 'AA 2.1',
      refEnd: 'AA 2.1',
      compactRef: 'AA 2.1',
      selectedTextSnapshot: 'saved text',
    );

    expect(saved, isNotNull);
    expect(saved!.isHighlight, isTrue);
    expect(
      await _countMarkups(eLibraryDb, libraryItemId: 'item-2'),
      1,
    );
    expect(
      await _countMarkups(userDb, libraryItemId: 'item-2'),
      0,
    );

    final bySection = await ElibraryMarkupRepository()
        .loadHighlightsBySectionForItem('item-2');
    expect(bySection['OEBPS/content02.xhtml'], isNotNull);
    expect(bySection['OEBPS/content02.xhtml']!.single.compactRef, 'AA 2.1');
  });
}
