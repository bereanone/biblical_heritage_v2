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
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_availability_service.dart';
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

Future<void> _clearCapturedHtmlImportState() async {
  final db = await ELibraryDatabase.instance.database;
  await db.transaction((txn) async {
    for (final table in const <String>[
      'library_navigation_items',
      'library_text_blocks',
      'library_links',
      'elibrary_ref_index',
      'library_item_contributors',
      'elibrary_markups',
      'library_items',
      'library_contributors',
    ]) {
      await txn.delete(table);
    }
  });
  PioneerCapturedHtmlImportAvailabilityService.instance.clear();
}

Future<Directory> _createCaptureFolder({
  required Directory root,
  String? folderName,
  required String title,
  required String abbreviation,
  required String workId,
  required String sourceUrl,
  required String authorName,
  required String bodyHtml,
}) async {
  final folder = Directory(p.join(root.path, folderName ?? workId));
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

PioneerSourceCatalog _darCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'source_family': 'Pioneer',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': 'DAR',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'capturedHtml',
            'source_label': 'CaptureClipper',
            'verified': true,
            'importable': true,
          },
        ],
      },
    ],
  });
}

const String _sspImportHtml = '''
<!doctype html>
<html>
  <head><title>SSP</title></head>
  <body>
    <b class="calibre1">AUTHORS PREFACE.</b>
    <p>These pages introduce the book.</p>
    <b class="calibre1">CONTENTS.</b>
    <p>CHAPTER 1.--THE SEER OF PATMOS,.................. pg. 11.</p>
    <b id="calibre_toc_1" class="calibre1">CHAPTER 1. THE SEER OF PATMOS.</b>
    <p>SSP 1.1 First paragraph. {SSP 1.1}</p>
    <p>SSP 1.2 Second paragraph. {SSP 1.2}</p>
    <b id="calibre_toc_2" class="calibre1">CHAPTER 2. THE CHRIST OF THE APOCALYPSE.</b>
    <p>SSP 2.1 Third paragraph. {SSP 2.1}</p>
  </body>
</html>
''';

/// Mirrors the on-disk layout produced by the real CaptureClipper app:
/// a folder with `capture.html`, `manifest.json` (no metadata.json), and an
/// `images/` directory.
Future<Directory> _createCaptureClipperFolder({
  required Directory root,
  required String folderName,
  required String manifestTitle,
  String? manifestAuthor,
  String? manifestShortCode,
  required String bodyHtml,
}) async {
  final folder = Directory(p.join(root.path, folderName));
  final imagesDir = Directory(p.join(folder.path, 'images'));
  await imagesDir.create(recursive: true);
  await File(p.join(imagesDir.path, 'image_0001.png')).writeAsString('cover');
  await File(p.join(folder.path, 'manifest.json')).writeAsString('''
{
  "schemaVersion": 1,
  "createdAt": "2026-07-03T11:18:21.103974Z",
  "captureApp": "CaptureClipper",
  "captureMode": "clipboard-html",
  "title": "$manifestTitle",
  ${manifestAuthor == null ? '' : '"author": "$manifestAuthor",'}
  ${manifestShortCode == null ? '' : '"shortCode": "$manifestShortCode",'}
  "coverImage": "images/image_0001.png",
  "imageCount": 1,
  "htmlFile": "capture.html"
}
''');
  await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$manifestTitle</title>
    <meta name="generator" content="CaptureClipper">
  </head>
  <body>
    <section class="capture-session" data-app="CaptureClipper" data-mode="clipboard-html">
      <div class="clip clip-image" data-index="1" data-type="image">
        <img src="images/image_0001.png" alt="Captured image 1">
      </div>
      $bodyHtml
    </section>
  </body>
</html>
''');
  return folder;
}

const String _sspCaptureClipperBody = '''
      <div class="clip clip-text" data-index="2" data-type="text">
        <p>The Story of the Seer of Patmos, p. 3 (Stephen Nelson Haskell) AUTHOR’S PREFACE  SSP 3 The Story of the Seer of Patmos, p. 3.1 (Stephen Nelson Haskell) Prophecy is often considered dark and mysterious.  SSP 3.1 The Story of the Seer of Patmos, p. 3.2 (Stephen Nelson Haskell) God has given the book of Revelation a title.  SSP 3.2</p>
      </div>
      <div class="clip clip-text" data-index="3" data-type="text">
        <p>The Story of the Seer of Patmos, p. 11 (Stephen Nelson Haskell) CHAPTER I. THE SEER OF PATMOS.  SSP 11 The Story of the Seer of Patmos, p. 11.1 (Stephen Nelson Haskell) The Revelation opens with a blessing on the reader.  SSP 11.1</p>
      </div>
      <div class="clip clip-text" data-index="4" data-type="text">
        <p>The Story of the Seer of Patmos, p. 28 (Stephen Nelson Haskell) CHAPTER II. THE AUTHOR OF THE REVELATION.  SSP 28 The Story of the Seer of Patmos, p. 28.1 (Stephen Nelson Haskell) John was in the isle that is called Patmos.  SSP 28.1</p>
      </div>
''';

const String _fp187CaptureClipperBody = '''
      <div class="clip clip-text" data-index="2" data-type="text">
        <p>Fundamental Principles, p. 3 (General Conference of SDA) Fundamental Principles  FP1872 3  A DECLARATION OF THE Fundamental Principles TAUGHT AND PRACTICED -BY- THE SEVENTH-DAY ADVENTISTS. STEAM PRESS OF THE SEVENTH-DAY ADVENTIST PUBLISHING ASSOCIATION, BATTLE CREEK, MICH.: 1872.</p>
      </div>
      <div class="clip clip-text" data-index="3" data-type="text">
        <p>Fundamental Principles, p. 3 (General Conference of SDA) Fundamental Principles  FP1872 3 Fundamental Principles, p. 3.1 (General Conference of SDA) In presenting to the public this synopsis of our faith, we wish to have it distinctly understood.  FP1872 3.1 Fundamental Principles, p. 3.2 (General Conference of SDA) As Seventh-day Adventists we desire simply that our position shall be understood.  FP1872 3.2</p>
      </div>
''';

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

int _successfulCloudImportCount(Object report) {
  if (report is PioneerCapturedHtmlCloudFolderImportReport) {
    return report.entries.where((entry) => entry.imported).length;
  }
  if (report is PioneerCapturedHtmlFolderImportReport) {
    return report.files
        .where((file) => file.status == PioneerCapturedHtmlFileStatus.imported)
        .length;
  }
  if (report is PioneerImportBatchResult) {
    return report.importedCount;
  }
  throw ArgumentError('Unsupported report type: ${report.runtimeType}');
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
    await _clearCapturedHtmlImportState();
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
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

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
      expect(_successfulCloudImportCount(firstReport), 1);
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
      expect(firstFile.coverImported, isTrue);
      expect(firstFile.coverImagePath, p.join(folder.path, 'cover.jpg'));
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
      final importedCatalogItem = await LibraryCatalogService.instance
          .loadItemById(firstFile.libraryItemId!);
      expect(importedCatalogItem, isNotNull);
      expect(
        importedCatalogItem!.coverPath,
        p.join(
          libraryRootDir.path,
          'Graphics',
          'eLibraryCovers',
          '${firstFile.libraryItemId}.jpg',
        ),
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
    'uses the known catalog title when placeholder folder-code metadata is present',
    () async {
      const sourceUrl = 'https://example.invalid/dar';
      const authorName = 'Uriah Smith';
      const workId = 'daniel_and_the_revelation';
      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: 'SDP',
        abbreviation: 'DAR',
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening DAR 1 Intro text. DAR 1.1 First paragraph text. DAR 1.2</p>
    </div>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: folder.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredFolder(catalog: _darCatalog());

      expect(_successfulCloudImportCount(report), 1);
      final file = report.files.single;
      expect(file.title, 'Daniel and the Revelation');
      expect(file.author, authorName);
      expect(file.status, PioneerCapturedHtmlFileStatus.imported);

      final catalogItem = await LibraryCatalogService.instance.loadItemById(
        file.libraryItemId!,
      );
      expect(catalogItem, isNotNull);
      expect(catalogItem!.displayTitle, 'Daniel and the Revelation');
      expect(catalogItem.displayAuthor, authorName);
    },
  );

  test('imports SSP using the bundled catalog title and author', () async {
    final folder = await _createCaptureFolder(
      root: captureRootDir,
      title: 'SSP',
      abbreviation: 'SSP',
      workId: 'ssp_capture_test',
      sourceUrl: 'https://example.invalid/ssp',
      authorName: 'Unknown',
      bodyHtml: _sspImportHtml,
    );
    await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

    await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
      path: folder.path,
    );

    final report = await PioneerCapturedHtmlImportFolderService.instance
        .importConfiguredFolder(
          existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
        );

    expect(report.files.single.title, 'The Story of the Seer of Patmos');
    expect(report.files.single.author, 'S. N. Haskell');
    expect(report.files.single.libraryItemId, isNotNull);

    final catalogItem = await LibraryCatalogService.instance.loadItemById(
      report.files.single.libraryItemId!,
    );
    expect(catalogItem, isNotNull);
    expect(catalogItem!.displayTitle, 'The Story of the Seer of Patmos');
    expect(catalogItem.displayAuthor, 'S. N. Haskell');

    final navRows = await ELibraryDatabase.instance.database.then((db) {
      return db.query(
        'library_navigation_items',
        columns: const <String>[
          'label',
          'is_front_matter',
          'is_body_start',
          'sort_order',
        ],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [report.files.single.libraryItemId!],
        orderBy: 'sort_order ASC',
      );
    });
    expect(navRows, hasLength(4));
    final navLabels = navRows
        .map((row) => row['label']?.toString() ?? '')
        .toList(growable: false);
    expect(navLabels.first, 'AUTHORS PREFACE.');
    expect(navLabels.any((label) => label.contains('SEER OF PATMOS')), isTrue);
    expect(
      navLabels.any((label) => label.contains('CHRIST OF THE APOCALYPSE')),
      isTrue,
    );
    expect(navLabels.any((label) => label == 'SSP'), isFalse);
  });

  test(
    'imports a real CaptureClipper SSP folder as a structured captured HTML book',
    () async {
      final folder = await _createCaptureClipperFolder(
        root: captureRootDir,
        folderName: 'SSP',
        manifestTitle: 'SSP',
        manifestAuthor: 'Stephen Nelson Haskell',
        manifestShortCode: 'SSP',
        bodyHtml: _sspCaptureClipperBody,
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder();

      expect(_successfulCloudImportCount(report), 1);
      final entry = report.entries.single;
      expect(entry.title, 'The Story of the Seer of Patmos');
      expect(entry.author, 'S. N. Haskell');
      expect(entry.reason, 'Imported captured HTML book into eLibrary.db.');
      expect(entry.reason, isNot(contains('copied EGW text')));
      final itemId = entry.libraryItemId;
      expect(itemId, isNotNull);

      final db = await ELibraryDatabase.instance.database;
      final navRows = await db.query(
        'library_navigation_items',
        columns: const <String>['label'],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [itemId],
        orderBy: 'sort_order ASC',
      );
      final navLabels = navRows
          .map((row) => row['label']?.toString() ?? '')
          .toList(growable: false);
      expect(navLabels, hasLength(3));
      expect(navLabels[0], 'AUTHOR’S PREFACE.');
      expect(navLabels[1], 'CHAPTER I. THE SEER OF PATMOS.');
      expect(navLabels[2], 'CHAPTER II. THE AUTHOR OF THE REVELATION.');
      expect(navLabels.any((label) => label.contains('Chapter 1 — SSP')), isFalse);

      final textRows = await db.query(
        'library_text_blocks',
        columns: const <String>['plain_text'],
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      expect(textRows, hasLength(4));
      for (final row in textRows) {
        final text = row['plain_text']?.toString() ?? '';
        expect(text, isNot(contains('The Story of the Seer of Patmos, p.')));
        expect(text, isNot(contains('(Stephen Nelson Haskell)')));
      }

      final itemRow = (await db.query(
        'library_items',
        columns: const <String>['title', 'author'],
        where: 'id = ?',
        whereArgs: [itemId],
      )).single;
      expect(itemRow['title'], 'The Story of the Seer of Patmos');
      expect(itemRow['author'], 'S. N. Haskell');

      expect(entry.archivePath, isNotNull);
      expect(folder.existsSync(), isFalse);
      expect(Directory(entry.archivePath!).existsSync(), isTrue);
    },
  );

  test(
    'resolves FP187 through the catalog instead of importing a copied-range blob',
    () async {
      await _createCaptureClipperFolder(
        root: captureRootDir,
        folderName: 'FP187',
        manifestTitle: 'FP187',
        manifestShortCode: 'Psalm',
        bodyHtml: _fp187CaptureClipperBody,
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(archiveImportedFolders: false);

      expect(_successfulCloudImportCount(report), 1);
      final entry = report.entries.single;
      expect(entry.title, 'Fundamental Principles of Seventh-day Adventists');
      expect(entry.author, 'General Conference of SDA');
      expect(entry.reason, 'Imported captured HTML book into eLibrary.db.');
      final itemId = entry.libraryItemId;
      expect(itemId, isNotNull);

      final db = await ELibraryDatabase.instance.database;
      final itemRow = (await db.query(
        'library_items',
        columns: const <String>['title', 'author'],
        where: 'id = ?',
        whereArgs: [itemId],
      )).single;
      expect(itemRow['title'], 'Fundamental Principles of Seventh-day Adventists');
      expect(itemRow['author'], 'General Conference of SDA');

      final navRows = await db.query(
        'library_navigation_items',
        columns: const <String>['label'],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [itemId],
      );
      expect(navRows, hasLength(1));
      expect(navRows.single['label'], 'FUNDAMENTAL PRINCIPLES.');

      final textRows = await db.query(
        'library_text_blocks',
        columns: const <String>['plain_text'],
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      expect(textRows, hasLength(2));
      for (final row in textRows) {
        final text = row['plain_text']?.toString() ?? '';
        expect(text, isNot(contains('Fundamental Principles, p.')));
        expect(text, isNot(contains('(General Conference of SDA)')));
        expect(text, isNot(contains('STEAM PRESS')));
      }
    },
  );

  test(
    'an import that needs review keeps the source folder in place',
    () async {
      final folder = await _createCaptureClipperFolder(
        root: captureRootDir,
        folderName: 'ZZX',
        manifestTitle: 'ZZX',
        bodyHtml: '''
      <div class="clip clip-text" data-index="2" data-type="text">
        <p>Sample Conflict Book, p. 5 (Test Author) CHAPTER I. CONFLICTS.  ZZX 5 Sample Conflict Book, p. 5.1 (Test Author) First version of the text.  ZZX 5.1 Sample Conflict Book, p. 5.1 (Test Author) A different second version.  ZZX 5.1</p>
      </div>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder();

      final entry = report.entries.single;
      expect(entry.importStatus, PioneerImportWorkStatus.imported);
      expect(entry.reason, contains('need review'));
      expect(entry.archivePath, isNull);
      expect(
        entry.archiveError,
        'Import needs review; the source folder was left in place.',
      );
      expect(folder.existsSync(), isTrue);
    },
  );

  test(
    'reimports SSP when only a soft-deleted stored row remains and leaves the source folder in place',
    () async {
      final folder = await _createCaptureFolder(
        root: captureRootDir,
        folderName: 'SSP',
        title: 'SSP',
        abbreviation: 'SSP',
        workId: 'ssp_soft_deleted_reimport_test',
        sourceUrl: 'https://example.invalid/ssp-soft-delete',
        authorName: 'Unknown',
        bodyHtml: _sspImportHtml,
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final service = PioneerCapturedHtmlImportFolderService.instance;
      final firstReport = await service.importConfiguredCloudFolder(
        archiveImportedFolders: false,
        existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
      );
      expect(_successfulCloudImportCount(firstReport), 1);
      final itemId = firstReport.entries.single.libraryItemId;
      expect(itemId, isNotNull);

      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        <String, Object?>{
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      final refreshedAvailability =
          await PioneerCapturedHtmlImportAvailabilityService.instance.refresh(
            catalog: await PioneerSourceCatalog.load(),
          );
      expect(refreshedAvailability.availableCount, greaterThanOrEqualTo(1));

      final secondReport = await service.importConfiguredCloudFolder(
        selectedFolderPaths: [folder.path],
        archiveImportedFolders: false,
      );

      expect(_successfulCloudImportCount(secondReport), 1);
      expect(
        secondReport.entries.single.importStatus,
        PioneerImportWorkStatus.imported,
      );
      expect(
        secondReport.entries.single.title,
        'The Story of the Seer of Patmos',
      );
      expect(secondReport.entries.single.author, 'S. N. Haskell');

      final repairedItem = await LibraryCatalogService.instance.loadItemById(
        secondReport.entries.single.libraryItemId!,
      );
      expect(repairedItem, isNotNull);
      expect(repairedItem!.displayTitle, 'The Story of the Seer of Patmos');
      expect(repairedItem.displayAuthor, 'S. N. Haskell');
      expect(folder.existsSync(), isTrue);
    },
  );

  test(
    'repairs a stale imported SSP book from source without archiving the source folder',
    () async {
      final folder = await _createCaptureFolder(
        root: captureRootDir,
        folderName: 'SSP',
        title: 'SSP',
        abbreviation: 'SSP',
        workId: 'ssp_repair_test',
        sourceUrl: 'https://example.invalid/ssp-repair',
        authorName: 'Unknown',
        bodyHtml: _sspImportHtml,
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final service = PioneerCapturedHtmlImportFolderService.instance;
      final initialReport = await service.importConfiguredCloudFolder(
        archiveImportedFolders: false,
        existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
      );
      expect(
        initialReport.entries.single.importStatus,
        anyOf(
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.skippedExisting,
        ),
      );
      expect(initialReport.archivedCount, 0);
      final itemId = initialReport.entries.single.libraryItemId;
      expect(itemId, isNotNull);
      final normalizedItemId = itemId!;

      expect(folder.existsSync(), isTrue);

      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        <String, Object?>{
          'title': 'SSP',
          'author': 'Unknown',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [normalizedItemId],
      );
      await db.update(
        'library_navigation_items',
        <String, Object?>{'label': 'Chapter 1 — SSP'},
        where: 'library_item_id = ?',
        whereArgs: [normalizedItemId],
      );

      final repairedReport = await service.repairImportedCaptureClipperBook(
        libraryItemId: normalizedItemId,
      );
      expect(repairedReport, isNotNull);
      expect(_successfulCloudImportCount(repairedReport!), 1);
      expect(repairedReport.archivedCount, 0);
      expect(repairedReport.failedCount, 0);
      expect(folder.existsSync(), isTrue);

      final repairedItem = await LibraryCatalogService.instance.loadItemById(
        normalizedItemId,
      );
      expect(repairedItem, isNotNull);
      expect(repairedItem!.displayTitle, 'The Story of the Seer of Patmos');
      expect(repairedItem.displayAuthor, 'S. N. Haskell');

      expect(
        await _countRows(
          db,
          'library_items',
          where: 'id = ?',
          whereArgs: [normalizedItemId],
        ),
        1,
      );
      expect(
        await _countRows(
          db,
          'library_navigation_items',
          where: 'library_item_id = ?',
          whereArgs: [normalizedItemId],
        ),
        greaterThanOrEqualTo(4),
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [normalizedItemId],
        ),
        greaterThanOrEqualTo(3),
      );
      final navRows = await db.query(
        'library_navigation_items',
        columns: const <String>['label'],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [normalizedItemId],
        orderBy: 'sort_order ASC',
      );
      final navLabels = navRows
          .map((row) => row['label']?.toString() ?? '')
          .toList(growable: false);
      expect(navLabels.first, 'AUTHORS PREFACE.');
      expect(
        navLabels.any((label) => label.contains('SEER OF PATMOS')),
        isTrue,
      );
      expect(
        navLabels.any((label) => label.contains('CHRIST OF THE APOCALYPSE')),
        isTrue,
      );
      expect(navLabels.any((label) => label == 'SSP'), isFalse);

      final refreshedAvailability =
          await PioneerCapturedHtmlImportAvailabilityService.instance.refresh(
            catalog: await PioneerSourceCatalog.load(),
          );
      expect(refreshedAvailability.availableCount, 0);
    },
  );

  test(
    'drops imported captured HTML rows without touching the source folder',
    () async {
      final sourceFolder = await Directory.systemTemp.createTemp(
        'ssp_drop_source_',
      );
      final sourceFile = File(p.join(sourceFolder.path, 'capture.html'));
      await sourceFile.writeAsString('source folder stays put');

      final work = PioneerSourceWork(
        id: 'the_story_of_the_seer_of_patmos',
        authorId: 'sn_haskell',
        authorName: 'S. N. Haskell',
        sourceFamily: 'Pioneer',
        title: 'The Story of the Seer of Patmos',
        abbreviation: 'SSP',
        group: 'Pioneer Authors',
        subgroup: 'Prophecy',
        availability: PioneerSourceAvailability.sourceNeeded,
        verified: false,
        catalogImportable: false,
        sourceType: 'html',
        sourceUrl: null,
        collectionUrl: null,
        captureUrl: null,
        readerUrl: null,
        directFileUrl: null,
        directFileType: null,
        sourceLabel: 'Pioneer',
        notes: 'Requires manual verification before import.',
      );
      final service = PioneerTextImportService();
      final importResult = await service.importFromCapturedHtml(
        work: work,
        html: _sspImportHtml,
        sourceUrl: 'https://example.invalid/ssp',
        sourceLabel: 'CaptureClipper',
        existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
      );

      expect(_successfulCloudImportCount(importResult), 1);

      final db = await ELibraryDatabase.instance.database;
      final itemId = work.stableLibraryItemId;
      await db.insert('elibrary_markups', <String, Object?>{
        'library_item_id': itemId,
        'epub_href': 'captured/ssp.xhtml',
        'start_block_index': 1,
        'start_char_offset': 0,
        'end_block_index': 1,
        'end_char_offset': 12,
        'selected_text_snapshot': 'source folder stays put',
        'markup_type': 'highlight',
        'color': '#F7D87D',
        'note_text': null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_at': null,
      });

      expect(
        await _countRows(
          db,
          'library_items',
          where: 'id = ?',
          whereArgs: [itemId],
        ),
        1,
      );
      expect(
        await _countRows(
          db,
          'library_navigation_items',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        greaterThan(0),
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        greaterThan(0),
      );
      expect(
        await _countRows(
          db,
          'library_item_contributors',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        greaterThan(0),
      );
      expect(
        await _countRows(
          db,
          'elibrary_markups',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        1,
      );

      final removed = await service.removeImportedLibraryItem(itemId);
      expect(removed, isTrue);
      expect(await LibraryCatalogService.instance.loadItemById(itemId), isNull);
      expect(
        await _countRows(
          db,
          'library_items',
          where: 'id = ?',
          whereArgs: [itemId],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_navigation_items',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_item_contributors',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'elibrary_markups',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        0,
      );
      expect(sourceFile.existsSync(), isTrue);

      await sourceFolder.delete(recursive: true);
    },
  );

  test(
    'imports configured cloud root folders and archives the source folder after verification',
    () async {
      const title = 'Cloud Import Test Book';
      const abbreviation = 'DAR';
      const workId = 'dar_test';
      const sourceUrl = 'https://example.invalid/dar';
      const authorName = 'Uriah Smith';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml:
            '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening $abbreviation 1 Intro text. $abbreviation 1.1 First paragraph text. $abbreviation 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — Section Two $abbreviation 2.1 Second paragraph text.</p>
    </div>
''',
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');
      await File(
        p.join(folder.path, 'images', 'image_0001.png'),
      ).create(recursive: true);

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            nowProvider: () => DateTime(2026, 7, 1),
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );

      expect(report.rootPath, captureRootDir.path);
      final cloudStatus = report.entries.single.importStatus;
      expect(
        cloudStatus,
        anyOf(
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.skippedExisting,
        ),
      );
      if (cloudStatus == PioneerImportWorkStatus.skippedExisting) {
        expect(report.archivedCount, 0);
        expect(folder.existsSync(), isTrue);
        return;
      }
      expect(report.archivedCount, 1);
      expect(report.skippedCount, 0);
      expect(report.failedCount, 0);

      final entry = report.entries.single;
      expect(entry.imported, isTrue);
      expect(entry.archived, isTrue);
      expect(entry.coverImported, isTrue);
      expect(entry.chapterCount, greaterThanOrEqualTo(2));
      expect(entry.firstChapterLabel, isNotNull);
      expect(entry.lastChapterLabel, isNotNull);
      expect(entry.archiveError, isNull);
      expect(
        entry.archivePath,
        p.join(
          captureRootDir.path,
          'Backup',
          '${p.basename(folder.path)}07-01-2026',
        ),
      );

      expect(folder.existsSync(), isFalse);
      final archivedFolder = Directory(
        p.join(
          captureRootDir.path,
          'Backup',
          '${p.basename(folder.path)}07-01-2026',
        ),
      );
      expect(archivedFolder.existsSync(), isTrue);
      expect(
        File(p.join(archivedFolder.path, 'capture.html')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(archivedFolder.path, 'cover.jpg')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(archivedFolder.path, 'images', 'image_0001.png'),
        ).existsSync(),
        isTrue,
      );

      final catalogItem = await LibraryCatalogService.instance.loadItemById(
        entry.libraryItemId!,
      );
      expect(catalogItem, isNotNull);
      expect(catalogItem!.displayTitle, title);
      expect(catalogItem.displayAuthor, authorName);
      expect(
        catalogItem.coverPath,
        p.join(
          libraryRootDir.path,
          'Graphics',
          'eLibraryCovers',
          '${entry.libraryItemId}.jpg',
        ),
      );
    },
  );

  test(
    'imports Chapter 33 fixture with cover art, chapter title, and preserved page refs',
    () async {
      const title = 'The Cross and Its Shadow';
      const abbreviation = 'CIS';
      const workId = 'cis_test_chapter_33';
      const sourceUrl = 'https://example.invalid/cis-chapter-33';
      const authorName = 'Uriah Smith';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml:
            '''
    <div class="clip clip-text">
      <p>Chapter 33-The Jubilee
$abbreviation 247
THE jubilee the climax of a series of sabbatical institutions.
$abbreviation 247.1
After the children of Israel entered the promised land, God commanded that every seventh year should be a Sabbath of rest unto the land.
$abbreviation 247.2</p>
    </div>
''',
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            nowProvider: () => DateTime(2026, 7, 1),
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );

      final chapterStatus = report.entries.single.importStatus;
      expect(
        chapterStatus,
        anyOf(
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.skippedExisting,
        ),
      );
      if (chapterStatus == PioneerImportWorkStatus.skippedExisting) {
        expect(report.archivedCount, 0);
        expect(folder.existsSync(), isTrue);
        return;
      }
      expect(report.archivedCount, 1);
      expect(report.failedCount, 0);

      final entry = report.entries.single;
      expect(entry.coverImported, isTrue);
      expect(entry.title, 'The Cross and Its Shadow');
      expect(entry.author, authorName);
      expect(entry.firstChapterLabel, 'Chapter 33 — The Jubilee');
      expect(entry.lastChapterLabel, 'Chapter 33 — The Jubilee');

      final catalogItem = await LibraryCatalogService.instance.loadItemById(
        entry.libraryItemId!,
      );
      expect(catalogItem, isNotNull);
      expect(catalogItem!.displayTitle, title);
      expect(catalogItem.displayAuthor, authorName);
      expect(
        catalogItem.coverPath,
        p.join(
          libraryRootDir.path,
          'Graphics',
          'eLibraryCovers',
          '${entry.libraryItemId}.jpg',
        ),
      );

      final db = await ELibraryDatabase.instance.database;
      final navRows = await db.query(
        'library_navigation_items',
        where: 'library_item_id = ?',
        whereArgs: [entry.libraryItemId],
      );
      expect(navRows, hasLength(1));
      expect(navRows.single['label'], 'Chapter 33 — The Jubilee');

      final textRows = await db.query(
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [entry.libraryItemId],
        orderBy: 'paragraph_index ASC',
      );
      expect(textRows, hasLength(2));
      expect(textRows.first['plain_text'], contains('THE jubilee'));
      expect(textRows.last['plain_text'], contains('children of Israel'));

      final refRows = await db.query(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [entry.libraryItemId],
        orderBy: 'paragraph_index ASC',
      );
      expect(refRows, hasLength(3));
      expect(refRows[0]['ref_code'], 'CIS 247');
      expect((refRows[0]['paragraph_index'] as num).toInt(), lessThan(0));
      expect((refRows[0]['paragraph_on_page'] as num).toInt(), 0);
      expect(refRows[1]['ref_code'], 'CIS 247.1');
      expect((refRows[1]['paragraph_index'] as num).toInt(), 1);
      expect((refRows[1]['paragraph_on_page'] as num).toInt(), 1);
      expect(refRows[2]['ref_code'], 'CIS 247.2');
      expect((refRows[2]['paragraph_index'] as num).toInt(), 2);
      expect((refRows[2]['paragraph_on_page'] as num).toInt(), 2);

      expect(folder.existsSync(), isFalse);
      expect(
        Directory(
          p.join(
            captureRootDir.path,
            'Backup',
            'cis_test_chapter_3307-01-2026',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(
            captureRootDir.path,
            'Backup',
            'cis_test_chapter_3307-01-2026',
            'cover.jpg',
          ),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'repairs an existing bad CaptureClipper import in place without duplicating it',
    () async {
      const title = 'Repair Import Test Book';
      const workId = 'cis_test_repair';
      const sourceUrl = 'https://example.invalid/cis-repair';
      const authorName = 'Uriah Smith';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: workId,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 33-The Jubilee
CIS 247
THE jubilee the climax of a series of sabbatical institutions.
CIS 247.1
After the children of Israel entered the promised land, God commanded that every seventh year should be a Sabbath of rest unto the land.
CIS 247.2</p>
    </div>
''',
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final seededReport = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredFolder(
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );
      expect(_successfulCloudImportCount(seededReport), 1);
      final seededItemId = seededReport.files.single.libraryItemId;
      expect(seededItemId, isNotNull);
      final seededId = seededItemId!;

      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        <String, Object?>{
          'title': 'Section 1 The...',
          'author': 'Unknown',
          'cover_path': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [seededId],
      );
      await db.update(
        'library_navigation_items',
        <String, Object?>{'label': 'Chapter 0 — Section 1 — The Sanctuary'},
        where: 'library_item_id = ?',
        whereArgs: [seededId],
      );
      await db.update(
        'library_text_blocks',
        <String, Object?>{
          'plain_text':
              'Section 1-The Sanctuary The Heavenly Sanctuary There is a house in heaven built...',
        },
        where: 'library_item_id = ?',
        whereArgs: [seededId],
      );
      await db.delete(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [seededId],
      );

      final repairReport = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            nowProvider: () => DateTime(2026, 7, 1),
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );

      expect(repairReport.entries, hasLength(1));
      expect(
        repairReport.entries.single.importStatus,
        anyOf(
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.skippedExisting,
        ),
      );
      expect(repairReport.archivedCount, 0);
      expect(repairReport.failedCount, 0);

      final entry = repairReport.entries.single;
      expect(entry.createdNew, isFalse);
      expect(entry.updatedExisting, isFalse);
      expect(entry.libraryItemId, seededId);
      expect(entry.reason, contains('Repaired existing CaptureClipper item'));

      final repairedItem = await LibraryCatalogService.instance.loadItemById(
        seededId,
      );
      expect(repairedItem, isNotNull);
      expect(repairedItem!.displayTitle, startsWith('Section 1'));
      expect(repairedItem.displayAuthor, isNotEmpty);
      expect(repairedItem.coverPath, isNull);

      final navRows = await db.query(
        'library_navigation_items',
        where: 'library_item_id = ?',
        whereArgs: [seededId],
      );
      expect(navRows, hasLength(1));
      expect(navRows.single['label'], 'Chapter 0 — Section 1 — The Sanctuary');

      final textRows = await db.query(
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [seededId],
        orderBy: 'paragraph_index ASC',
      );
      expect(textRows, hasLength(1));
      expect(
        textRows.single['plain_text'],
        contains('Section 1-The Sanctuary'),
      );

      final refRows = await db.query(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [seededId],
        orderBy: 'paragraph_index ASC',
      );
      expect(refRows, isEmpty);

      expect(folder.existsSync(), isTrue);
      expect(
        Directory(
          p.join(captureRootDir.path, 'Backup', 'CIS07-01-2026'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(captureRootDir.path, 'Backup', 'CIS07-01-2026', 'cover.jpg'),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'leaves a matching already-imported bad item unchanged when repair is attempted',
    () async {
      const title = 'The Cross and Its Shadow';
      const authorName = 'S. N. Haskell';
      const workId = 'the_cross_and_its_shadow';
      const sourceUrl = 'https://example.invalid/cis-invalid';

      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: 'CIS',
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml: '',
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final db = await ELibraryDatabase.instance.database;
      final itemId =
          'library_item_research_pioneer_s_n_haskell_the_cross_and_its_shadow';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': itemId,
        'title': 'Section 1 The...',
        'author': 'Unknown',
        'file_name': 'capture.html',
        'relative_path':
            'TextCaptures/Research/Pioneer Authors/s_n_haskell/$workId/capture.html',
        'source_type': 'egw_html_capture',
        'source_site': 'egwwritings.org',
        'source_url': sourceUrl,
        'cover_path': null,
        'created_at': now,
        'updated_at': now,
        'device_id': 'device_test',
        'revision': 1,
        'sync_status': 'pending',
      });
      await db.insert('library_navigation_items', <String, Object?>{
        'id': 'nav_${itemId}_1',
        'library_item_id': itemId,
        'parent_id': null,
        'label': 'Chapter 0 — Section 1 — The Sanctuary',
        'href': 'captured/cis/capture.html',
        'anchor_id': null,
        'spine_index': 1,
        'sort_order': 1,
        'depth': 0,
        'nav_type': 'toc',
        'content_kind': 'chapter',
        'is_front_matter': 0,
        'is_body_start': 0,
        'body_order': 1,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'device_id': 'device_test',
        'revision': 1,
        'sync_status': 'pending',
      });
      await db.insert('library_text_blocks', <String, Object?>{
        'library_item_id': itemId,
        'epub_href': 'captured/cis/capture.html',
        'spine_index': 1,
        'paragraph_index': 1,
        'paragraph_on_section': 1,
        'section_title': 'Chapter 0 — Section 1 — The Sanctuary',
        'plain_text':
            'Section 1-The Sanctuary The Heavenly Sanctuary There is a house in heaven built...',
        'created_at': now,
        'updated_at': now,
      });

      final repairReport = await PioneerCapturedHtmlImportFolderService.instance
          .repairBrokenCaptureClipperItems(
            nowProvider: () => DateTime(2026, 7, 1),
          );

      expect(repairReport.entries, isEmpty);
      expect(repairReport.repairedCount, 0);
      expect(repairReport.failedCount, 0);

      final repairedItem = await LibraryCatalogService.instance.loadItemById(
        itemId,
      );
      expect(repairedItem, isNotNull);
      expect(repairedItem!.displayTitle, 'Section 1 The...');
      expect(repairedItem.displayAuthor, 'Unknown');
      expect(repairedItem.coverPath, isNull);
      expect(folder.existsSync(), isTrue);
    },
  );

  test(
    'archive collisions append a numeric suffix and Backup folders are ignored',
    () async {
      const title = 'Archive Collision Test Book';
      const abbreviation = 'LOF';
      const workId = 'lof_test';
      const sourceUrl = 'https://example.invalid/lof';
      const authorName = 'A. T. Jones';

      await Directory(
        p.join(captureRootDir.path, 'Backup', 'lof_test07-01-2026'),
      ).create(recursive: true);
      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: title,
        abbreviation: abbreviation,
        workId: workId,
        sourceUrl: sourceUrl,
        authorName: authorName,
        bodyHtml:
            '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening $abbreviation 1 Intro text. $abbreviation 1.1 First paragraph text. $abbreviation 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — Section Two $abbreviation 2.1 Second paragraph text.</p>
    </div>
''',
      );

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            nowProvider: () => DateTime(2026, 7, 1),
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );

      final archiveStatus = report.entries.single.importStatus;
      expect(
        archiveStatus,
        anyOf(
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.skippedExisting,
        ),
      );
      if (archiveStatus == PioneerImportWorkStatus.skippedExisting) {
        expect(report.archivedCount, 0);
        expect(folder.existsSync(), isTrue);
      } else {
        expect(
          report.entries.single.archivePath,
          p.join(captureRootDir.path, 'Backup', 'lof_test07-01-2026-2'),
        );
        expect(
          Directory(
            p.join(captureRootDir.path, 'Backup', 'lof_test07-01-2026-2'),
          ).existsSync(),
          isTrue,
        );
        expect(folder.existsSync(), isFalse);
      }

      final secondPass = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(nowProvider: () => DateTime(2026, 7, 1));
      expect(secondPass.importedCount, 0);
      expect(secondPass.archivedCount, 0);
      expect(secondPass.skippedCount, 0);
      expect(secondPass.failedCount, 0);
      expect(secondPass.entries, isEmpty);
    },
  );

  test('failed cloud import leaves the source folder in place', () async {
    const title = 'Failure Test Book';
    const workId = 'FAIL';
    const sourceUrl = 'https://example.invalid/fail';
    const authorName = 'E. G. White';

    final folder = await _createCaptureFolder(
      root: captureRootDir,
      title: title,
      abbreviation: workId,
      workId: workId,
      sourceUrl: sourceUrl,
      authorName: authorName,
      bodyHtml:
          '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening $workId 1 Intro text. $workId 1.1 First paragraph text. $workId 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — Section Two $workId 2.1 Second paragraph text.</p>
    </div>
''',
    );

    await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
      path: captureRootDir.path,
    );

    final report = await PioneerCapturedHtmlImportFolderService.instance
        .importConfiguredCloudFolder(
          importPreviews: (previews) async {
            final preview = previews.first;
            final work = preview.importWork;
            return PioneerImportBatchResult(
              workResults: [
                PioneerImportWorkResult(
                  work: work,
                  status: PioneerImportWorkStatus.failed,
                  stage: 'failed',
                  sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
                  reason: 'Simulated cloud import failure.',
                  libraryItemId: work.stableLibraryItemId,
                  sourceType: work.sourceType,
                  insertedLibraryItems: 0,
                  insertedNavigationItems: 0,
                  insertedTextBlocks: 0,
                  skippedExisting: false,
                  refCodeHandlingSummary: 'Simulated failure.',
                  detail: 'Simulated cloud import failure.',
                  exceptionType: 'SimulatedFailure',
                  httpStatusCode: null,
                  contentType: 'text/html',
                  downloadedByteCount: preview.extractedText?.length,
                  parsedSectionCount: 0,
                  parsedParagraphCount: 0,
                  requiresManualVerification: false,
                  manualVerificationHint: null,
                  textCaptureAvailable: true,
                  preferredImportPreference:
                      PioneerSourcePathPreference.textCapture,
                  qualityValidationSummary: 'Simulated failure.',
                ),
              ],
            );
          },
        );

    expect(report.failedCount, 1);
    expect(report.archivedCount, 0);
    expect(folder.existsSync(), isTrue);
    expect(
      Directory(p.join(captureRootDir.path, 'Backup')).existsSync(),
      isFalse,
    );
  });

  test('archive move failures leave the source folder in place', () async {
    const title = 'Archive Failure Test Book';
    const abbreviation = 'ARCHIVE_FAIL';
    const workId = 'archive_fail_test';
    const sourceUrl = 'https://example.invalid/archive-fail';
    const authorName = 'E. G. White';

    final folder = await _createCaptureFolder(
      root: captureRootDir,
      title: title,
      abbreviation: abbreviation,
      workId: workId,
      sourceUrl: sourceUrl,
      authorName: authorName,
      bodyHtml:
          '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening $abbreviation 1 Intro text. $abbreviation 1.1 First paragraph text. $abbreviation 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — Section Two $abbreviation 2.1 Second paragraph text.</p>
    </div>
''',
    );
    await File(
      p.join(captureRootDir.path, 'Backup'),
    ).writeAsString('blocked by file');

    await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
      path: captureRootDir.path,
    );

    final report = await PioneerCapturedHtmlImportFolderService.instance
        .importConfiguredCloudFolder(
          nowProvider: () => DateTime(2026, 7, 1),
          existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
        );

    expect(
      report.entries.single.importStatus,
      anyOf(
        PioneerImportWorkStatus.imported,
        PioneerImportWorkStatus.skippedExisting,
      ),
    );
    expect(report.archivedCount, 0);
    expect(report.failedCount, 0);
    expect(report.entries.single.archiveError, isNotNull);
    expect(folder.existsSync(), isTrue);
    expect(File(p.join(captureRootDir.path, 'Backup')).existsSync(), isTrue);
    expect(
      Directory(
        p.join(captureRootDir.path, 'Backup', 'ARCHIVE_FAIL07-01-2026'),
      ).existsSync(),
      isFalse,
    );
  });

  test('persists needsCleanup review entries with warning text', () async {
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
    expect(settings['pioneer_captured_html_review_entries'], isA<List>());
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
  });

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
      expect(catalogItems.where((item) => item.displayTitle == title), isEmpty);
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
      expect(_successfulCloudImportCount(report), 1);

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

  test(
    'discovers ready CaptureClipper folders without touching source folders',
    () async {
      final readyFolder = await _createCaptureFolder(
        root: captureRootDir,
        title: 'SDP',
        abbreviation: 'DAR',
        workId: 'DAR',
        sourceUrl: 'https://example.invalid/dar-ready',
        authorName: 'Uriah Smith',
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening DAR 1 Intro text. DAR 1.1 First paragraph text. DAR 1.2</p>
    </div>
''',
      );
      await Directory(
        p.join(captureRootDir.path, 'Backup'),
      ).create(recursive: true);
      await Directory(
        p.join(captureRootDir.path, 'Backup', 'Archive'),
      ).create(recursive: true);
      await File(
        p.join(captureRootDir.path, 'Backup', 'Archive', 'ignored.html'),
      ).writeAsString('<html></html>');
      await Directory(
        p.join(captureRootDir.path, 'Imported'),
      ).create(recursive: true);
      await Directory(
        p.join(captureRootDir.path, 'Archive'),
      ).create(recursive: true);
      await Directory(
        p.join(captureRootDir.path, 'Scanned', 'Scanned'),
      ).create(recursive: true);

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final report = await PioneerCapturedHtmlImportFolderService.instance
          .discoverConfiguredCloudFolderImports();

      expect(report.hasAvailableImports, isTrue);
      expect(report.availableCount, 1);
      expect(report.imports.single.folderName, 'DAR');
      expect(report.imports.single.title, 'Daniel and the Revelation');
      expect(report.imports.single.author, 'Uriah Smith');
      expect(readyFolder.existsSync(), isTrue);
      expect(
        Directory(p.join(captureRootDir.path, 'Backup')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(captureRootDir.path, 'Imported')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(captureRootDir.path, 'Archive')).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          p.join(captureRootDir.path, 'Scanned', 'Scanned'),
        ).existsSync(),
        isTrue,
      );
      expect(report.rootPath, captureRootDir.path);
    },
  );
}
