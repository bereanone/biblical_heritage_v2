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
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_review_store.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';
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

Future<Directory> _createCaptureFolder({
  required Directory root,
  required String title,
  required String abbreviation,
  required String workId,
  required String sourceUrl,
  required String authorName,
  required String bodyHtml,
}) async {
  final folder = Directory(p.join(root.path, workId));
  await folder.create(recursive: true);
  await File(p.join(folder.path, 'metadata.json')).writeAsString('''
{
  "title": "$title",
  "abbreviation": "$abbreviation",
  "work_id": "$workId",
  "source_type": "pioneer_captured_html",
  "source_site": "user_capture",
  "source_url": "$sourceUrl",
  "contributors": [
    {
      "name": "$authorName",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ]
}
''');
  await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$title</title>
    <meta name="author" content="$authorName" />
    <link rel="canonical" href="$sourceUrl" />
  </head>
  <body>
    <h1>$title</h1>
    $bodyHtml
  </body>
</html>
''');
  return folder;
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

class _FailingCapturedHtmlImportService extends PioneerTextImportService {
  @override
  Future<PioneerImportBatchResult> importFromParsedCapturedHtml({
    required PioneerSourceWork work,
    required PioneerImportDocument document,
    required Uint8List sourceBytes,
    String? sourceUrl,
    String? sourceLabel,
    String? sourceType,
    String? sourceSite,
    String? relativePath,
    String? coverPath,
    List<ImportContributorSpec>? contributors,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    String? indexStatus,
    String? indexError,
  }) async {
    return PioneerImportBatchResult(
      workResults: [
        PioneerImportWorkResult(
          work: work,
          status: PioneerImportWorkStatus.failed,
          stage: 'failed',
          sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
          reason: 'Simulated import failure.',
          libraryItemId: '',
          sourceType: sourceType,
          insertedLibraryItems: 0,
          insertedNavigationItems: 0,
          insertedTextBlocks: 0,
          skippedExisting: false,
          refCodeHandlingSummary: 'Simulated failure.',
          detail: 'Simulated import failure.',
          exceptionType: 'SimulatedFailure',
          httpStatusCode: null,
          contentType: 'text/html',
          downloadedByteCount: sourceBytes.length,
          parsedSectionCount: document.sections.length,
          parsedParagraphCount: document.sections.fold<int>(
            0,
            (sum, section) => sum + section.paragraphs.length,
          ),
          requiresManualVerification: false,
          manualVerificationHint: null,
          epubAvailable: false,
          epubValidated: false,
          epubRejectedReason: null,
          textCaptureAvailable: true,
          preferredImportPreference: PioneerSourcePathPreference.textCapture,
          qualityValidationSummary: 'Simulated failure.',
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory captureRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'capture_import_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'capture_import_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'capture_import_library_',
    );
    captureRootDir = await Directory.systemTemp.createTemp(
      'capture_import_folder_',
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
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
    if (captureRootDir.existsSync()) {
      await captureRootDir.delete(recursive: true);
    }
  });

  test('parses captured HTML headings, paragraphs, and page markers', () {
    const parser = PioneerCapturedHtmlParser();
    const html = '''
<!doctype html>
<html>
  <head>
    <title>Captured Sermon</title>
    <meta name="author" content="E. G. White" />
  </head>
  <body>
    <h1>Captured Sermon</h1>
    <p>First paragraph [12]</p>
    <h2>Section 2</h2>
    <p>Second paragraph</p>
  </body>
</html>
''';

    final result = parser.parse(
      html: html,
      filePath: p.join(captureRootDir.path, 'captured', 'capture.html'),
      relativePath: 'captured/capture.html',
      metadata: const PioneerCaptureFolderMetadata(
        sourceUrl: 'https://example.invalid/captured-sermon',
      ),
    );

    expect(result.title, 'Captured Sermon');
    expect(result.author, 'E. G. White');
    expect(result.sourceUrl, 'https://example.invalid/captured-sermon');
    expect(result.sourceSite, 'local_cloud_folder');
    expect(result.headingCount, 2);
    expect(result.paragraphCount, 2);
    expect(result.pageMarkerCount, 1);
    expect(result.document.sections, hasLength(2));
    expect(result.warnings, isEmpty);
    expect(result.isValid, isTrue);
  });

  test(
    'imports a configured capture folder, writes captured HTML items, and skips duplicates on rerun',
    () async {
      const title = 'Captured Sermon';
      const abbreviation = 'CS';
      const workId = 'captured_sermon';
      const sourceUrl = 'https://example.invalid/captured-sermon';
      const authorName = 'E. G. White';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <p>First paragraph.</p>
    <h2>Section 2</h2>
    <p>Second paragraph.</p>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
        bookmark: 'bookmark-token-123',
      );

      expect(
        await LocalSettingsStore.instance.loadPioneerCapturedHtmlFolderPath(),
        folder.path,
      );
      expect(
        await LocalSettingsStore.instance
            .loadPioneerCapturedHtmlFolderBookmark(),
        'bookmark-token-123',
      );

      final service = PioneerCapturedHtmlImportFolderService.instance;
      final firstReport = await service.importConfiguredFolder();

      expect(firstReport.folderPath, folder.path);
      expect(firstReport.htmlFileCount, 1);
      expect(firstReport.importedCount, 1);
      expect(firstReport.skippedDuplicateCount, 0);
      expect(firstReport.needsCleanupCount, 0);
      expect(firstReport.failedCount, 0);

      final firstFile = firstReport.files.single;
      expect(firstFile.status, PioneerCapturedHtmlFileStatus.imported);
      expect(firstFile.reason, contains('Imported into eLibrary.db.'));
      expect(firstFile.sourceType, 'pioneer_captured_html');
      expect(firstFile.sourceSite, 'user_capture');
      expect(firstFile.title, title);
      expect(firstFile.author, authorName);
      expect(firstFile.libraryItemId, isNotNull);

      final reviewEntries = await PioneerCapturedHtmlImportReviewStore.instance
          .loadRecentEntries(limit: 5);
      expect(reviewEntries, hasLength(1));
      final reviewEntry = reviewEntries.single;
      expect(reviewEntry.status, 'imported');
      expect(reviewEntry.libraryItemId, firstFile.libraryItemId);
      expect(
        await LibraryCatalogService.instance.loadItemById(
          reviewEntry.libraryItemId!,
        ),
        isNotNull,
      );

      final db = await ELibraryDatabase.instance.database;
      final rows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [firstFile.libraryItemId],
        limit: 1,
      );
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['source_type'], 'pioneer_captured_html');
      expect(row['source_site'], 'user_capture');
      expect(
        row['relative_path'],
        p.join(
          'TextCaptures',
          'Research',
          'Pioneer Authors',
          workId,
          'captured_html',
          'capture.html',
        ),
      );
      expect(row['author'], authorName);
      expect(row['title'], title);
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [firstFile.libraryItemId],
        ),
        2,
      );

      final duplicateReport = await service.importConfiguredFolder();
      expect(duplicateReport.importedCount, 0);
      expect(duplicateReport.skippedDuplicateCount, 1);
      expect(duplicateReport.needsCleanupCount, 0);
      expect(duplicateReport.failedCount, 0);
      expect(
        duplicateReport.files.single.status,
        isA<PioneerCapturedHtmlFileStatus>(),
      );
      expect(
        duplicateReport.files.single.status,
        PioneerCapturedHtmlFileStatus.skippedDuplicate,
      );
    },
  );

  test(
    'persists needsCleanup review entries with warning text',
    () async {
      const title = 'Captured Sermon Cleanup';
      const abbreviation = 'CSC';
      const workId = 'captured_sermon_cleanup';
      const sourceUrl = 'https://example.invalid/captured-sermon-cleanup';
      const authorName = 'E. G. White';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <p>First paragraph.</p>
    <p>Second paragraph.</p>
''',
      );
      await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$title</title>
    <meta name="author" content="$authorName" />
    <link rel="canonical" href="$sourceUrl" />
  </head>
  <body>
    <p>First paragraph.</p>
    <p>Second paragraph.</p>
  </body>
</html>
''');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredFolder();
      expect(report.needsCleanupCount, 1);

      final settings = await LocalSettingsStore.instance.load();
      expect(
        settings['pioneer_captured_html_review_entries'],
        isA<List>(),
      );
      expect(settings['pioneer_captured_html_review_entries'], isNotEmpty);

      final reviewEntries = await PioneerCapturedHtmlImportReviewStore.instance
          .loadRecentEntries();
      expect(reviewEntries, hasLength(1));
      final reviewEntry = reviewEntries.single;
      expect(reviewEntry.status, 'needsCleanup');
      expect(reviewEntry.libraryItemId, isNotNull);
      expect(reviewEntry.warningOrFailureReason, isNotNull);
      expect(
        reviewEntry.warningOrFailureReason,
        contains('No h1/h2/h3 headings were found.'),
      );
      expect(reviewEntry.isNeedsCleanup, isTrue);
      expect(reviewEntry.isImported, isFalse);
    },
  );

  test(
    'marks same-path changed HTML as needing cleanup instead of silently importing',
    () async {
      const title = 'Captured Sermon';
      const abbreviation = 'CS';
      const workId = 'captured_sermon_changed';
      const sourceUrl = 'https://example.invalid/captured-sermon-changed';
      const authorName = 'E. G. White';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <p>First paragraph.</p>
    <h2>Section 2</h2>
    <p>Second paragraph.</p>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
      );

      final service = PioneerCapturedHtmlImportFolderService.instance;
      final firstReport = await service.importConfiguredFolder();
      expect(
        firstReport.files.single.status,
        PioneerCapturedHtmlFileStatus.imported,
      );

      await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$title</title>
    <meta name="author" content="$authorName" />
    <link rel="canonical" href="$sourceUrl" />
  </head>
  <body>
    <h1>$title</h1>
    <p>First paragraph updated.</p>
    <h2>Section 2</h2>
    <p>Second paragraph updated.</p>
  </body>
</html>
''');

      final secondReport = await service.importConfiguredFolder();
      expect(secondReport.importedCount, 0);
      expect(secondReport.skippedDuplicateCount, 0);
      expect(secondReport.needsCleanupCount, 1);
      expect(secondReport.failedCount, 0);
      final secondFile = secondReport.files.single;
      expect(secondFile.status, PioneerCapturedHtmlFileStatus.needsCleanup);
      expect(secondFile.reason, contains('contents changed'));
      expect(secondFile.libraryItemId, isNotNull);
    },
  );

  test(
    'persists failed review entries without creating broken catalog items',
    () async {
      const title = 'Captured Failure Sermon';
      const abbreviation = 'CFS';
      const workId = 'captured_failure_sermon';
      const sourceUrl = 'https://example.invalid/captured-failure-sermon';
      const authorName = 'E. G. White';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <p>First paragraph.</p>
    <h2>Section 2</h2>
    <p>Second paragraph.</p>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
      );

      final service = PioneerCapturedHtmlImportFolderService(
        importService: _FailingCapturedHtmlImportService(),
      );
      final report = await service.importConfiguredFolder();

      expect(report.failedCount, 1);
      final file = report.files.single;
      expect(file.status, PioneerCapturedHtmlFileStatus.failed);
      expect(file.reason, contains('Simulated import failure.'));
      expect(file.libraryItemId, isNull);

      final reviewEntries = await PioneerCapturedHtmlImportReviewStore.instance
          .loadRecentEntries();
      expect(reviewEntries, hasLength(1));
      final reviewEntry = reviewEntries.single;
      expect(reviewEntry.status, 'failed');
      expect(reviewEntry.libraryItemId, isNull);
      expect(reviewEntry.warningOrFailureReason, contains('Simulated'));

      final catalogItems = await LibraryCatalogService.instance.loadItems();
      expect(
        catalogItems.where((item) => item.displayTitle == title),
        isEmpty,
      );
    },
  );

  test(
    'imports captured HTML into the Pioneer catalog and reader search path',
    () async {
      const title = 'Captured Sermon';
      const abbreviation = 'CS';
      const workId = 'captured_sermon_catalog';
      const sourceUrl = 'https://example.invalid/captured-sermon-catalog';
      const authorName = 'E. G. White';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <p>First paragraph.</p>
    <h2>Section 2</h2>
    <p>Second paragraph with a unique captured phrase.</p>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredFolder();
      expect(report.importedCount, 1);

      final imported = report.files.single;
      final catalogItems = await LibraryCatalogService.instance.loadItems();
      final catalogItem = catalogItems.firstWhere(
        (item) => item.id == imported.libraryItemId,
      );

      expect(catalogItem.collectionGroupKey, 'adventist_pioneer_library');
      expect(catalogItem.collectionName, 'Adventist Pioneer Library');
      expect(catalogItem.displayTitle, title);
      expect(catalogItem.displayAuthor, authorName);
      expect(
        catalogItem.relativePath,
        contains('TextCaptures/Research/Pioneer Authors'),
      );
      expect(
        await LibraryCatalogService.instance.loadItemById(catalogItem.id),
        isNotNull,
      );

      final searchResults = await LibraryCatalogService.instance.searchContent(
        query: 'unique captured phrase',
        collectionFilter: 'adventist_pioneer_library',
      );
      final hit = searchResults.firstWhere(
        (result) => result.item.id == catalogItem.id,
      );
      expect(hit.item.id, catalogItem.id);
      expect(hit.locationText, contains('CS 2.1'));
      expect(
        await LibraryCatalogService.instance.loadSearchResultParagraph(hit),
        contains('unique captured phrase'),
      );

      final sections = await CommentaryResearchLibraryService.instance
          .loadBookSections(
            filePath: p.join(libraryRootDir.path, catalogItem.relativePath),
            libraryItemId: catalogItem.id,
          );
      expect(
        sections.expand((section) => section.paragraphs).toList(),
        <String>[
          'First paragraph.',
          'Second paragraph with a unique captured phrase.',
        ],
      );
    },
  );
}
