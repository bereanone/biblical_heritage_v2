import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/utilities/data/epub_storage_policy_service.dart';

Uint8List _epubBytes(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

/// Builds a structurally complete EPUB (container.xml -> OPF -> spine) so
/// tests can exercise the canonical reader's happy path under the same
/// structural gate [EpubDownloadValidator] enforces at download time.
Uint8List _wellFormedEpubBytes({
  required Map<String, String> chapters,
  String title = 'Test Book',
}) {
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();
  var index = 0;
  for (final href in chapters.keys) {
    final id = 'chap$index';
    manifestItems.writeln(
      '<item id="$id" href="$href" media-type="application/xhtml+xml"/>',
    );
    spineItems.writeln('<itemref idref="$id"/>');
    index++;
  }
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
  </metadata>
  <manifest>
    $manifestItems
  </manifest>
  <spine>
    $spineItems
  </spine>
</package>
''';
  final files = <String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
  };
  chapters.forEach((href, html) {
    files['OEBPS/$href'] = html.codeUnits;
  });
  return _epubBytes(files);
}

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

LibraryCatalogItem _managedEpubItem({
  required String id,
  required String relativePath,
  String sourceType = 'official_download',
  String fileFormat = 'epub',
}) => LibraryCatalogItem(
  id: id,
  title: 'Managed Book',
  author: 'Managed Author',
  fileName: p.basename(relativePath),
  fileHash: null,
  relativePath: relativePath,
  fileFormat: fileFormat,
  folderType: 'research',
  libraryRole: 'research',
  collectionName: 'EGW Books',
  sourceSite: 'egwwritings.org',
  sourceUrl: null,
  sourceType: sourceType,
  coverPath: null,
  dateAdded: null,
  lastOpened: null,
  indexStatus: 'metadata_only',
  fileSize: null,
  mimeType: null,
  spineIndex: null,
  anchorId: null,
  epubHref: null,
  paragraphIndex: null,
  navigationCount: 0,
  sourceWorkId: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('saved canonical front matter cannot override substantive opening', () {
    expect(
      canonicalSavedOrderIsSubstantive(savedOrder: 0, openingOrder: 4),
      isFalse,
    );
    expect(
      canonicalSavedOrderIsSubstantive(savedOrder: 4, openingOrder: 4),
      isTrue,
    );
    expect(
      canonicalSavedOrderIsSubstantive(savedOrder: 27, openingOrder: 4),
      isTrue,
    );
  });

  late Directory supportDir;
  late Directory documentsDir;
  late Directory rootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('pilot_epub_support_');
    documentsDir = await Directory.systemTemp.createTemp(
      'pilot_epub_documents_',
    );
    rootDir = await Directory.systemTemp.createTemp('pilot_epub_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: rootDir.path);
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
    for (final dir in <Directory>[supportDir, documentsDir, rootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test(
    'a non-EPUB managed item is never routed through the canonical EPUB reader',
    () async {
      final relativePath = p.join('PDFs', 'EGW', 'EGW_Books', 'unpiloted.pdf');
      final item = _managedEpubItem(
        id: 'NOT_EPUB',
        relativePath: relativePath,
        fileFormat: 'pdf',
      );

      final preparation = await prepareCanonicalEpubReader(item);

      expect(preparation, isNull);
    },
  );

  test(
    'an EPUB outside official managed storage is never routed through the canonical EPUB reader',
    () async {
      final relativePath = p.join('Imports', 'user_uploaded.epub');
      final epubFile = File(p.join(rootDir.path, relativePath));
      epubFile.parent.createSync(recursive: true);
      epubFile.writeAsBytesSync(
        _epubBytes(<String, List<int>>{
          'OEBPS/ch1.xhtml': '<h2>Chapter 1</h2><p>Body text.</p>'.codeUnits,
        }),
      );
      final item = _managedEpubItem(
        id: 'UNMANAGED_EPUB',
        relativePath: relativePath,
        sourceType: 'user_import',
      );

      expect(supportsCanonicalEpubReader(item), isFalse);
      final preparation = await prepareCanonicalEpubReader(item);
      expect(preparation, isNull);
    },
  );

  test(
    'a pioneer_archive_org_download EPUB in ImportedPioneerEpubs is eligible '
    'for the canonical reader the same as pioneer_epub_import (both write '
    'into the same folder; the source-type label must not gate routing)',
    () async {
      final relativePath = p.join('ImportedPioneerEpubs', 'Some Book.epub');
      final item = _managedEpubItem(
        id: 'ARCHIVE_ORG_ITEM',
        relativePath: relativePath,
        sourceType: 'pioneer_archive_org_download',
      );

      expect(supportsCanonicalEpubReader(item), isTrue);
    },
  );

  test(
    'a pioneer_archive_org_download EPUB outside ImportedPioneerEpubs is '
    'still ineligible — the folder-path check still applies',
    () async {
      final relativePath = p.join('Imports', 'archive_org_download.epub');
      final item = _managedEpubItem(
        id: 'ARCHIVE_ORG_OUTSIDE',
        relativePath: relativePath,
        sourceType: 'pioneer_archive_org_download',
      );

      expect(supportsCanonicalEpubReader(item), isFalse);
    },
  );

  test(
    'a managed EPUB that fails validation keeps the EPUB and does not open canonically',
    () async {
      final relativePath = p.join('ePubs', 'EGW', 'EGW_Books', 'blank.epub');
      final epubFile = File(p.join(rootDir.path, relativePath));
      epubFile.parent.createSync(recursive: true);
      epubFile.writeAsBytesSync(
        _epubBytes(<String, List<int>>{'OEBPS/ch1.xhtml': '<hr>'.codeUnits}),
      );
      final item = _managedEpubItem(
        id: 'BLANK_ITEM',
        relativePath: relativePath,
      );

      expect(supportsCanonicalEpubReader(item), isTrue);
      final preparation = await prepareCanonicalEpubReader(item);

      expect(preparation, isNull);
      expect(epubFile.existsSync(), isTrue);
    },
  );

  test(
    'a validated managed EPUB is removed under a remove-after-indexing preference and reopens without the EPUB',
    () async {
      await EpubStoragePolicyService.instance
          .saveDesktopEpubRetentionPreference(
            EpubRetentionPreference.removeAfterIndexing,
          );
      final relativePath = p.join('ePubs', 'EGW', 'EGW_Books', 'good.epub');
      final epubFile = File(p.join(rootDir.path, relativePath));
      epubFile.parent.createSync(recursive: true);
      epubFile.writeAsBytesSync(
        _wellFormedEpubBytes(
          chapters: <String, String>{
            'ch1.xhtml': '<h2>Chapter 1</h2><p>Body text.</p>',
          },
        ),
      );
      final item = _managedEpubItem(
        id: 'GOOD_ITEM',
        relativePath: relativePath,
      );
      final seedDb = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await seedDb.insert('library_items', <String, Object?>{
        'id': item.id,
        'title': item.title,
        'file_name': item.fileName,
        'relative_path': item.relativePath,
        'file_format': 'epub',
        'source_type': 'official_download',
        'collection_name': item.collectionName,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });

      final firstOpen = await prepareCanonicalEpubReader(item);
      expect(firstOpen, isNotNull);
      expect(epubFile.existsSync(), isFalse);

      final db = await ELibraryDatabase.instance.database;
      final blockCountBefore = (await db.rawQuery(
        'SELECT COUNT(*) FROM library_document_blocks WHERE library_item_id = ?',
        <Object?>[item.id],
      )).first.values.first;
      expect((blockCountBefore as num).toInt(), greaterThan(0));

      // Reopening after removal must not need the archive at all, and must
      // not create a second visible item/row.
      final secondOpen = await prepareCanonicalEpubReader(item);
      expect(secondOpen, isNotNull);
      final itemRows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: <Object?>[item.id],
      );
      expect(itemRows, hasLength(1));
      expect(itemRows.single['epub_storage_state'], 'removed_after_index');
    },
  );
}
