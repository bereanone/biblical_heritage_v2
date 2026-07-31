import 'dart:convert';
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
import 'package:studybible2/features/library/data/library_contributor.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';
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

PioneerSourceWork _makeWork({
  required String id,
  required String authorId,
  required String authorName,
  required String title,
  required String abbreviation,
}) {
  return PioneerSourceWork(
    id: id,
    authorId: authorId,
    authorName: authorName,
    sourceFamily: 'Pioneer',
    title: title,
    abbreviation: abbreviation,
    group: 'Pioneer Authors',
    subgroup: 'Test',
    availability: PioneerSourceAvailability.available,
    verified: true,
    catalogImportable: true,
    sourceType: 'capturedHtml',
    sourceUrl: null,
    collectionUrl: null,
    captureUrl: null,
    readerUrl: null,
    directFileUrl: null,
    directFileType: null,
    sourceLabel: 'Test',
    notes: null,
  );
}

/// Creates a synthetic [PioneerHtmlCaptureFolderPreview] from [html] content
/// so tests don't need the asset scanner.
PioneerHtmlCaptureFolderPreview _syntheticPreview({
  required String folderPath,
  required String folderName,
  required String html,
  required PioneerSourceWork catalogWork,
  List<PioneerCaptureFolderContributorData> contributors = const [],
}) {
  final extraction = const EgwHtmlCaptureExtractor().extract(html);
  return PioneerHtmlCaptureFolderPreview(
    folderPath: folderPath,
    folderName: folderName,
    metadata: PioneerCaptureFolderMetadata(
      title: catalogWork.title,
      abbreviation: catalogWork.abbreviation,
      displayAbbreviation: catalogWork.abbreviation,
      workId: catalogWork.id,
      sourceType: 'capturedHtml',
      sourceSite: 'egwwritings.org',
      contributors: contributors,
    ),
    htmlFiles: [p.join(folderPath, 'capture.html')],
    imageFiles: const [],
    preferredCoverImagePath: null,
    detectedTitle: catalogWork.title,
    detectedAuthor: catalogWork.authorName,
    detectedAbbreviation: extraction.detectedAbbreviation,
    firstRef: extraction.firstRef,
    lastRef: extraction.lastRef,
    refCount: extraction.refCount,
    duplicateRefCount: extraction.duplicateRefCount,
    chapterHeadingCount: extraction.chapterHeadingCount,
    isValid: extraction.refCount > 0,
    warnings: const [],
    importStatus: PioneerHtmlCaptureImportStatus.newImport,
    catalogWork: catalogWork,
    extractedText: extraction.text,
  );
}

Future<PioneerHtmlCaptureFolderPreview> _scanLofPreview() async {
  final tempDir = await Directory.systemTemp.createTemp('lof_import_');
  addTearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  return _syntheticPreview(
    folderPath: p.join(tempDir.path, 'LOF_ATJ'),
    folderName: 'LOF_ATJ',
    html: _lofHtml,
    catalogWork: _lofCatalog().workById('lessons_on_faith')!,
    contributors: const [
      PioneerCaptureFolderContributorData(
        name: 'A. T. Jones',
        fullName: 'Alonzo Trevier Jones',
        role: 'author',
        sortOrder: 1,
        isPrimary: true,
      ),
      PioneerCaptureFolderContributorData(
        name: 'E. J. Waggoner',
        fullName: 'Ellet Joseph Waggoner',
        role: 'author',
        sortOrder: 2,
        isPrimary: false,
      ),
    ],
  );
}

PioneerSourceCatalog _lofCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'at_jones',
        'author_name': 'A. T. Jones',
        'source_family': 'Pioneer',
        'sort_key': 'a t jones',
        'works': [
          {
            'work_id': 'lessons_on_faith',
            'title': 'Lessons on Faith',
            'abbreviation': 'LOF',
            'group': 'Pioneer Authors',
            'subgroup': 'Righteousness by Faith',
            'availability_status': 'available',
            'source_type': 'capturedHtml',
            'source_url': 'assets/scans/LOF_ATJ/capture.html',
            'source_label': 'Local HTML Capture',
            'verified': true,
            'importable': true,
          },
        ],
      },
    ],
  });
}

/// Minimal captured-HTML that produces parseable paragraphs with EGW refs.
const _twoChapterHtml = '''
<div class="clip clip-text">
  <p>Chapter 1 — Introduction  TEST 1  First paragraph.  TEST 1.1 Second paragraph.  TEST 1.2</p>
</div>
<div class="clip clip-text">
  <p>Chapter 2 — Conclusion  TEST 2  Third paragraph.  TEST 2.1</p>
</div>
''';

const _lofHtml = '''
<!doctype html>
<html>
  <head><title>Lessons on Faith</title></head>
  <body>
    <div class="clip clip-text">
      <p>Chapter 1 — Living By Faith LOF_ATJ 1 Intro. LOF_ATJ 1.1 Faith matters.</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Gift of Righteousness LOF_ATJ 2 Grace is a gift. LOF_ATJ 2.1</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 3 — Walking With God LOF_ATJ 3.1 Faith continues.</p>
    </div>
  </body>
</html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('multi_author_support_');
    documentsDir = await Directory.systemTemp.createTemp(
      'multi_author_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'multi_author_root_',
    );
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
    if (supportDir.existsSync()) await supportDir.delete(recursive: true);
    if (documentsDir.existsSync()) await documentsDir.delete(recursive: true);
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  // ─── model unit tests ────────────────────────────────────────────────────

  group('LibraryContributor model helpers', () {
    test('displayAuthorsFromContributors joins names with semicolon', () {
      final jones = const LibraryContributor(
        id: 'a_t_jones',
        displayName: 'A. T. Jones',
      );
      final waggoner = const LibraryContributor(
        id: 'e_j_waggoner',
        displayName: 'E. J. Waggoner',
      );
      final contributors = [
        LibraryItemContributor(
          libraryItemId: 'lof',
          contributor: jones,
          role: 'author',
          sortOrder: 1,
          isPrimary: true,
        ),
        LibraryItemContributor(
          libraryItemId: 'lof',
          contributor: waggoner,
          role: 'author',
          sortOrder: 2,
          isPrimary: false,
        ),
      ];
      expect(
        displayAuthorsFromContributors(contributors),
        'A. T. Jones; E. J. Waggoner',
      );
    });

    test('shortAuthorsFromContributors joins last names with ampersand', () {
      final jones = const LibraryContributor(
        id: 'a_t_jones',
        displayName: 'A. T. Jones',
      );
      final waggoner = const LibraryContributor(
        id: 'e_j_waggoner',
        displayName: 'E. J. Waggoner',
      );
      final contributors = [
        LibraryItemContributor(
          libraryItemId: 'lof',
          contributor: jones,
          role: 'author',
          sortOrder: 1,
          isPrimary: true,
        ),
        LibraryItemContributor(
          libraryItemId: 'lof',
          contributor: waggoner,
          role: 'author',
          sortOrder: 2,
          isPrimary: false,
        ),
      ];
      expect(shortAuthorsFromContributors(contributors), 'Jones & Waggoner');
    });

    test('sortOrder is respected regardless of insertion order', () {
      final c1 = const LibraryContributor(
        id: 'c1',
        displayName: 'Zebra Author',
      );
      final c2 = const LibraryContributor(
        id: 'c2',
        displayName: 'Alpha Author',
      );
      final contributors = [
        LibraryItemContributor(
          libraryItemId: 'x',
          contributor: c1,
          role: 'author',
          sortOrder: 2,
          isPrimary: false,
        ),
        LibraryItemContributor(
          libraryItemId: 'x',
          contributor: c2,
          role: 'author',
          sortOrder: 1,
          isPrimary: true,
        ),
      ];
      // Alpha (sortOrder 1) must come before Zebra (sortOrder 2).
      expect(
        displayAuthorsFromContributors(contributors),
        'Alpha Author; Zebra Author',
      );
    });

    test('shortAuthorsFromDisplayString extracts last names', () {
      expect(
        shortAuthorsFromDisplayString('A. T. Jones; E. J. Waggoner'),
        'Jones & Waggoner',
      );
    });

    test('shortAuthorsFromDisplayString handles single-author field', () {
      expect(shortAuthorsFromDisplayString('Uriah Smith'), 'Uriah Smith');
    });

    test('ImportContributorSpec.fromJson round-trips all fields', () {
      final spec = ImportContributorSpec.fromJson({
        'name': 'E. J. Waggoner',
        'full_name': 'Ellet Joseph Waggoner',
        'role': 'editor',
        'sort_order': 2,
        'primary': false,
      });
      expect(spec.name, 'E. J. Waggoner');
      expect(spec.fullName, 'Ellet Joseph Waggoner');
      expect(spec.role, 'editor');
      expect(spec.sortOrder, 2);
      expect(spec.isPrimary, isFalse);
      expect(spec.stableId, 'e_j_waggoner');
    });

    test('ImportContributorSpec.toContributor produces stable contributor', () {
      const spec = ImportContributorSpec(
        name: 'A. T. Jones',
        fullName: 'Alonzo Trevier Jones',
        sortOrder: 1,
        isPrimary: true,
      );
      final contributor = spec.toContributor();
      expect(contributor.id, 'a_t_jones');
      expect(contributor.displayName, 'A. T. Jones');
      expect(contributor.fullName, 'Alonzo Trevier Jones');
    });
  });

  // ─── LibraryCatalogItem display ──────────────────────────────────────────

  group('LibraryCatalogItem multi-author display getters', () {
    LibraryCatalogItem makeItem({
      String? author,
      List<LibraryItemContributor> contributors = const [],
    }) {
      return LibraryCatalogItem(
        id: 'lof_item',
        title: 'Lessons on Faith',
        author: author,
        fileName: 'LOF.html',
        fileHash: null,
        relativePath: 'TextCaptures/Research/Pioneer Authors/at_jones/LOF.html',
        fileFormat: 'html',
        folderType: 'research',
        libraryRole: 'research',
        collectionName: 'Adventist Pioneer Library',
        sourceSite: null,
        sourceUrl: null,
        sourceType: 'egw_html_capture',
        coverPath: null,
        dateAdded: null,
        lastOpened: null,
        indexStatus: 'indexed',
        fileSize: 1000,
        mimeType: 'text/html',
        spineIndex: null,
        anchorId: null,
        epubHref: null,
        paragraphIndex: null,
        navigationCount: 5,
        contributors: contributors,
      );
    }

    test('displayAuthors falls back to displayAuthor when no contributors', () {
      final item = makeItem(author: 'Uriah Smith');
      expect(item.displayAuthors, 'Uriah Smith');
    });

    test('displayAuthors returns joined names from contributors list', () {
      final jones = const LibraryContributor(
        id: 'a_t_jones',
        displayName: 'A. T. Jones',
      );
      final waggoner = const LibraryContributor(
        id: 'e_j_waggoner',
        displayName: 'E. J. Waggoner',
      );
      final item = makeItem(
        author: 'A. T. Jones; E. J. Waggoner',
        contributors: [
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: jones,
            role: 'author',
            sortOrder: 1,
            isPrimary: true,
          ),
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: waggoner,
            role: 'author',
            sortOrder: 2,
            isPrimary: false,
          ),
        ],
      );
      expect(item.displayAuthors, 'A. T. Jones; E. J. Waggoner');
    });

    test('shortAuthors returns last names from contributors list', () {
      final jones = const LibraryContributor(
        id: 'a_t_jones',
        displayName: 'A. T. Jones',
      );
      final waggoner = const LibraryContributor(
        id: 'e_j_waggoner',
        displayName: 'E. J. Waggoner',
      );
      final item = makeItem(
        author: 'A. T. Jones; E. J. Waggoner',
        contributors: [
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: jones,
            role: 'author',
            sortOrder: 1,
            isPrimary: true,
          ),
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: waggoner,
            role: 'author',
            sortOrder: 2,
            isPrimary: false,
          ),
        ],
      );
      expect(item.shortAuthors, 'Jones & Waggoner');
    });

    test(
      'shortAuthors parses semicolon author field when no contributors loaded',
      () {
        final item = makeItem(author: 'A. T. Jones; E. J. Waggoner');
        expect(item.shortAuthors, 'Jones & Waggoner');
      },
    );

    test('subtitle uses combined author string when contributors present', () {
      final jones = const LibraryContributor(
        id: 'a_t_jones',
        displayName: 'A. T. Jones',
      );
      final waggoner = const LibraryContributor(
        id: 'e_j_waggoner',
        displayName: 'E. J. Waggoner',
      );
      final item = makeItem(
        author: 'A. T. Jones; E. J. Waggoner',
        contributors: [
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: jones,
            role: 'author',
            sortOrder: 1,
            isPrimary: true,
          ),
          LibraryItemContributor(
            libraryItemId: 'lof_item',
            contributor: waggoner,
            role: 'author',
            sortOrder: 2,
            isPrimary: false,
          ),
        ],
      );
      expect(item.subtitle, contains('A. T. Jones; E. J. Waggoner'));
    });
  });

  // ─── DB import integration — LOF auto-hardcode ───────────────────────────

  group('LOF auto-hardcode (real scan, no metadata.json)', () {
    test(
      'imports LOF: one library item, denormalized author, two contributor rows',
      () async {
        final lof = await _scanLofPreview();

        final result = await PioneerTextImportService()
            .importHtmlCaptureFolders([lof]);
        expect(
          result.importedCount,
          1,
          reason: 'LOF must import as a single work',
        );
        expect(result.failedCount, 0);

        final db = await ELibraryDatabase.instance.database;
        final work = lof.importWork;

        // Exactly one library_items row.
        expect(
          await _countRows(
            db,
            'library_items',
            where: 'id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          1,
          reason: 'Exactly one library_items row for LOF',
        );

        // Denormalized author contains both names.
        final itemRows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        );
        expect(itemRows.single['author'], 'A. T. Jones; E. J. Waggoner');

        // Two rows in library_contributors.
        expect(
          await _countRows(
            db,
            'library_contributors',
            where: 'id IN (?, ?)',
            whereArgs: ['a_t_jones', 'e_j_waggoner'],
          ),
          2,
          reason: 'Two contributor rows written to library_contributors',
        );

        // Two rows in library_item_contributors.
        expect(
          await _countRows(
            db,
            'library_item_contributors',
            where: 'library_item_id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          2,
          reason: 'Two contributor links for LOF',
        );

        // Primary contributor is A. T. Jones with sort_order 1.
        final primaryRows = await db.query(
          'library_item_contributors',
          where: 'library_item_id = ? AND is_primary = 1',
          whereArgs: [work.stableLibraryItemId],
        );
        expect(primaryRows, hasLength(1));
        expect(primaryRows.single['contributor_id'], 'a_t_jones');
        expect(primaryRows.single['sort_order'], 1);

        // Secondary contributor is E. J. Waggoner with sort_order 2.
        final waggonerRows = await db.query(
          'library_item_contributors',
          where: 'library_item_id = ? AND contributor_id = ?',
          whereArgs: [work.stableLibraryItemId, 'e_j_waggoner'],
        );
        expect(waggonerRows, hasLength(1));
        expect(waggonerRows.single['sort_order'], 2);
        expect(waggonerRows.single['is_primary'], 0);
      },
    );

    test(
      'overwrite preserves exactly one LOF item and replaces contributor links',
      () async {
        final lof = await _scanLofPreview();
        final service = PioneerTextImportService();

        // First import.
        await service.importHtmlCaptureFolders([lof]);

        // Second import (overwrite).
        final result2 = await service.importHtmlCaptureFolders([
          lof,
        ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);
        expect(result2.importedCount, 1);

        final db = await ELibraryDatabase.instance.database;
        final work = lof.importWork;

        // Still exactly one library_items row.
        expect(
          await _countRows(
            db,
            'library_items',
            where: 'id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          1,
          reason: 'No duplicate library_items after overwrite',
        );

        // Contributor links are replaced, not duplicated.
        expect(
          await _countRows(
            db,
            'library_item_contributors',
            where: 'library_item_id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          2,
          reason: 'Exactly two contributor links after overwrite, not four',
        );
      },
    );

    test(
      'no duplicate library_items rows after three sequential imports',
      () async {
        final lof = await _scanLofPreview();
        final service = PioneerTextImportService();

        await service.importHtmlCaptureFolders([lof]);
        await service.importHtmlCaptureFolders([
          lof,
        ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);
        await service.importHtmlCaptureFolders([
          lof,
        ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);

        final db = await ELibraryDatabase.instance.database;
        final itemId = lof.importWork.stableLibraryItemId;
        // The import service must never create more than one row for this stable ID.
        expect(
          await _countRows(
            db,
            'library_items',
            where: 'id = ?',
            whereArgs: [itemId],
          ),
          1,
          reason: 'Exactly one library_items row for the stable LOF item ID',
        );
        expect(
          await _countRows(
            db,
            'library_item_contributors',
            where: 'library_item_id = ?',
            whereArgs: [itemId],
          ),
          2,
          reason: 'Exactly two contributor links after three imports',
        );
      },
    );
  });

  // ─── DB import — metadata.json override ──────────────────────────────────

  group('metadata.json contributor override', () {
    test(
      'metadata.json specifies two authors for a generic single-author work',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'meta_json_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        });

        const folderName = 'HIST_SB';
        final folderPath = p.join(tempDir.path, folderName);
        await Directory(folderPath).create(recursive: true);

        // Write the metadata.json specifying two authors.
        await File(p.join(folderPath, 'metadata.json')).writeAsString(
          jsonEncode({
            'title': 'History of the Sabbath',
            'abbreviation': 'HIST_SB',
            'contributors': [
              {
                'name': 'J. N. Andrews',
                'full_name': 'John Nevins Andrews',
                'role': 'author',
                'sort_order': 1,
                'primary': true,
              },
              {
                'name': 'L. R. Conradi',
                'full_name': 'Ludwig Richard Conradi',
                'role': 'author',
                'sort_order': 2,
              },
            ],
          }),
        );

        // Catalog work: single authorName that would normally give one contributor.
        final work = _makeWork(
          id: 'history_of_the_sabbath_meta_override',
          authorId: 'jn_andrews',
          authorName: 'J. N. Andrews',
          title: 'History of the Sabbath',
          abbreviation: 'HIST',
        );

        // Synthetic preview with folderPath pointing to the temp dir so
        // _readCaptureMetadataContributors can find metadata.json.
        final preview = _syntheticPreview(
          folderPath: folderPath,
          folderName: folderName,
          html: _twoChapterHtml,
          catalogWork: work,
        );

        expect(
          preview.isValid,
          isTrue,
          reason: 'Preview must be valid for the test to be meaningful',
        );
        final importedWork = preview.importWork;

        final result = await PioneerTextImportService()
            .importHtmlCaptureFolders(
              [preview],
              existingImportPolicy:
                  PioneerExistingImportPolicy.overwriteExisting,
            );
        expect(
          result.importedCount,
          1,
          reason: 'One work must be imported successfully',
        );

        final db = await ELibraryDatabase.instance.database;
        final itemId = importedWork.stableLibraryItemId;

        // One library_items row.
        final itemRows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        expect(itemRows, hasLength(1));

        // Denormalized author from metadata.json.
        expect(
          itemRows.single['author'],
          'J. N. Andrews; L. R. Conradi',
          reason: 'author field must be built from metadata.json contributors',
        );

        // Two rows in library_contributors.
        expect(
          await _countRows(
            db,
            'library_contributors',
            where: 'id IN (?, ?)',
            whereArgs: ['j_n_andrews', 'l_r_conradi'],
          ),
          2,
        );

        // Two rows in library_item_contributors.
        expect(
          await _countRows(
            db,
            'library_item_contributors',
            where: 'library_item_id = ?',
            whereArgs: [itemId],
          ),
          2,
        );

        // Primary flag correct.
        final primaryRows = await db.query(
          'library_item_contributors',
          where: 'library_item_id = ? AND is_primary = 1',
          whereArgs: [itemId],
        );
        expect(primaryRows, hasLength(1));
        expect(primaryRows.single['contributor_id'], 'j_n_andrews');
      },
    );
  });

  // ─── author search via LibraryCatalogService ─────────────────────────────

  group('author search', () {
    Future<void> importLof() async {
      final lof = await _scanLofPreview();
      await PioneerTextImportService().importHtmlCaptureFolders([lof]);
    }

    test('searching by "Jones" finds Lessons on Faith', () async {
      await importLof();

      final results = await LibraryCatalogService.instance.searchContent(
        query: 'Jones',
        limit: 20,
      );

      final lofHit = results.where((r) => r.item.title == 'Lessons on Faith');
      expect(
        lofHit,
        isNotEmpty,
        reason: 'Searching "Jones" must find LOF via denormalized author field',
      );
    });

    test('searching by "Waggoner" finds Lessons on Faith', () async {
      await importLof();

      final results = await LibraryCatalogService.instance.searchContent(
        query: 'Waggoner',
        limit: 20,
      );

      final lofHit = results.where((r) => r.item.title == 'Lessons on Faith');
      expect(
        lofHit,
        isNotEmpty,
        reason:
            'Searching "Waggoner" must find LOF via denormalized author field',
      );
    });

    test('loadItems: LOF displayAuthor shows combined author string', () async {
      await importLof();

      final items = await LibraryCatalogService.instance.loadItems();
      final lofItems = items
          .where((i) => i.title == 'Lessons on Faith')
          .toList(growable: false);

      expect(lofItems, isNotEmpty, reason: 'LOF must appear in catalog');
      final lof = lofItems.first;
      expect(
        lof.displayAuthor,
        'A. T. Jones; E. J. Waggoner',
        reason: 'displayAuthor reads the denormalized author field',
      );
    });

    test('loadItems: LOF shortAuthors shows "Jones & Waggoner"', () async {
      await importLof();

      final items = await LibraryCatalogService.instance.loadItems();
      final lof = items.firstWhere((i) => i.title == 'Lessons on Faith');
      expect(
        lof.shortAuthors,
        'Jones & Waggoner',
        reason:
            'shortAuthors extracts last names from the semicolon-delimited field',
      );
    });
  });
}
