import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';
import 'package:studybible2/features/utilities/data/egw_copied_range_parser.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_page_inspection.dart';
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

Uint8List _zipWithSingleEpubEntry({
  required String fileName,
  required List<int> epubBytes,
}) {
  final archive = Archive()
    ..addFile(ArchiveFile(fileName, epubBytes.length, epubBytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _zipWithEpubEntries(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _epubBytes() {
  final containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml" />
  </rootfiles>
</container>
''';
  final opfXml = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Daniel and the Revelation</dc:title>
    <dc:creator>Uriah Smith</dc:creator>
    <dc:publisher>Adventist Pioneer Library</dc:publisher>
    <meta name="cover" content="cover-image" />
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
    <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg" />
    <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml" properties="cover-image" />
    <item id="main" href="The_Daniel_and_Revelation_01t_%28ebook%29.xhtml" media-type="application/xhtml+xml" />
  </manifest>
  <spine>
    <itemref idref="main" />
  </spine>
</package>
''';
  final navXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Contents</title></head>
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="The_Daniel_and_Revelation_01t_%28ebook%29.xhtml#preface">Preface</a></li>
        <li><a href="The_Daniel_and_Revelation_01t_%28ebook%29.xhtml#chapter-1">Chapter 1 - Daniel in Captivity</a></li>
      </ol>
    </nav>
  </body>
</html>
''';
  final coverXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Cover</title></head>
  <body>
    <div><img src="images/cover.jpg" alt="Daniel and the Revelation cover" /></div>
  </body>
</html>
''';
  final mainXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Contents</title></head>
  <body>
    <p class="Normal">© 2016 Adventist Pioneer Library</p>
    <p class="Normal">37457 Jasper Lowell Rd</p>
    <p class="Normal">Jasper, OR, 97438, USA</p>
    <p class="Normal">+1 (877) 585-1111</p>
    <p class="Normal">www.APLib.org</p>
    <p class="Normal">Originally published in 1897 by the Review and Herald Publishing Company.</p>
    <p class="Normal">The original Table of Contents contained brief descriptions for the chapters.</p>
    <p class="Normal">Published in the USA</p>
    <p class="Normal">July, 2016</p>
    <p class="Normal">ISBN: 978-1-61455-045-7</p>
    <div class="Header-Main" id="contents">Contents</div>
    <p class="TOC-text-level-0-Section">Contents</p>
    <div class="Header-Main" id="preface">Preface</div>
    <p class="Normal">A brief preface frames the book. [4]</p>
    <div class="Header-Main" id="chapter-1">Chapter 1 - Daniel in Captivity</div>
    <p class="Normal">Daniel and the Revelation opens in the days of Babylon. [5]</p>
    <p class="Normal-Noindent">The prophecy of Daniel begins with captivity and hope.</p>
    <div class="Heading-2">Chapter 2 - The Great Image</div>
    <p class="Normal">The great image is the next major subject in the book. [6]</p>
    <p class="Normal">Its metals and kingdoms are discussed in careful sequence.</p>
  </body>
</html>
''';

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerXml.length,
        containerXml.codeUnits,
      ),
    )
    ..addFile(ArchiveFile('OEBPS/content.opf', opfXml.length, opfXml.codeUnits))
    ..addFile(
      ArchiveFile('OEBPS/nav.xhtml', navXhtml.length, navXhtml.codeUnits),
    )
    ..addFile(
      ArchiveFile('OEBPS/cover.xhtml', coverXhtml.length, coverXhtml.codeUnits),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/The_Daniel_and_Revelation_01t_(ebook).xhtml',
        mainXhtml.length,
        mainXhtml.codeUnits,
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

PioneerSourceWork _work({
  required String id,
  required String authorId,
  required String authorName,
  required String title,
  required String abbreviation,
  required String sourceType,
  required String sourceUrl,
  String? sourceLabel,
  PioneerSourceAvailability availability = PioneerSourceAvailability.available,
  bool verified = true,
  bool catalogImportable = true,
  String? collectionUrl,
  String? directFileUrl,
  String? directFileType,
  List<PioneerSourceCandidate> sourceCandidates = const [],
}) {
  return PioneerSourceWork(
    id: id,
    authorId: authorId,
    authorName: authorName,
    sourceFamily: 'Pioneer',
    title: title,
    abbreviation: abbreviation,
    group: 'Pioneer Authors',
    subgroup: 'Prophecy',
    availability: availability,
    verified: verified,
    catalogImportable: catalogImportable,
    sourceType: sourceType,
    sourceUrl: sourceUrl,
    collectionUrl: collectionUrl,
    captureUrl: sourceUrl,
    readerUrl: sourceUrl,
    directFileUrl: directFileUrl,
    directFileType: directFileType,
    sourceLabel: sourceLabel,
    notes: null,
    sourceCandidates: sourceCandidates,
  );
}

PioneerSourceWork _sourceNeededWork({
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
}

PioneerImportDocument _fakeDocumentFor(PioneerSourceWork work) {
  switch (work.id) {
    case 'the_united_states_in_the_light_of_prophecy':
      return PioneerImportDocument(
        title: work.title,
        sections: [
          PioneerImportSection(
            href: 'https://example.com/uslp/ch1',
            title: 'Chapter 1',
            paragraphs: const <String>[
              'The United States in the Light of Prophecy explains history.',
              'The United States and prophecy appear together here.',
            ],
            spineIndex: 1,
          ),
        ],
      );
    case 'daniel_and_the_revelation':
      return PioneerImportDocument(
        title: work.title,
        sections: [
          PioneerImportSection(
            href: 'https://egwwritings.org/read?panels=p1297.2&index=1',
            title: 'Chapter 1 - Daniel in Captivity',
            paragraphs: const <String>[
              'Daniel and the Revelation opens with Daniel in captivity.',
              'The narrative introduces the prophetic sequence at the start.',
            ],
            spineIndex: 1,
          ),
        ],
      );
    default:
      throw StateError('Unexpected work requested in fake parser: ${work.id}');
  }
}

Future<Directory> _createCaptureFixtureRoot({
  required Directory root,
  required String folderName,
  required String title,
  required String abbreviation,
  required String workId,
  required String authorName,
  required String bodyHtml,
  List<String> contributorNames = const <String>[],
}) async {
  final folder = Directory(p.join(root.path, folderName));
  await folder.create(recursive: true);
  final imagesDir = Directory(p.join(folder.path, 'images'));
  await imagesDir.create(recursive: true);
  await File(p.join(imagesDir.path, 'image_0001.png')).writeAsString('cover');

  final contributors = <Map<String, Object?>>[
    {'name': authorName, 'role': 'author', 'sort_order': 1, 'primary': true},
    for (var index = 0; index < contributorNames.length; index += 1)
      {
        'name': contributorNames[index],
        'role': 'author',
        'sort_order': index + 2,
        'primary': false,
      },
  ];

  await File(p.join(folder.path, 'metadata.json')).writeAsString(
    jsonEncode({
      'title': title,
      'abbreviation': abbreviation,
      'display_abbreviation': abbreviation,
      'work_id': workId,
      'source_type': 'pioneer_captured_html',
      'source_site': 'egwwritings.org',
      'source_url': 'https://example.invalid/$folderName',
      'cover_image': 'images/image_0001.png',
      'contributors': contributors,
    }),
  );
  await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$title</title>
    <meta name="author" content="$authorName" />
    <link rel="canonical" href="https://example.invalid/$folderName" />
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

void legacyEpubTest(String description, dynamic Function() body) {
  test(description, body, skip: 'Legacy EPUB import path is disabled.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'pioneer_import_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'pioneer_import_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'pioneer_import_root_',
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
  });

  legacyEpubTest(
    'imports an APLIB EPUB Pioneer work, prefers EPUB over EGW capture, and skips capture-needed works',
    () async {
      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epub',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: [
          const PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epub',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          const PioneerSourceCandidate(
            provider: 'egwWritings',
            sourceType: 'readerPage',
            url: 'https://egwwritings.org/read?panels=p1297.2&index=0',
            priority: 50,
            qualityTier: 'reader',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );
      final uslp = _work(
        id: 'the_united_states_in_the_light_of_prophecy',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'The United States in the Light of Prophecy',
        abbreviation: 'USLP',
        sourceType: 'epub',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epub',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );
      final blocked = _sourceNeededWork(
        id: 'history_of_the_sabbath',
        authorId: 'jn_andrews',
        authorName: 'J. N. Andrews',
        title: 'History of the Sabbath',
        abbreviation: 'HST',
      );

      final zipBytes = _zipWithSingleEpubEntry(
        fileName: 'Daniel and the Revelation.epub',
        epubBytes: const [80, 75, 3, 4, 10, 11, 12, 13],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: zipBytes,
          httpStatusCode: 200,
          contentType: 'application/zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async => _fakeDocumentFor(work),
      );

      final result = await service.importSelectedWorks([dar, uslp, blocked]);

      expect(result.importedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.failedCount, 0);
      expect(
        result.workResults.map((item) => item.status),
        containsAll([
          PioneerImportWorkStatus.skippedNotImportable,
          PioneerImportWorkStatus.imported,
          PioneerImportWorkStatus.imported,
        ]),
      );

      final userDb = await UserDatabase.instance.database;
      final eLibraryDb = await ELibraryDatabase.instance.database;

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
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [uslp.stableLibraryItemId],
        ),
        0,
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
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [dar.stableLibraryItemId],
        ),
        0,
      );
    },
  );

  test(
    'skips a missing DAR ZIP candidate without attempting a download',
    () async {
      var fetchCount = 0;
      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epubZipEntry',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        availability: PioneerSourceAvailability.sourceNeeded,
        catalogImportable: false,
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'adventaudio',
            sourceType: 'epub',
            editionLabel: '1897',
            editionYear: 1897,
            priority: 5,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.sourceNeeded,
            notes: 'EGW Audio / AdventAudio DAR 1897 EPUB URL needed.',
          ),
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Epub/Smith/Daniel and the Revelation.epub',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.sourceNeeded,
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async {
          fetchCount += 1;
          return PioneerSourceDownloadResult(
            bytes: Uint8List(0),
            httpStatusCode: 200,
            contentType: 'application/zip',
            resolvedUri: uri,
          );
        },
        parseDocument: (work, bytes) async => _fakeDocumentFor(work),
      );

      final result = await service.importSelectedWorks([dar]);

      expect(fetchCount, 0);
      expect(result.importedCount, 0);
      expect(result.skippedCount, 1);
      expect(
        result.workResults.single.status,
        PioneerImportWorkStatus.skippedNotImportable,
      );
      expect(result.workResults.single.work.title, 'Daniel and the Revelation');
    },
  );

  legacyEpubTest(
    'imports Daniel and the Revelation through the EllenWhiteAudio direct EPUB URL',
    () async {
      var fetchCount = 0;
      final epubBytes = _epubBytes();
      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'directEpub',
        sourceUrl:
            'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub',
        sourceLabel: 'EllenWhiteAudio / EGW Audio',
        collectionUrl: 'https://ellenwhiteaudio.org/ebooks-of-the-pioneers/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'ellenwhiteaudio',
            sourceType: 'directEpub',
            url:
                'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub',
            editionLabel: '1897',
            editionYear: 1897,
            priority: 1,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Epub/Smith/Daniel and the Revelation.epub',
            editionLabel: '1897',
            editionYear: 1897,
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.sourceNeeded,
            notes: 'APLIB ZIP entry missing from the archive.',
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async {
          fetchCount += 1;
          expect(
            uri.toString(),
            'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub',
          );
          return PioneerSourceDownloadResult(
            bytes: epubBytes,
            httpStatusCode: 200,
            contentType: 'application/epub+zip',
            resolvedUri: uri,
          );
        },
      );

      final result = await service.importSelectedWorks([dar]);

      expect(fetchCount, 1);
      expect(result.importedCount, 1);
      expect(result.failedCount, 0);
      expect(result.skippedCount, 0);
      expect(
        result.workResults.single.status,
        PioneerImportWorkStatus.imported,
      );
      expect(result.workResults.single.parsedSectionCount, 3);
      expect(result.workResults.single.parsedParagraphCount, greaterThan(0));

      final inspection = await inspectPioneerEpubBytes(epubBytes, work: dar);
      expect(inspection.profileName, 'pioneerPublicDomain');
      expect(inspection.sectionCount, 3);
      expect(inspection.paragraphCountAfterFiltering, greaterThan(0));

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
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [dar.stableLibraryItemId],
        ),
        0,
      );
      final navRows = await eLibraryDb.query(
        'library_navigation_items',
        columns: const <String>[
          'label',
          'is_front_matter',
          'is_body_start',
          'sort_order',
        ],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [dar.stableLibraryItemId],
        orderBy: 'sort_order ASC',
      );
      expect(navRows, hasLength(3));
      expect(navRows[0]['label'], 'Preface');
      expect(navRows[0]['is_front_matter'], 1);
      expect(navRows[1]['label'], 'Chapter 1 - Daniel in Captivity');
      expect(navRows[1]['is_body_start'], 1);
      expect(navRows[2]['label'], 'Chapter 2 - The Great Image');
    },
  );

  legacyEpubTest(
    'rejects front-matter-only EPUBs during quality validation and falls back to text capture',
    () async {
      final work = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'directEpub',
        sourceUrl: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
        sourceLabel: 'EllenWhiteAudio / EGW Audio',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'ellenwhiteaudio',
            sourceType: 'directEpub',
            url: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
            priority: 1,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          PioneerSourceCandidate(
            provider: 'egwWritings',
            sourceType: 'readerPage',
            url: 'https://egwwritings.org/read?panels=p1297.2&index=0',
            priority: 50,
            qualityTier: 'reader',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: Uint8List.fromList([80, 75, 3, 4, 10, 11, 12, 13]),
          httpStatusCode: 200,
          contentType: 'application/epub+zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async => PioneerImportDocument(
          title: work.title,
          sections: [
            PioneerImportSection(
              href: 'https://example.com/dar/front-matter',
              title: 'Copyright',
              paragraphs: const <String>[
                '© 2016 Adventist Pioneer Library',
                '37457 Jasper Lowell Rd',
              ],
              spineIndex: 1,
            ),
            PioneerImportSection(
              href: 'https://example.com/dar/front-matter-2',
              title: 'Contents',
              paragraphs: const <String>['Published in the USA', 'July, 2016'],
              spineIndex: 2,
            ),
          ],
        ),
      );

      final result = await service.importSelectedWorks([work]);
      final workResult = result.workResults.single;

      expect(result.importedCount, 0);
      expect(result.failedCount, 1);
      expect(workResult.status, PioneerImportWorkStatus.failed);
      expect(workResult.stage, 'validating');
      expect(
        workResult.reason,
        contains('no body text attached to navigation'),
      );
      expect(workResult.epubAvailable, isTrue);
      expect(workResult.epubValidated, isFalse);
      expect(workResult.epubRejectedReason, contains('no body text attached'));
      expect(workResult.preferredImportPreferenceLabel, 'Text/read capture');

      final eLibraryDb = await ELibraryDatabase.instance.database;
      final userDb = await UserDatabase.instance.database;
      expect(
        await _countRows(
          eLibraryDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        0,
      );
      expect(
        await _countRows(
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        0,
      );
    },
  );

  legacyEpubTest(
    'rejects EPUBs whose navigation has no attached body text',
    () async {
      final work = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'directEpub',
        sourceUrl: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
        sourceLabel: 'EllenWhiteAudio / EGW Audio',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'ellenwhiteaudio',
            sourceType: 'directEpub',
            url: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
            priority: 1,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          PioneerSourceCandidate(
            provider: 'egwWritings',
            sourceType: 'readerPage',
            url: 'https://egwwritings.org/read?panels=p1297.2&index=0',
            priority: 50,
            qualityTier: 'reader',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: Uint8List.fromList([80, 75, 3, 4, 10, 11, 12, 13]),
          httpStatusCode: 200,
          contentType: 'application/epub+zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async => PioneerImportDocument(
          title: work.title,
          sections: [
            PioneerImportSection(
              href: 'https://example.com/dar/front-matter',
              title: 'Contents',
              paragraphs: const <String>[
                '© 2016 Adventist Pioneer Library',
                '37457 Jasper Lowell Rd',
              ],
              spineIndex: 1,
            ),
            PioneerImportSection(
              href: 'https://example.com/dar/chapter-1',
              title: 'Chapter 1 - Daniel in Captivity',
              paragraphs: const <String>['', '   '],
              spineIndex: 2,
            ),
          ],
        ),
      );

      final result = await service.importSelectedWorks([work]);
      final workResult = result.workResults.single;

      expect(result.importedCount, 0);
      expect(result.failedCount, 1);
      expect(workResult.status, PioneerImportWorkStatus.failed);
      expect(workResult.stage, 'validating');
      expect(
        workResult.reason,
        contains('no body text attached to navigation'),
      );
      expect(workResult.epubAvailable, isTrue);
      expect(workResult.epubValidated, isFalse);
      expect(workResult.preferredImportPreferenceLabel, 'Text/read capture');
    },
  );

  legacyEpubTest(
    'accepts EPUBs with meaningful body text and marks validation passed',
    () async {
      final work = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'directEpub',
        sourceUrl: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
        sourceLabel: 'EllenWhiteAudio / EGW Audio',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'ellenwhiteaudio',
            sourceType: 'directEpub',
            url: 'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel.epub',
            priority: 1,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          PioneerSourceCandidate(
            provider: 'egwWritings',
            sourceType: 'readerPage',
            url: 'https://egwwritings.org/read?panels=p1297.2&index=0',
            priority: 50,
            qualityTier: 'reader',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: Uint8List.fromList([80, 75, 3, 4, 10, 11, 12, 13]),
          httpStatusCode: 200,
          contentType: 'application/epub+zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async => PioneerImportDocument(
          title: work.title,
          sections: [
            PioneerImportSection(
              href: 'https://example.com/dar/front-matter',
              title: 'Contents',
              paragraphs: const <String>[
                '© 2016 Adventist Pioneer Library',
                '37457 Jasper Lowell Rd',
              ],
              spineIndex: 1,
            ),
            PioneerImportSection(
              href: 'https://example.com/dar/chapter-1',
              title: 'Chapter 1 - Daniel in Captivity',
              paragraphs: const <String>[
                'Daniel and the Revelation opens with Daniel in captivity.',
                'The prophecy of Daniel begins with captivity and hope.',
              ],
              spineIndex: 2,
            ),
            PioneerImportSection(
              href: 'https://example.com/dar/chapter-2',
              title: 'Chapter 2 - The Great Image',
              paragraphs: const <String>[
                'The great image is the next major subject in the book.',
                'Its metals and kingdoms are discussed in careful sequence.',
              ],
              spineIndex: 3,
            ),
          ],
        ),
      );

      final result = await service.importSelectedWorks([work]);
      final workResult = result.workResults.single;

      expect(result.importedCount, 1);
      expect(result.failedCount, 0);
      expect(workResult.status, PioneerImportWorkStatus.imported);
      expect(workResult.epubValidated, isTrue);
      expect(workResult.epubRejectedReason, isNull);
      expect(workResult.preferredImportPreferenceLabel, 'Legacy EPUB fallback');
      expect(workResult.qualityValidationSummary, contains('EPUB passed'));

      final eLibraryDb = await ELibraryDatabase.instance.database;
      final userDb = await UserDatabase.instance.database;
      expect(
        await _countRows(
          eLibraryDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        1,
      );
      expect(
        await _countRows(
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        0,
      );
    },
  );

  legacyEpubTest(
    'imports the selected EPUB entry from a ZIP archive when multiple EPUBs are present',
    () async {
      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epubZipEntry',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: [
          const PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Smith - Daniel and the Revelation.epub',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );
      final uslp = _work(
        id: 'the_united_states_in_the_light_of_prophecy',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'The United States in the Light of Prophecy',
        abbreviation: 'USLP',
        sourceType: 'epubZipEntry',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: [
          const PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Smith - The United States in the Light of Prophecy.epub',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final zipBytes = _zipWithEpubEntries({
        'Smith - Daniel and the Revelation.epub': [1, 1, 1, 1],
        'Smith - The United States in the Light of Prophecy.epub': [2, 2, 2, 2],
      });

      final parsedBytes = <String, int>{};
      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: zipBytes,
          httpStatusCode: 200,
          contentType: 'application/zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async {
          parsedBytes[work.id] = bytes.first;
          return _fakeDocumentFor(work);
        },
      );

      final result = await service.importSelectedWorks([dar, uslp]);

      expect(result.importedCount, 2);
      expect(parsedBytes[dar.id], 1);
      expect(parsedBytes[uslp.id], 2);
    },
  );

  legacyEpubTest(
    'fails instead of falling back to a different EPUB when an explicit ZIP entry is missing',
    () async {
      final containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:schemas:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
      final opfXml = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Poems, by Uriah Smith</dc:title>
    <dc:identifier id="uid">urn:test-poems</dc:identifier>
  </metadata>
  <manifest>
    <item id="ch1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
''';
      final chapterXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Poems, by Uriah Smith</title></head>
  <body>
    <h1>POEMS, BY URIAH SMITH.</h1>
    <p>Poetry content that should never be written under Daniel's id.</p>
  </body>
</html>
''';

      final epubArchive = Archive()
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            containerXml.length,
            containerXml.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('content.opf', opfXml.length, opfXml.codeUnits))
        ..addFile(
          ArchiveFile(
            'Text/chapter1.xhtml',
            chapterXhtml.length,
            chapterXhtml.codeUnits,
          ),
        );
      final wrongEpubBytes = Uint8List.fromList(
        ZipEncoder().encode(epubArchive),
      );

      final collectionArchive = Archive()
        ..addFile(
          ArchiveFile(
            'Epub/Smith/Poems, by Uriah Smith.epub',
            wrongEpubBytes.length,
            wrongEpubBytes,
          ),
        );
      final collectionZipBytes = Uint8List.fromList(
        ZipEncoder().encode(collectionArchive),
      );

      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epubZipEntry',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Epub/Smith/Daniel and the Revelation.epub',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: collectionZipBytes,
          httpStatusCode: 200,
          contentType: 'application/zip',
          resolvedUri: uri,
        ),
      );

      final result = await service.importSelectedWorks([dar]);

      expect(result.importedCount, 0);
      expect(result.failedCount, 1);
      expect(result.workResults.single.status, PioneerImportWorkStatus.failed);
      expect(result.workResults.single.reason, contains('ZIP entry not found'));
    },
  );

  legacyEpubTest(
    'prefers AdventAudio EPUB over APLIB ZIP entry when both are available',
    () async {
      final work = _work(
        id: 'sample_work',
        authorId: 'sample_author',
        authorName: 'Sample Author',
        title: 'Sample Work',
        abbreviation: 'SW',
        sourceType: 'epub',
        sourceUrl: 'https://example.com/high-quality.epub',
        sourceLabel: 'EGW Audio / AdventAudio',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: [
          const PioneerSourceCandidate(
            provider: 'adventaudio',
            sourceType: 'epub',
            url: 'https://example.com/high-quality.epub',
            priority: 5,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
          const PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: 'Epub/Smith/Sample Work.epub',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final fetchedUrls = <String>[];
      final service = PioneerTextImportService(
        fetchBytes: (uri) async {
          fetchedUrls.add(uri.toString());
          return PioneerSourceDownloadResult(
            bytes: Uint8List.fromList([80, 75, 3, 4, 10, 11, 12, 13]),
            httpStatusCode: 200,
            contentType: 'application/epub+zip',
            resolvedUri: uri,
          );
        },
        parseDocument: (work, bytes) async => PioneerImportDocument(
          title: work.title,
          sections: [
            PioneerImportSection(
              href: work.sourceUrl ?? 'https://example.com/high-quality.epub',
              title: 'Chapter 1',
              paragraphs: const ['AdventAudio is preferred.'],
              spineIndex: 1,
            ),
          ],
        ),
      );

      final result = await service.importSelectedWorks([work]);

      expect(result.importedCount, 1);
      expect(fetchedUrls, hasLength(1));
      expect(fetchedUrls.single, 'https://example.com/high-quality.epub');
    },
  );

  legacyEpubTest(
    'does not overwrite existing installs without explicit repair',
    () async {
      final work = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epub',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epub',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final zipBytes = _zipWithSingleEpubEntry(
        fileName: 'Daniel and the Revelation.epub',
        epubBytes: const [80, 75, 3, 4, 10, 11, 12, 13],
      );

      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: zipBytes,
          httpStatusCode: 200,
          contentType: 'application/zip',
          resolvedUri: uri,
        ),
        parseDocument: (work, bytes) async => _fakeDocumentFor(work),
      );

      final first = await service.importSelectedWorks([work]);
      expect(first.importedCount, 1);

      final skipped = await service.importSelectedWorks([work]);
      expect(skipped.importedCount, 0);
      expect(skipped.skippedCount, 1);
      expect(skipped.workResults.single.reason, 'Already installed.');

      final repaired = await service.importSelectedWorks([
        work,
      ], allowRepair: true);
      expect(repaired.importedCount, 1);
      expect(repaired.skippedCount, 0);
    },
  );

  test(
    'imports captured HTML through the user-verified automated capture path and preserves ref codes',
    () async {
      final work = _sourceNeededWork(
        id: 'history_of_the_sabbath',
        authorId: 'jn_andrews',
        authorName: 'J. N. Andrews',
        title: 'History of the Sabbath',
        abbreviation: 'HST',
      );

      final service = PioneerTextImportService();
      final result = await service.importFromCapturedHtml(
        work: work,
        html: '''
<!doctype html>
<html>
  <head>
    <title>History of the Sabbath</title>
  </head>
  <body>
    <h1>CHAPTER 1</h1>
    <p>HST 7.3 appears in the first paragraph.</p>
    <p>Another paragraph preserves USLP 12.1 for display.</p>
  </body>
</html>
''',
        sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
        sourceLabel: 'EGW Writings',
      );

      expect(result.wasCancelled, isFalse);
      expect(result.importedCount, 1);
      expect(result.failedCount, 0);

      final workResult = result.workResults.single;
      expect(workResult.status, PioneerImportWorkStatus.imported);
      expect(
        workResult.sourceMethod,
        PioneerImportSourceMethod.userVerifiedAutomatedCapture,
      );
      expect(workResult.parsedSectionCount, 1);
      expect(workResult.parsedParagraphCount, 2);
      expect(workResult.navigationCount, 1);
      expect(workResult.textBlockCount, 2);
      expect(workResult.refCodeHandlingSummary, contains('2 source ref codes'));
      expect(workResult.refCodeHandlingSummary, contains('preserved'));

      final userDb = await UserDatabase.instance.database;
      final eLibraryDb = await ELibraryDatabase.instance.database;
      expect(
        await _countRows(
          eLibraryDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        1,
      );
      expect(
        await _countRows(
          eLibraryDb,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        2,
      );
      expect(
        await _countRows(
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        0,
      );
      expect(
        await _countRows(
          eLibraryDb,
          'library_text_blocks',
          where:
              'library_item_id = ? AND (plain_text LIKE ? OR plain_text LIKE ? OR plain_text LIKE ? OR plain_text LIKE ?)',
          whereArgs: [
            work.stableLibraryItemId,
            '%Adventist Pioneer Library%',
            '%www.APLib.org%',
            '%ISBN:%',
            '%Published in the USA%',
          ],
        ),
        0,
      );
    },
  );

  test(
    'marks title-page boilerplate as front matter and starts at the first meaningful section',
    () async {
      final work = _sourceNeededWork(
        id: 'the_story_of_the_seer_of_patmos',
        authorId: 's_n_haskell',
        authorName: 'S. N. Haskell',
        title: 'The Story of the Seer of Patmos',
        abbreviation: 'TSOT',
      );

      final service = PioneerTextImportService();
      final result = await service.importFromCapturedHtml(
        work: work,
        html: '''
<!doctype html>
<html>
  <head>
    <title>The Story of the Seer of Patmos</title>
  </head>
  <body>
    <h1>The Story of the Seer of Patmos</h1>
    <p>BY STEPHEN N. HASKELL.</p>
    <p>SOUTHERN PUBLISHING ASSOCIATION, NASHVILLE, TENNESSEE.</p>
    <h2>FOREWORD</h2>
    <p>This foreword is short and should stay in front matter.</p>
    <h2>CHAPTER I. THE SEER OF PATMOS</h2>
    <p>The men whom God has chosen as a means of communication between heaven and earth, form a galaxy of noted characters.</p>
    <p>The gift of prophecy is called the "best gift," and the church is exhorted to covet that "best gift."</p>
  </body>
</html>
''',
        sourceUrl: null,
        sourceLabel: 'Pioneer',
      );

      expect(result.importedCount, 1);
      expect(result.failedCount, 0);
      expect(
        result.workResults.single.refCodeHandlingSummary,
        contains('no source ref codes'),
      );

      final eLibraryDb = await ELibraryDatabase.instance.database;
      final itemId = work.stableLibraryItemId;
      final navRows = await eLibraryDb.query(
        'library_navigation_items',
        columns: const <String>[
          'label',
          'is_front_matter',
          'is_body_start',
          'sort_order',
        ],
        where: 'library_item_id = ? AND deleted_at IS NULL',
        whereArgs: [itemId],
        orderBy: 'sort_order ASC',
      );

      expect(navRows, hasLength(3));
      expect(navRows[0]['is_front_matter'], 1);
      expect(navRows[0]['is_body_start'], 0);
      expect(navRows[1]['is_front_matter'], 1);
      expect(navRows[1]['is_body_start'], 0);
      expect(navRows[2]['is_front_matter'], 0);
      expect(navRows[2]['is_body_start'], 1);
      expect(navRows[2]['label'], 'CHAPTER I. THE SEER OF PATMOS');
    },
  );

  test(
    'imports a full-work browser capture session with multiple sections',
    () async {
      final work = _sourceNeededWork(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
      );

      final service = PioneerTextImportService();
      final result = await service.importFromCapturedHtml(
        work: work,
        html: '''
PREFACE

A brief preface paragraph is captured before the numbered chapters. DAR 7.3

01 - DANIEL IN CAPTIVITY

VERSE 1. In the third year of Jehoiakim king of Judah came Nebuchadnezzar. DAR 24.1

02 - THE GREAT IMAGE

The great image prophecy opens a new chapter of the captured work. DAR 32.1
''',
        sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
        sourceLabel: 'EGW Writings',
      );

      expect(result.importedCount, 1);
      final workResult = result.workResults.single;
      expect(workResult.sourceType, 'egw_browser_capture');
      expect(workResult.navigationCount, 3);
      expect(workResult.textBlockCount, 3);

      final db = await ELibraryDatabase.instance.database;
      expect(
        await _countRows(
          db,
          'library_items',
          where:
              'id = ? AND source_type = ? AND relative_path NOT LIKE ? AND relative_path LIKE ?',
          whereArgs: [
            work.stableLibraryItemId,
            'egw_browser_capture',
            '%ePubs/%',
            'TextCaptures/%',
          ],
        ),
        1,
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ? AND plain_text LIKE ?',
          whereArgs: [work.stableLibraryItemId, '%DAR 32.1%'],
        ),
        1,
      );
    },
  );

  test('rejects challenge HTML and asks for manual verification', () async {
    final work = _sourceNeededWork(
      id: 'history_of_the_sabbath',
      authorId: 'jn_andrews',
      authorName: 'J. N. Andrews',
      title: 'History of the Sabbath',
      abbreviation: 'HST',
    );

    final service = PioneerTextImportService();
    final result = await service.importFromCapturedHtml(
      work: work,
      html: '''
<!doctype html>
<html>
  <head><title>Just a moment...</title></head>
  <body><div>Cloudflare security check</div></body>
</html>
''',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
    );

    expect(result.importedCount, 0);
    expect(result.failedCount, 1);

    final workResult = result.workResults.single;
    expect(workResult.status, PioneerImportWorkStatus.failed);
    expect(workResult.requiresManualVerification, isTrue);
    expect(workResult.manualVerificationHint, isNotNull);
    expect(workResult.reason, contains('Parse failed'));
    expect(workResult.detail, contains('human-verification or challenge page'));
  });

  test(
    'detects reader structure, TOC links, and next-page links from EGW HTML',
    () {
      final inspection = inspectPioneerPage(
        currentUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
        title: 'Daniel and the Revelation',
        bodyText: 'DAR 7.3 appears here.',
        outerHtml: '''
<html>
  <head><title>Daniel and the Revelation</title></head>
  <body>
    <a href="https://egwwritings.org/allCollection/en/160">Contents</a>
    <a rel="next" href="https://egwwritings.org/read?panels=p1297.2&index=1">Next</a>
    <a rel="prev" href="https://egwwritings.org/read?panels=p1297.2&index=0">Previous</a>
  </body>
</html>
''',
      );

      expect(inspection.isReady, isFalse);
      expect(inspection.manualVerificationRequired, isFalse);
      expect(inspection.structure.currentPanelId, 'p1297.2');
      expect(inspection.structure.currentIndex, 0);
      expect(inspection.structure.tocLinks, isNotEmpty);
      expect(inspection.structure.readPageLinks, isNotEmpty);
      expect(inspection.structure.nextUrl, contains('index=1'));
      expect(inspection.structure.previousUrl, contains('index=0'));
      expect(inspection.structure.paragraphMarkers, contains('DAR 7.3'));
    },
  );

  legacyEpubTest(
    'imports an epubZipEntry work using the real EPUB parser with no fake parseDocument override',
    () async {
      // Build a minimal valid EPUB archive in memory.
      final containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:schemas:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
      final opfXml = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Daniel and the Revelation</dc:title>
    <dc:identifier id="uid">urn:test-dar</dc:identifier>
  </metadata>
  <manifest>
    <item id="ch1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
''';
      final chapterXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter 1</title></head>
  <body>
    <h1>Chapter 1</h1>
    <p>Daniel in captivity opens the book with a vision of the Son of man.</p>
    <p>The prophecy establishes a chronological sequence of world empires.</p>
  </body>
</html>
''';

      // Inner ZIP = the EPUB file itself.
      final epubArchive = Archive()
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            containerXml.length,
            containerXml.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('content.opf', opfXml.length, opfXml.codeUnits))
        ..addFile(
          ArchiveFile(
            'Text/chapter1.xhtml',
            chapterXhtml.length,
            chapterXhtml.codeUnits,
          ),
        );
      final epubBytes = Uint8List.fromList(ZipEncoder().encode(epubArchive));

      // Outer ZIP = the collection ZIP that the importer downloads.
      const zipEntryPath = 'Epub/Smith/Daniel and the Revelation.epub';
      final collectionArchive = Archive()
        ..addFile(ArchiveFile(zipEntryPath, epubBytes.length, epubBytes));
      final collectionZipBytes = Uint8List.fromList(
        ZipEncoder().encode(collectionArchive),
      );

      final dar = _work(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        sourceType: 'epubZipEntry',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        sourceLabel: 'APLIB',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'aplib',
            sourceType: 'epubZipEntry',
            url: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
            zipEntry: zipEntryPath,
            priority: 10,
            qualityTier: 'epub',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      // No parseDocument override → real _parseSourceDocument is used.
      final service = PioneerTextImportService(
        fetchBytes: (uri) async => PioneerSourceDownloadResult(
          bytes: collectionZipBytes,
          httpStatusCode: 200,
          contentType: 'application/zip',
          resolvedUri: uri,
        ),
      );

      final result = await service.importSelectedWorks([dar]);

      expect(
        result.importedCount,
        1,
        reason:
            'Expected one successful import; got: '
            '${result.workResults.map((r) => "${r.work.title}: ${r.status} [${r.stage}] ${r.reason}").join(", ")}',
      );
      expect(result.failedCount, 0);
      expect(result.workResults.single.parsedSectionCount, greaterThan(0));
      expect(result.workResults.single.parsedParagraphCount, greaterThan(0));

      final eLibraryDb = await ELibraryDatabase.instance.database;
      final userDb = await UserDatabase.instance.database;

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
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [dar.stableLibraryItemId],
        ),
        greaterThan(0),
      );
      // Must write nothing to user.db.
      expect(
        await _countRows(
          userDb,
          'library_items',
          where: 'id = ?',
          whereArgs: [dar.stableLibraryItemId],
        ),
        0,
      );
    },
  );

  test(
    'repeated import skips existing Pioneer rows without duplicating them',
    () async {
      final work = _sourceNeededWork(
        id: 'history_of_the_sabbath',
        authorId: 'jn_andrews',
        authorName: 'J. N. Andrews',
        title: 'History of the Sabbath',
        abbreviation: 'HST',
      );

      final service = PioneerTextImportService();

      final first = await service.importFromCapturedHtml(
        work: work,
        html: '''
<!doctype html>
<html><body><h1>CHAPTER 1</h1><p>HST 7.3 one.</p></body></html>
''',
        sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
        sourceLabel: 'EGW Writings',
      );
      expect(first.importedCount, 1);

      final second = await service.importFromCapturedHtml(
        work: work,
        html: '''
<!doctype html>
<html><body><h1>CHAPTER 1</h1><p>HST 7.3 one.</p></body></html>
''',
        sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
        sourceLabel: 'EGW Writings',
      );
      expect(second.importedCount, 0);
      expect(second.skippedCount, 1);
      expect(
        second.workResults.map((item) => item.status),
        everyElement(PioneerImportWorkStatus.skippedExisting),
      );
    },
  );

  test('captured import overwrite replaces child rows cleanly', () async {
    final work = _sourceNeededWork(
      id: 'history_of_the_sabbath',
      authorId: 'jn_andrews',
      authorName: 'J. N. Andrews',
      title: 'History of the Sabbath',
      abbreviation: 'HST',
    );
    final service = PioneerTextImportService();

    final first = await service.importFromCapturedHtml(
      work: work,
      html:
          '<html><body><h1>CHAPTER 1</h1><p>Old partial HST 7.3 one.</p></body></html>',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
    );
    expect(first.importedCount, 1);

    final db = await ELibraryDatabase.instance.database;
    await db.insert('elibrary_markups', <String, Object?>{
      'id': 9001,
      'library_item_id': work.stableLibraryItemId,
      'epub_href': 'chapter_1.html',
      'start_block_index': 0,
      'start_char_offset': 0,
      'end_block_index': 0,
      'end_char_offset': 11,
      'start_token_index': null,
      'end_token_index': null,
      'ref_start': 'HST 7.3',
      'ref_end': 'HST 7.3',
      'compact_ref': 'HST 7.3',
      'selected_text_snapshot': 'Old partial',
      'markup_type': 'highlight',
      'color': '#ffcc00',
      'note_text': 'user annotation should survive overwrite',
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
      'deleted_at': null,
    });

    final second = await service.importFromCapturedHtml(
      work: work,
      html: '''
<html><body>
  <h1>CHAPTER 1</h1>
  <p>New complete HST 7.3 one.</p>
  <p>New complete HST 7.4 two.</p>
</body></html>
''',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
      existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
    );
    expect(second.importedCount, 1);

    expect(
      await _countRows(
        db,
        'library_items',
        where: 'id = ?',
        whereArgs: [work.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        db,
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [work.stableLibraryItemId],
      ),
      2,
    );
    expect(
      await _countRows(
        db,
        'library_text_blocks',
        where: 'library_item_id = ? AND plain_text LIKE ?',
        whereArgs: [work.stableLibraryItemId, '%Old partial%'],
      ),
      0,
    );
    expect(
      await _countRows(
        db,
        'library_text_blocks',
        where: 'library_item_id = ? AND plain_text LIKE ?',
        whereArgs: [work.stableLibraryItemId, '%New complete%'],
      ),
      2,
    );
    expect(
      await _countRows(
        db,
        'elibrary_markups',
        where: 'library_item_id = ?',
        whereArgs: [work.stableLibraryItemId],
      ),
      1,
      reason:
          'Overwrite should not drop user markup rows when replacing captured text.',
    );
  });

  test(
    'imports staged LOF_ATJ HTML capture with refs and chapter navigation',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('pioneer_lof_');
      try {
        await _createCaptureFixtureRoot(
          root: Directory(p.join(tempDir.path, 'assets', 'scans')),
          folderName: 'LOF_ATJ',
          title: 'Lessons on Faith',
          abbreviation: 'LOF_ATJ',
          workId: 'lessons_on_faith',
          authorName: 'A. T. Jones',
          contributorNames: const ['E. J. Waggoner'],
          bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Living By Faith LOF_ATJ 1 Intro text. LOF_ATJ 1.1 Faith matters.</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Gift of Righteousness LOF_ATJ 2 Grace is a gift. LOF_ATJ 2.1</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 3 — Walking With God LOF_ATJ 3.1 Faith continues.</p>
    </div>
''',
        );

        final catalog = PioneerSourceCatalog.fromJson({
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
        final previews = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: tempDir.path,
          preferAssetManifest: false,
        ).scan(catalog: catalog);
        final lof = previews.singleWhere(
          (preview) => preview.folderName == 'LOF_ATJ',
        );
        expect(lof.duplicateRefCount, 0);
        expect(lof.detectedTitle, 'Lessons on Faith');
        expect(lof.detectedAuthor, 'A. T. Jones');
        expect(lof.detectedAbbreviation, 'LOF_ATJ');

        final service = PioneerTextImportService();
        final result = await service.importHtmlCaptureFolders([
          lof,
        ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);
        expect(result.importedCount, 1);
        expect(result.failedCount, 0);

        final db = await ELibraryDatabase.instance.database;
        final work = lof.importWork;
        final itemRows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [work.stableLibraryItemId],
        );
        expect(itemRows, hasLength(1));
        expect(itemRows.single['title'], 'Lessons on Faith');
        expect(
          itemRows.single['author'],
          'A. T. Jones; E. J. Waggoner',
          reason:
              'LOF is a joint work; denormalized author combines both names',
        );
        expect(itemRows.single['source_type'], 'egw_html_capture');
        expect(itemRows.single['source_site'], 'egwwritings.org');
        expect(
          itemRows.single['relative_path'],
          contains('LOF_ATJ/capture.html'),
        );
        expect(itemRows.single['relative_path'], isNot(contains('ePubs/')));
        expect(itemRows.single['relative_path'], isNot(contains('PDFs/')));
        expect(itemRows.single['source_url'], contains('LOF_ATJ/capture.html'));
        expect(itemRows.single['source_url'], isNot(contains('.epub')));
        expect(itemRows.single['source_url'], isNot(contains('.pdf')));
        expect(
          itemRows.single['source_site']?.toString().toLowerCase(),
          isNot(contains('ellenwhiteaudio')),
        );
        expect(
          itemRows.single['source_type']?.toString().toLowerCase(),
          isNot(contains('ocr')),
        );
        expect(
          itemRows.single['source_type']?.toString().toLowerCase(),
          isNot(contains('epub')),
        );

        expect(
          await _countRows(
            db,
            'library_navigation_items',
            where: 'library_item_id = ? AND label LIKE ?',
            whereArgs: [work.stableLibraryItemId, 'Chapter%'],
          ),
          greaterThanOrEqualTo(2),
        );
        expect(
          await _countRows(
            db,
            'library_text_blocks',
            where: 'library_item_id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          greaterThanOrEqualTo(2),
        );
        expect(
          await _countRows(
            db,
            'elibrary_ref_index',
            where: 'library_item_id = ?',
            whereArgs: [work.stableLibraryItemId],
          ),
          greaterThanOrEqualTo(2),
        );
        expect(
          await _countRows(
            db,
            'elibrary_ref_index',
            where: 'library_item_id = ? AND ref_code = ?',
            whereArgs: [work.stableLibraryItemId, 'LOF_ATJ 113.2'],
          ),
          0,
        );
        expect(
          await _countRows(
            db,
            'library_text_blocks',
            where: 'library_item_id = ? AND plain_text LIKE ?',
            whereArgs: [
              work.stableLibraryItemId,
              '%Without faith it is impossible to please him.%',
            ],
          ),
          0,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('captured import overwrite preserves an existing cover path', () async {
    final work = _sourceNeededWork(
      id: 'history_of_the_sabbath',
      authorId: 'jn_andrews',
      authorName: 'J. N. Andrews',
      title: 'History of the Sabbath',
      abbreviation: 'HST',
    );
    final db = await ELibraryDatabase.instance.database;
    await db.insert('library_items', <String, Object?>{
      'id': work.stableLibraryItemId,
      'title': work.title,
      'author': work.authorName,
      'file_name': 'HST.html',
      'relative_path':
          'TextCaptures/Research/Pioneer Authors/jn_andrews/HST.html',
      'file_hash': 'old',
      'file_size': 3,
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Adventist Pioneer Library',
      'source_site': 'egwwritings.org',
      'source_url': 'https://egwwritings.org/read?panels=p1297.2&index=0',
      'source_type': 'egw_browser_capture',
      'cover_path': 'assets/library_covers/thumbs/HST.png',
      'date_added': '2026-06-25T00:00:00Z',
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
      'device_id': 'device-1',
      'index_status': 'partially_imported',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    });

    final service = PioneerTextImportService();
    final result = await service.importFromCapturedHtml(
      work: work,
      html:
          '<html><body><h1>CHAPTER 1</h1><p>Replacement HST 7.3 one.</p></body></html>',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
      existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
    );

    expect(result.importedCount, 1);

    final itemRows = await db.query(
      'library_items',
      columns: const ['cover_path'],
      where: 'id = ?',
      whereArgs: [work.stableLibraryItemId],
    );
    expect(
      itemRows.single['cover_path'],
      'assets/library_covers/thumbs/HST.png',
    );
  });

  test(
    'imports staged DAR HTML capture using metadata work_id instead of the EPUB row',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('pioneer_dar_');
      try {
        await _createCaptureFixtureRoot(
          root: Directory(p.join(tempDir.path, 'assets', 'scans')),
          folderName: 'DAR',
          title: 'Daniel and the Revelation',
          abbreviation: 'DAR',
          workId: 'DAR_US',
          authorName: 'Uriah Smith',
          bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Daniel in Captivity DAR_US 1.1 The chapter begins. DAR_US 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Great Image DAR_US 2.1 Another section follows.</p>
    </div>
''',
        );

        final catalog = PioneerSourceCatalog.fromJson({
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
                  'source_url': 'assets/scans/DAR/capture.html',
                  'source_label': 'Local HTML Capture',
                  'verified': true,
                  'importable': true,
                },
              ],
            },
          ],
        });
        final previews = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: tempDir.path,
          preferAssetManifest: false,
        ).scan(catalog: catalog);
        final dar = previews.singleWhere(
          (preview) => preview.folderName == 'DAR',
        );
        expect(dar.metadata.workId, 'DAR_US');
        expect(dar.isValid, isTrue);
        expect(dar.importWork.id, 'DAR_US');
        expect(dar.importWork.authorName, 'Uriah Smith');
        expect(dar.importWork.cachedCoverPath, contains('image_0001.png'));
        expect(dar.detectedTitle, 'Daniel and the Revelation');

        final db = await ELibraryDatabase.instance.database;
        await db.insert('library_items', <String, Object?>{
          'id':
              'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
          'title': 'Daniel and the Revelation',
          'author': 'Uriah Smith',
          'file_name': 'DAR.epub',
          'relative_path':
              'ePubs/Research/Pioneer Authors/uriah_smith/DAR.epub',
          'file_hash': 'stale-dar-epub-hash',
          'file_size': 3,
          'mime_type': 'application/epub+zip',
          'file_format': 'epub',
          'folder_type': 'research',
          'library_role': 'research',
          'collection_name': 'Adventist Pioneer Library',
          'source_site': 'ellenwhiteaudio.org',
          'source_url': 'https://example.invalid/dar.epub',
          'source_type': 'epub',
          'date_added': '2026-06-25T00:00:00Z',
          'created_at': '2026-06-25T00:00:00Z',
          'updated_at': '2026-06-25T00:00:00Z',
          'device_id': 'device-1',
          'revision': 1,
          'sync_status': 'pending',
        });
        final service = PioneerTextImportService();
        final parsed = parseEgwCopiedRangeText(
          dar.extractedText ?? '',
          workAbbreviation: dar.detectedAbbreviation ?? 'DAR_US',
        );
        final importDocument = PioneerImportDocument(
          title: dar.importWork.title,
          sections: [
            for (
              var index = 0;
              index < parsed.document.sections.length;
              index++
            )
              PioneerImportSection(
                href: 'assets/scans/DAR/capture.html#section_${index + 1}',
                title: parsed.document.sections[index].title,
                paragraphs: parsed.document.sections[index].paragraphs
                    .map((paragraph) => paragraph.text)
                    .toList(growable: false),
                spineIndex: index + 1,
              ),
          ],
        );
        final result = await service.importFromParsedCapturedHtml(
          work: dar.importWork,
          document: importDocument,
          sourceBytes: Uint8List.fromList(utf8.encode(dar.extractedText ?? '')),
          sourceType: 'egw_html_capture',
          sourceSite: 'egwwritings.org',
          relativePath: 'assets/scans/DAR/capture.html',
          coverPath: dar.preferredCoverImagePath,
          existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
        );
        expect(result.importedCount, 1);
        expect(result.failedCount, 0);

        final importedWork = dar.importWork;
        final itemRows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [importedWork.stableLibraryItemId],
        );
        expect(itemRows, hasLength(1));
        expect(itemRows.single['title'], 'Daniel and the Revelation');
        expect(itemRows.single['author'], 'Uriah Smith');
        expect(itemRows.single['source_type'], 'egw_html_capture');
        expect(itemRows.single['source_site'], 'egwwritings.org');
        expect(itemRows.single['relative_path'], contains('DAR/capture.html'));
        expect(itemRows.single['relative_path'], isNot(contains('ePubs/')));
        expect(itemRows.single['relative_path'], isNot(contains('PDFs/')));
        expect(
          await _countRows(
            db,
            'library_navigation_items',
            where: 'library_item_id = ? AND label LIKE ?',
            whereArgs: [importedWork.stableLibraryItemId, 'Chapter%'],
          ),
          greaterThanOrEqualTo(1),
        );
        expect(
          await _countRows(
            db,
            'library_text_blocks',
            where: 'library_item_id = ?',
            whereArgs: [importedWork.stableLibraryItemId],
          ),
          greaterThanOrEqualTo(1),
        );
        expect(
          await _countRows(
            db,
            'elibrary_ref_index',
            where: 'library_item_id = ?',
            whereArgs: [importedWork.stableLibraryItemId],
          ),
          greaterThanOrEqualTo(1),
        );
        expect(
          await _countRows(
            db,
            'library_items',
            where: 'id = ? AND source_type = ? AND relative_path LIKE ?',
            whereArgs: [
              'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
              'epub',
              '%ePubs/%',
            ],
          ),
          1,
          reason:
              'The existing EPUB-backed DAR row should remain untouched when importing the scan folder.',
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('HTML capture overwrite replaces stale legacy Pioneer row', () async {
    final tempDir = await Directory.systemTemp.createTemp('pioneer_lof_');
    try {
      await _createCaptureFixtureRoot(
        root: Directory(p.join(tempDir.path, 'assets', 'scans')),
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        workId: 'lessons_on_faith',
        authorName: 'A. T. Jones',
        contributorNames: const ['E. J. Waggoner'],
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Living By Faith LOF_ATJ 1 Intro text. LOF_ATJ 1.1 Faith matters.</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Gift of Righteousness LOF_ATJ 2 Grace is a gift. LOF_ATJ 2.1</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 3 — Walking With God LOF_ATJ 3.1 Faith continues.</p>
    </div>
''',
      );

      final catalog = PioneerSourceCatalog.fromJson({
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
      final lof =
          (await PioneerHtmlCaptureFolderScanner(
            projectRootPath: tempDir.path,
            currentDirectoryPath: tempDir.path,
            preferAssetManifest: false,
          ).scan(catalog: catalog)).singleWhere(
            (preview) => preview.folderName == 'LOF_ATJ',
          );
      final work = lof.importWork;
      final db = await ELibraryDatabase.instance.database;
      await PioneerTextImportService().hardResetWork(work);
      await db.insert('library_items', <String, Object?>{
        'id': work.stableLibraryItemId,
        'title': work.title,
        'author': work.authorName,
        'file_name': 'LOF.epub',
        'relative_path': 'ePubs/Research/Pioneer Authors/LOF.epub',
        'file_hash': 'stale-epub-hash',
        'file_size': 3,
        'mime_type': 'application/epub+zip',
        'file_format': 'epub',
        'folder_type': 'research',
        'library_role': 'research',
        'collection_name': 'Adventist Pioneer Library',
        'source_site': 'APLIB',
        'source_url': 'https://example.invalid/pioneers.zip',
        'source_type': 'epub',
        'date_added': '2026-06-25T00:00:00Z',
        'created_at': '2026-06-25T00:00:00Z',
        'updated_at': '2026-06-25T00:00:00Z',
        'device_id': 'device-1',
        'index_status': 'failed',
        'is_missing': 0,
        'revision': 1,
        'sync_status': 'pending',
      });
      await db.insert('library_text_blocks', <String, Object?>{
        'library_item_id': work.stableLibraryItemId,
        'epub_href': 'OEBPS/stale.xhtml',
        'spine_index': 1,
        'paragraph_index': 1,
        'paragraph_on_section': 1,
        'section_title': 'Stale EPUB',
        'plain_text': 'Old low-quality EPUB text.',
        'created_at': '2026-06-25T00:00:00Z',
        'updated_at': '2026-06-25T00:00:00Z',
      });

      final result = await PioneerTextImportService().importHtmlCaptureFolders([
        lof,
      ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);

      expect(result.importedCount, 1);
      final itemRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [work.stableLibraryItemId],
      );
      expect(itemRows, hasLength(1));
      expect(itemRows.single['source_type'], 'egw_html_capture');
      expect(itemRows.single['mime_type'], 'text/html');
      expect(itemRows.single['file_format'], 'html');
      expect(itemRows.single['source_site'], 'egwwritings.org');
      expect(
        itemRows.single['relative_path'],
        contains('LOF_ATJ/capture.html'),
      );
      expect(itemRows.single['relative_path'], isNot(contains('ePubs/')));
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ? AND plain_text LIKE ?',
          whereArgs: [work.stableLibraryItemId, '%Old low-quality EPUB text%'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        greaterThanOrEqualTo(2),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('partial existing capture can be replaced', () async {
    final work = _sourceNeededWork(
      id: 'history_of_the_sabbath',
      authorId: 'jn_andrews',
      authorName: 'J. N. Andrews',
      title: 'History of the Sabbath',
      abbreviation: 'HST',
    );
    final db = await ELibraryDatabase.instance.database;
    await db.insert('library_items', <String, Object?>{
      'id': work.stableLibraryItemId,
      'title': work.title,
      'author': work.authorName,
      'file_name': 'HST.html',
      'relative_path':
          'TextCaptures/Research/Pioneer Authors/jn_andrews/HST.html',
      'file_hash': 'old',
      'file_size': 3,
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Adventist Pioneer Library',
      'source_site': 'egwwritings.org',
      'source_url': 'https://egwwritings.org/read?panels=p1297.2&index=0',
      'source_type': 'egw_browser_capture',
      'date_added': '2026-06-25T00:00:00Z',
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
      'device_id': 'device-1',
      'index_status': 'partially_imported',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    });

    final service = PioneerTextImportService();
    final summary = await service.inspectExistingCapturedImport(work);
    expect(summary.hasExistingImport, isTrue);
    expect(summary.isPartialOrFailed, isTrue);

    final result = await service.importFromCapturedHtml(
      work: work,
      html:
          '<html><body><h1>CHAPTER 1</h1><p>Replacement HST 7.3 one.</p></body></html>',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
      existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
    );

    expect(result.importedCount, 1);
    expect(
      await _countRows(
        db,
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [work.stableLibraryItemId],
      ),
      1,
    );
  });

  test(
    'imports 3-block clip-text HTML into all expected DB tables with no EPUB/PDF/OCR contamination',
    () async {
      // Build a synthetic PioneerHtmlCaptureFolderPreview manually so we can
      // supply precisely 2 chapter headings + 3 paragraph refs and verify the
      // exact DB row counts without depending on the real LOF_ATJ asset.
      const syntheticHtml = '''
<!doctype html>
<html><head><title>Synthetic Test Work</title></head><body>
  <div class="clip clip-text">
    <p>Chapter 1 — Opening Chapter  SNTH 5  First paragraph text.  SNTH 5.1 Second paragraph text.  SNTH 5.2</p>
  </div>
  <div class="clip clip-text">
    <p>Chapter 2 — Closing Chapter  SNTH 6  Third paragraph text.  SNTH 6.1</p>
  </div>
</body></html>
''';

      final extraction = const EgwHtmlCaptureExtractor().extract(syntheticHtml);
      expect(extraction.detectedAbbreviation, 'SNTH');
      expect(extraction.refCount, 3);
      expect(extraction.chapterHeadingCount, 2);

      final work = _work(
        id: 'synthetic_test_work',
        authorId: 'test_author',
        authorName: 'Test Author',
        title: 'Synthetic Test Work',
        abbreviation: 'SNTH',
        sourceType: 'capturedHtml',
        sourceUrl: 'https://egwwritings.org/read?panels=psnth.2&index=0',
        sourceLabel: 'EGW Writings',
      );

      final preview = PioneerHtmlCaptureFolderPreview(
        folderPath: '/tmp/scans/SNTH',
        folderName: 'SNTH',
        metadata: PioneerCaptureFolderMetadata(
          title: 'Synthetic Test Work',
          abbreviation: 'SNTH',
          displayAbbreviation: 'SNTH',
          workId: work.id,
          sourceType: 'capturedHtml',
          sourceSite: 'egwwritings.org',
        ),
        htmlFiles: const ['/tmp/scans/SNTH/capture.html'],
        imageFiles: const [],
        preferredCoverImagePath: null,
        detectedTitle: 'Synthetic Test Work',
        detectedAuthor: 'Test Author',
        detectedAbbreviation: extraction.detectedAbbreviation,
        firstRef: extraction.firstRef,
        lastRef: extraction.lastRef,
        refCount: extraction.refCount,
        duplicateRefCount: extraction.duplicateRefCount,
        chapterHeadingCount: extraction.chapterHeadingCount,
        isValid: true,
        warnings: const [],
        importStatus: PioneerHtmlCaptureImportStatus.newImport,
        catalogWork: work,
        extractedText: extraction.text,
      );

      final service = PioneerTextImportService();
      final result = await service.importHtmlCaptureFolders([preview]);

      expect(result.importedCount, 1);
      expect(result.failedCount, 0);

      final db = await ELibraryDatabase.instance.database;
      final itemId = work.stableLibraryItemId;

      // library_items: exactly 1 row, no EPUB/PDF/OCR contamination
      final itemRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [itemId],
      );
      expect(itemRows, hasLength(1));
      expect(itemRows.single['source_type'], 'egw_html_capture');
      expect(itemRows.single['cover_path'], isNull);
      expect(
        itemRows.single['source_type']?.toString().toLowerCase(),
        isNot(contains('epub')),
      );
      expect(
        itemRows.single['source_type']?.toString().toLowerCase(),
        isNot(contains('pdf')),
      );
      expect(
        itemRows.single['source_type']?.toString().toLowerCase(),
        isNot(contains('ocr')),
      );
      expect(
        itemRows.single['relative_path']?.toString(),
        isNot(contains('ePubs/')),
      );
      expect(
        itemRows.single['relative_path']?.toString(),
        isNot(contains('PDFs/')),
      );

      // library_text_blocks: 3 rows (one per paragraph ref)
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        3,
      );

      // library_navigation_items: 2 rows (one per chapter heading)
      expect(
        await _countRows(
          db,
          'library_navigation_items',
          where: 'library_item_id = ? AND deleted_at IS NULL',
          whereArgs: [itemId],
        ),
        2,
      );

      // elibrary_ref_index: 5 rows (3 paragraph refs + 2 page markers)
      expect(
        await _countRows(
          db,
          'elibrary_ref_index',
          where: 'library_item_id = ?',
          whereArgs: [itemId],
        ),
        5,
      );
    },
  );

  test('HTML capture import stores generated thumbnail cover path', () async {
    final sourceCover = File(p.join(libraryRootDir.path, 'COVR-source.png'));
    await sourceCover.writeAsString('cover');

    const syntheticHtml = '''
<!doctype html><html><body>
  <div class="clip clip-text">
    <p>Chapter 1 — Opening  COVR 1  Covered paragraph. COVR 1.1</p>
  </div>
</body></html>
''';
    final extraction = const EgwHtmlCaptureExtractor().extract(syntheticHtml);
    final work = _work(
      id: 'covered_test_work',
      authorId: 'test_author',
      authorName: 'Test Author',
      title: 'Covered Test Work',
      abbreviation: 'COVR',
      sourceType: 'capturedHtml',
      sourceUrl: 'https://egwwritings.org/read?panels=pcovr.1',
      sourceLabel: 'EGW Writings',
    );
    final preview = PioneerHtmlCaptureFolderPreview(
      folderPath: '/tmp/scans/COVR',
      folderName: 'COVR',
      metadata: PioneerCaptureFolderMetadata(
        title: 'Covered Test Work',
        abbreviation: 'COVR',
        displayAbbreviation: 'COVR',
        workId: work.id,
        sourceType: 'capturedHtml',
        sourceSite: 'egwwritings.org',
        coverImagePath: sourceCover.path,
      ),
      htmlFiles: const ['/tmp/scans/COVR/capture.html'],
      imageFiles: const ['/tmp/scans/COVR/cover.png'],
      preferredCoverImagePath: sourceCover.path,
      detectedTitle: 'Covered Test Work',
      detectedAuthor: 'Test Author',
      detectedAbbreviation: extraction.detectedAbbreviation,
      firstRef: extraction.firstRef,
      lastRef: extraction.lastRef,
      refCount: extraction.refCount,
      duplicateRefCount: extraction.duplicateRefCount,
      chapterHeadingCount: extraction.chapterHeadingCount,
      isValid: true,
      warnings: const [],
      importStatus: PioneerHtmlCaptureImportStatus.newImport,
      catalogWork: work,
      extractedText: extraction.text,
    );

    final result = await PioneerTextImportService().importHtmlCaptureFolders([
      preview,
    ]);
    expect(result.importedCount, 1);

    final db = await ELibraryDatabase.instance.database;
    final itemRows = await db.query(
      'library_items',
      columns: const ['cover_path'],
      where: 'id = ?',
      whereArgs: [work.stableLibraryItemId],
    );
    expect(
      itemRows.single['cover_path'],
      p.join(
        libraryRootDir.path,
        'Graphics',
        'eLibraryCovers',
        'library_item_b8e9b7c776136591d4db_work.png',
      ),
    );
  });

  test(
    'HTML capture overwrite updates an existing item without clearing its cover path',
    () async {
      const html = '''
<!doctype html>
<html>
  <head><title>section_1the_sanctuary_cis_2026-07-01</title></head>
  <body>
    <div class="clip clip-text">
      <p>Section 1-The Sanctuary CIS 14 First paragraph. CIS 14.1</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2-The Tabernacle CIS 28 Second paragraph. CIS 28.1</p>
    </div>
  </body>
</html>
''';
      final fileHash = sha256.convert(utf8.encode(html)).toString();
      final sourceCover = File(
        p.join(libraryRootDir.path, 'CIS', 'images', 'image_0001.png'),
      );
      await sourceCover.parent.create(recursive: true);
      await sourceCover.writeAsString('cover');

      final firstExtraction = const EgwHtmlCaptureExtractor().extract(html);
      final firstPreview = PioneerHtmlCaptureFolderPreview(
        folderPath: p.join(libraryRootDir.path, 'CIS'),
        folderName: 'CIS',
        metadata: const PioneerCaptureFolderMetadata(workId: 'cis_capture'),
        htmlFiles: [p.join(libraryRootDir.path, 'CIS', 'capture.html')],
        imageFiles: [
          p.join(libraryRootDir.path, 'CIS', 'images', 'image_0001.png'),
        ],
        sourceFileHash: fileHash,
        preferredCoverImagePath: sourceCover.path,
        detectedTitle: 'Section 1-The Sanctuary',
        detectedAuthor: 'Unknown',
        detectedAbbreviation: 'CIS',
        firstRef: firstExtraction.firstRef,
        lastRef: firstExtraction.lastRef,
        refCount: firstExtraction.refCount,
        duplicateRefCount: firstExtraction.duplicateRefCount,
        chapterHeadingCount: firstExtraction.chapterHeadingCount,
        firstChapterLabel: 'Section 1 — The Sanctuary',
        lastChapterLabel: 'Chapter 2 — The Tabernacle',
        isValid: true,
        warnings: const [],
        importStatus: PioneerHtmlCaptureImportStatus.newImport,
        extractedText: firstExtraction.text,
      );

      final service = PioneerTextImportService();
      final firstResult = await service.importHtmlCaptureFolders([
        firstPreview,
      ]);
      expect(firstResult.importedCount, 1);

      final db = await ELibraryDatabase.instance.database;
      final firstItemId = firstResult.workResults.single.libraryItemId;
      final firstRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [firstItemId],
      );
      expect(firstRows, hasLength(1));
      final firstCoverPath = firstRows.single['cover_path']?.toString() ?? '';
      expect(firstCoverPath, isNotEmpty);
      expect(File(firstCoverPath).existsSync(), isTrue);

      final cisWork = _work(
        id: 'the_cross_and_its_shadow',
        authorId: 'sn_haskell',
        authorName: 'S. N. Haskell',
        title: 'The Cross and Its Shadow',
        abbreviation: 'CIS',
        sourceType: 'capturedHtml',
        sourceUrl: 'https://example.invalid/cis',
        sourceLabel: 'CaptureClipper',
      );
      final secondPreview = PioneerHtmlCaptureFolderPreview(
        folderPath: p.join(libraryRootDir.path, 'CIS'),
        folderName: 'CIS',
        metadata: const PioneerCaptureFolderMetadata(workId: 'cis_capture'),
        htmlFiles: [p.join(libraryRootDir.path, 'CIS', 'capture.html')],
        imageFiles: const [],
        sourceFileHash: fileHash,
        preferredCoverImagePath: null,
        detectedTitle: 'Section 1-The Sanctuary',
        detectedAuthor: 'Unknown',
        detectedAbbreviation: 'CIS',
        firstRef: firstExtraction.firstRef,
        lastRef: firstExtraction.lastRef,
        refCount: firstExtraction.refCount,
        duplicateRefCount: firstExtraction.duplicateRefCount,
        chapterHeadingCount: firstExtraction.chapterHeadingCount,
        firstChapterLabel: 'Section 1 — The Sanctuary',
        lastChapterLabel: 'Chapter 2 — The Tabernacle',
        isValid: true,
        warnings: const [],
        importStatus: PioneerHtmlCaptureImportStatus.overwriteAvailable,
        catalogWork: cisWork,
        extractedText: firstExtraction.text,
      );

      final secondResult = await service.importHtmlCaptureFolders([
        secondPreview,
      ], existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting);

      expect(secondResult.importedCount, 1);
      expect(secondResult.workResults.single.createdNew, isFalse);
      expect(secondResult.workResults.single.existingItemUpdated, isTrue);

      final secondRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [firstItemId],
      );
      expect(secondRows, hasLength(1));
      expect(secondRows.single['title'], 'The Cross and Its Shadow');
      expect(secondRows.single['author'], 'S. N. Haskell');
      expect(secondRows.single['cover_path'], firstCoverPath);
    },
  );

  test('browser overwrite removes copied-range sibling item', () async {
    final work = _sourceNeededWork(
      id: 'daniel_and_the_revelation',
      authorId: 'uriah_smith',
      authorName: 'Uriah Smith',
      title: 'Daniel and the Revelation',
      abbreviation: 'DAR',
    );
    final db = await ELibraryDatabase.instance.database;
    await db.insert('library_items', <String, Object?>{
      'id': work.copiedRangeLibraryItemId,
      'title': work.title,
      'author': work.authorName,
      'file_name': 'DAR.copied-range.html',
      'relative_path':
          'TextCaptures/Research/Pioneer Authors/uriah_smith/copied_range/DAR.copied-range.html',
      'file_hash': 'old',
      'file_size': 3,
      'mime_type': 'text/plain',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Adventist Pioneer Library',
      'source_site': 'egwwritings.org',
      'source_url': 'EGW Writings copied range',
      'source_type': 'egw_copied_range',
      'date_added': '2026-06-25T00:00:00Z',
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
      'device_id': 'device-1',
      'index_status': 'partially_imported',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    });
    await db.insert('library_text_blocks', <String, Object?>{
      'library_item_id': work.copiedRangeLibraryItemId,
      'epub_href': 'copied_range/chapter_1.html',
      'spine_index': 1,
      'paragraph_index': 1,
      'paragraph_on_section': 1,
      'section_title': 'Chapter 1',
      'plain_text': 'Old copied range text.',
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
    });

    final service = PioneerTextImportService();
    final result = await service.importFromCapturedHtml(
      work: work,
      html:
          '<html><body><h1>CHAPTER 1</h1><p>Fresh browser DAR 7.3 text.</p></body></html>',
      sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
      sourceLabel: 'EGW Writings',
      existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
    );

    expect(result.importedCount, 1);
    expect(
      await _countRows(
        db,
        'library_items',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [work.copiedRangeLibraryItemId],
      ),
      0,
    );
    expect(
      await _countRows(
        db,
        'library_items',
        where: 'id = ? AND deleted_at IS NOT NULL',
        whereArgs: [work.copiedRangeLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        db,
        'library_items',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [work.stableLibraryItemId],
      ),
      1,
    );
    expect(
      await _countRows(
        db,
        'library_text_blocks',
        where: 'library_item_id = ? AND plain_text LIKE ?',
        whereArgs: [work.stableLibraryItemId, '%Fresh browser%'],
      ),
      1,
    );
  });

  test(
    'schema-2 package lineage persists and rejects a different package',
    () async {
      final work = _sourceNeededWork(
        id: 'lineage_test_work',
        authorId: 'test_author',
        authorName: 'Test Author',
        title: 'Lineage Test Work',
        abbreviation: 'LTW',
      );
      PioneerHtmlCaptureFolderPreview preview(String packageId, String hash) {
        final extraction = const EgwHtmlCaptureExtractor().extract('''
<div class="clip clip-text">
  <p>Chapter 1 — Lineage LTW 1 Lineage text. LTW 1.1</p>
</div>
''');
        return PioneerHtmlCaptureFolderPreview(
          folderPath: p.join(libraryRootDir.path, 'LTW'),
          folderName: 'LTW',
          metadata: PioneerCaptureFolderMetadata(
            schemaVersion: 2,
            workId: work.id,
            packageId: packageId,
            contentHash: hash,
          ),
          htmlFiles: [p.join(libraryRootDir.path, 'LTW', 'capture.html')],
          imageFiles: const [],
          preferredCoverImagePath: null,
          sourceFileHash: hash,
          detectedTitle: work.title,
          detectedAuthor: work.authorName,
          detectedAbbreviation: work.abbreviation,
          firstRef: 'LTW 1.1',
          lastRef: 'LTW 1.1',
          refCount: 1,
          duplicateRefCount: 0,
          chapterHeadingCount: 1,
          isValid: true,
          warnings: const [],
          importStatus: PioneerHtmlCaptureImportStatus.newImport,
          catalogWork: work,
          extractedText: extraction.text,
        );
      }

      final service = PioneerTextImportService();
      final first = await service.importHtmlCaptureFolders([
        preview('captureclipper:LTW', 'hash-one'),
      ]);
      expect(first.importedCount, 1);
      final itemId = first.workResults.single.libraryItemId;
      final db = await ELibraryDatabase.instance.database;
      var rows = await db.query(
        'library_items',
        columns: const [
          'id',
          'source_work_id',
          'source_package_id',
          'file_hash',
        ],
        where: 'id = ?',
        whereArgs: [itemId],
      );
      expect(rows.single['source_work_id'], work.id);
      expect(rows.single['source_package_id'], 'captureclipper:LTW');
      expect(rows.single['file_hash'], 'hash-one');

      await ELibraryDatabase.instance.close();
      final reopened = await ELibraryDatabase.instance.database;
      rows = await reopened.query(
        'library_items',
        columns: const ['source_package_id'],
        where: 'id = ?',
        whereArgs: [itemId],
      );
      expect(rows.single['source_package_id'], 'captureclipper:LTW');

      final unchanged = await service.importHtmlCaptureFolders([
        preview('captureclipper:LTW', 'hash-one'),
      ]);
      expect(
        unchanged.workResults.single.status,
        PioneerImportWorkStatus.skippedExisting,
      );

      final changed = await service.importHtmlCaptureFolders([
        preview('captureclipper:LTW', 'hash-two'),
      ]);
      expect(changed.importedCount, 1);
      expect(changed.workResults.single.libraryItemId, itemId);
      expect(changed.workResults.single.existingItemUpdated, isTrue);

      final conflict = await service.importHtmlCaptureFolders([
        preview('captureclipper:OTHER', 'hash-three'),
      ]);
      expect(
        conflict.workResults.single.status,
        PioneerImportWorkStatus.packageLineageConflict,
      );
      expect(conflict.workResults.single.insertedLibraryItems, 0);
      rows = await reopened.query(
        'library_items',
        columns: const ['id', 'source_package_id', 'file_hash'],
        where: 'source_work_id = ?',
        whereArgs: [work.id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['id'], itemId);
      expect(rows.single['source_package_id'], 'captureclipper:LTW');
      expect(rows.single['file_hash'], 'hash-two');
    },
  );

  test('legacy item adopts schema-2 package lineage in place', () async {
    final work = _sourceNeededWork(
      id: 'legacy_lineage_work',
      authorId: 'test_author',
      authorName: 'Test Author',
      title: 'Legacy Lineage Work',
      abbreviation: 'LLW',
    );
    final db = await ELibraryDatabase.instance.database;
    await db.insert('library_items', <String, Object?>{
      'id': work.stableLibraryItemId,
      'title': work.title,
      'author': work.authorName,
      'file_name': 'capture.html',
      'relative_path': 'TextCaptures/LLW/capture.html',
      'file_hash': 'legacy-hash',
      'file_format': 'html',
      'source_type': 'egw_html_capture',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'device_id': 'device-1',
    });
    final extraction = const EgwHtmlCaptureExtractor().extract('''
<div class="clip clip-text">
  <p>Chapter 1 — Upgrade LLW 1 Upgraded text. LLW 1.1</p>
</div>
''');
    final preview = PioneerHtmlCaptureFolderPreview(
      folderPath: p.join(libraryRootDir.path, 'LLW'),
      folderName: 'LLW',
      metadata: PioneerCaptureFolderMetadata(
        schemaVersion: 2,
        workId: work.id,
        packageId: 'captureclipper:LLW',
      ),
      htmlFiles: [p.join(libraryRootDir.path, 'LLW', 'capture.html')],
      imageFiles: const [],
      preferredCoverImagePath: null,
      sourceFileHash: 'schema-two-hash',
      detectedTitle: work.title,
      detectedAuthor: work.authorName,
      detectedAbbreviation: work.abbreviation,
      firstRef: 'LLW 1.1',
      lastRef: 'LLW 1.1',
      refCount: 1,
      duplicateRefCount: 0,
      chapterHeadingCount: 1,
      isValid: true,
      warnings: const [],
      importStatus: PioneerHtmlCaptureImportStatus.overwriteAvailable,
      catalogWork: work,
      extractedText: extraction.text,
    );
    final result = await PioneerTextImportService().importHtmlCaptureFolders([
      preview,
    ]);
    expect(result.importedCount, 1);
    expect(result.workResults.single.libraryItemId, work.stableLibraryItemId);
    expect(result.workResults.single.createdNew, isFalse);
    final rows = await db.query(
      'library_items',
      columns: const ['id', 'source_work_id', 'source_package_id'],
      where: 'id = ?',
      whereArgs: [work.stableLibraryItemId],
    );
    expect(rows, hasLength(1));
    expect(rows.single['source_work_id'], work.id);
    expect(rows.single['source_package_id'], 'captureclipper:LLW');
  });

  test(
    'CaptureClipper indexing failure preserves a retryable imported item',
    () async {
      final work = _sourceNeededWork(
        id: 'index_retry_work',
        authorId: 'test_author',
        authorName: 'Test Author',
        title: 'Index Retry Work',
        abbreviation: 'IRW',
      );
      final extraction = const EgwHtmlCaptureExtractor().extract('''
<div class="clip clip-text">
  <p>Chapter 1 — Retry IRW 1 Searchable retry text. IRW 1.1</p>
</div>
''');
      final preview = PioneerHtmlCaptureFolderPreview(
        folderPath: p.join(libraryRootDir.path, 'IRW'),
        folderName: 'IRW',
        metadata: PioneerCaptureFolderMetadata(
          schemaVersion: 2,
          workId: work.id,
          packageId: 'captureclipper:IRW',
          contentHash: 'retry-hash',
        ),
        htmlFiles: [p.join(libraryRootDir.path, 'IRW', 'capture.html')],
        imageFiles: const [],
        preferredCoverImagePath: null,
        sourceFileHash: 'retry-hash',
        detectedTitle: work.title,
        detectedAuthor: work.authorName,
        detectedAbbreviation: work.abbreviation,
        firstRef: 'IRW 1.1',
        lastRef: 'IRW 1.1',
        refCount: 1,
        duplicateRefCount: 0,
        chapterHeadingCount: 1,
        isValid: true,
        warnings: const [],
        importStatus: PioneerHtmlCaptureImportStatus.newImport,
        catalogWork: work,
        extractedText: extraction.text,
      );

      final failed = await PioneerTextImportService(
        beforeCapturedHtmlIndexWrite: (_) async {
          throw StateError('simulated indexing failure');
        },
      ).importHtmlCaptureFolders([preview]);
      expect(failed.failedCount, 1);

      final db = await ELibraryDatabase.instance.database;
      var itemRows = await db.query(
        'library_items',
        columns: const [
          'id',
          'source_package_id',
          'file_hash',
          'index_status',
          'index_error',
        ],
        where: 'id = ?',
        whereArgs: [work.stableLibraryItemId],
      );
      expect(itemRows, hasLength(1));
      expect(itemRows.single['source_package_id'], 'captureclipper:IRW');
      expect(itemRows.single['file_hash'], 'retry-hash');
      expect(itemRows.single['index_status'], 'needs_attention');
      expect(
        itemRows.single['index_error'],
        contains('simulated indexing failure'),
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [work.stableLibraryItemId],
        ),
        0,
      );

      final retried = await PioneerTextImportService().importHtmlCaptureFolders(
        [preview],
      );
      expect(retried.importedCount, 1);
      expect(
        retried.workResults.single.libraryItemId,
        work.stableLibraryItemId,
      );
      itemRows = await db.query(
        'library_items',
        columns: const ['index_status', 'index_error'],
        where: 'id = ?',
        whereArgs: [work.stableLibraryItemId],
      );
      expect(itemRows.single['index_status'], 'indexed');
      expect(itemRows.single['index_error'], isNull);
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ? AND plain_text LIKE ?',
          whereArgs: [work.stableLibraryItemId, '%Searchable retry text%'],
        ),
        1,
      );
    },
  );
}
