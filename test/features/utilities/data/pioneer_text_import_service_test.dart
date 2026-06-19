import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

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

PioneerSourceWork _work({
  required String id,
  required String authorId,
  required String authorName,
  required String title,
  required String abbreviation,
  required String sourceType,
  required String sourceUrl,
}) {
  return PioneerSourceWork(
    id: id,
    authorId: authorId,
    authorName: authorName,
    title: title,
    abbreviation: abbreviation,
    group: 'Pioneer Authors',
    subgroup: 'Prophecy',
    availability: PioneerSourceAvailability.available,
    verified: true,
    catalogImportable: true,
    sourceType: sourceType,
    sourceUrl: sourceUrl,
    sourceLabel: null,
    notes: null,
  );
}

PioneerImportDocument _fakeDocumentFor(PioneerSourceWork work) {
  switch (work.id) {
    case 'daniel_and_the_revelation':
      return PioneerImportDocument(
        title: work.title,
        sections: [
          PioneerImportSection(
            href: 'OEBPS/content01.xhtml',
            title: 'Chapter 1',
            paragraphs: const <String>[
              'Daniel and the Revelation opens with the revelation.',
              'The prophecy of Revelation is plain.',
            ],
            spineIndex: 1,
          ),
          PioneerImportSection(
            href: 'OEBPS/content02.xhtml',
            title: 'Chapter 2',
            paragraphs: const <String>[
              'Another Daniel and the Revelation paragraph.',
            ],
            spineIndex: 2,
          ),
        ],
      );
    case 'the_united_states_in_the_light_of_prophecy':
      return PioneerImportDocument(
        title: work.title,
        sections: [
          PioneerImportSection(
            href: 'OEBPS/content01.xhtml',
            title: 'Chapter 1',
            paragraphs: const <String>[
              'The United States in the Light of Prophecy explains history.',
              'The United States and prophecy appear together here.',
            ],
            spineIndex: 1,
          ),
        ],
      );
    default:
      throw StateError('Unexpected work requested in fake parser: ${work.id}');
  }
}

Future<int> _countRows(
  Database db,
  String tableName, {
  String? where,
  List<Object?> whereArgs = const [],
}) async {
  final sql = StringBuffer('SELECT COUNT(*) AS cnt FROM "$tableName"');
  if (where != null && where.trim().isNotEmpty) {
    sql.write(' WHERE $where');
  }
  final rows = await db.rawQuery(sql.toString(), whereArgs);
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
    supportDir = await Directory.systemTemp.createTemp('pioneer_import_support_');
    documentsDir = await Directory.systemTemp.createTemp('pioneer_import_documents_');
    libraryRootDir = await Directory.systemTemp.createTemp('pioneer_import_root_');
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

  test('imports two verified Pioneer works into eLibrary.db and makes them searchable', () async {
    final dar = _work(
      id: 'daniel_and_the_revelation',
      authorId: 'uriah_smith',
      authorName: 'Uriah Smith',
      title: 'Daniel and the Revelation',
      abbreviation: 'DAR',
      sourceType: 'epub',
      sourceUrl:
          'https://archive.org/download/UriahSmithDanielAndTheRevelation.TheResponseOfHistoryToTheVoiceOf/1897_smith_danielAndTheRevelation.epub',
    );
    final uslp = _work(
      id: 'the_united_states_in_the_light_of_prophecy',
      authorId: 'uriah_smith',
      authorName: 'Uriah Smith',
      title: 'The United States in the Light of Prophecy',
      abbreviation: 'USLP',
      sourceType: 'html',
      sourceUrl: 'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
    );
    final blocked = PioneerSourceWork(
      id: 'history_of_the_sabbath',
      authorId: 'jn_andrews',
      authorName: 'J. N. Andrews',
      title: 'History of the Sabbath',
      abbreviation: 'HST',
      group: 'Pioneer Authors',
      subgroup: 'Sabbath',
      availability: PioneerSourceAvailability.sourceNeeded,
      verified: false,
      catalogImportable: false,
      sourceType: null,
      sourceUrl: null,
      sourceLabel: null,
      notes: null,
    );

    final service = PioneerTextImportService(
      fetchBytes: (uri) async => Uint8List.fromList(uri.toString().codeUnits),
      parseDocument: (work, bytes) async => _fakeDocumentFor(work),
    );

    final result = await service.importSelectedWorks([dar, uslp, blocked]);

    expect(result.importedCount, 2);
    expect(result.skippedCount, 1);
    expect(result.failedCount, 0);
    expect(
      result.workResults.map((item) => item.status),
      containsAll([
        PioneerImportWorkStatus.imported,
        PioneerImportWorkStatus.imported,
        PioneerImportWorkStatus.skippedNotImportable,
      ]),
    );

    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;

    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [uslp.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      3,
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_navigation_items',
        where: 'library_item_id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      2,
    );

    expect(
      await _countRows(
        userDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      0,
    );
    expect(
      await _countRows(
        userDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [uslp.stableLibraryItemId],
      ),
      0,
    );

    final darSearch = await LibraryCatalogService.instance.searchContent(
      query: 'revelation',
    );
    expect(darSearch, isNotEmpty);
    expect(darSearch.first.item.id, dar.stableLibraryItemId);

    final uslpSearch = await LibraryCatalogService.instance.searchContent(
      query: 'United States',
    );
    expect(uslpSearch, isNotEmpty);
    expect(uslpSearch.first.item.id, uslp.stableLibraryItemId);

    final sections = await CommentaryResearchLibraryService.instance.loadBookSections(
      filePath: p.join(
        libraryRootDir.path,
        'ePubs',
        'Research',
        'Pioneer Authors',
        'uriah_smith',
        'DAR.epub',
      ),
      libraryItemId: dar.stableLibraryItemId,
    );
    expect(sections, hasLength(2));
    expect(sections.first.title, 'Chapter 1');
  });

  test('repeated import skips existing Pioneer rows without duplicating them', () async {
    final dar = _work(
      id: 'daniel_and_the_revelation',
      authorId: 'uriah_smith',
      authorName: 'Uriah Smith',
      title: 'Daniel and the Revelation',
      abbreviation: 'DAR',
      sourceType: 'epub',
      sourceUrl:
          'https://archive.org/download/UriahSmithDanielAndTheRevelation.TheResponseOfHistoryToTheVoiceOf/1897_smith_danielAndTheRevelation.epub',
    );
    final uslp = _work(
      id: 'the_united_states_in_the_light_of_prophecy',
      authorId: 'uriah_smith',
      authorName: 'Uriah Smith',
      title: 'The United States in the Light of Prophecy',
      abbreviation: 'USLP',
      sourceType: 'html',
      sourceUrl: 'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
    );

    final service = PioneerTextImportService(
      fetchBytes: (uri) async => Uint8List.fromList(uri.toString().codeUnits),
      parseDocument: (work, bytes) async => _fakeDocumentFor(work),
    );

    final first = await service.importSelectedWorks([dar, uslp]);
    expect(first.importedCount, 2);

    final eLibraryDb = await ELibraryDatabase.instance.database;
    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [uslp.stableLibraryItemId],
      ),
      1,
    );

    final second = await service.importSelectedWorks([dar, uslp]);
    expect(second.importedCount, 0);
    expect(second.skippedCount, 2);
    expect(
      second.workResults.map((item) => item.status),
      everyElement(PioneerImportWorkStatus.skippedExisting),
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [dar.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        eLibraryDb,
        'library_items',
        where: 'id = ?',
        whereArgs: [uslp.stableLibraryItemId],
      ),
      1,
    );
  });
}
