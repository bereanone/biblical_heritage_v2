import 'dart:convert';
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
import 'package:studybible2/features/library/data/library_item_identity.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

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

/// Builds an in-memory ZIP/EPUB from a map of archive entry path -> text
/// content, so each test can assemble only the pieces relevant to the
/// structural condition under test.
File _writeEpub(File file, Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoded = ZipEncoder().encode(archive);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(encoded);
  return file;
}

const _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

String _opfXml({required bool includeSpine}) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata>
    <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title>
  </metadata>
  <manifest>
    <item id="content1" href="content1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    ${includeSpine ? '<itemref idref="content1"/>' : ''}
  </spine>
</package>
''';

const _healthyContentXhtml = '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter One</title></head>
<body>
<h1>Chapter One</h1>
<p>In the beginning God created the heaven and the earth, as recorded in Genesis 1:1.</p>
<p>This is a second paragraph with more narrative text describing the scene in detail.</p>
</body>
</html>
''';

const _emptyContentXhtml = '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter One</title></head>
<body>
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
    supportDir = await Directory.systemTemp.createTemp(
      'epub_validation_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'epub_validation_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'epub_validation_root_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
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

  // `_indexFile` recomputes the library_items primary key from
  // (folderType, relativePath) via `canonicalLibraryItemId` rather than
  // trusting whatever id the row was seeded with, so the seed must use that
  // same canonical id or the indexing write lands on a different row than
  // the one the test is asserting against.
  Future<({String itemId, String relativePath})> seedCatalogRow({
    required String fileName,
  }) async {
    const folderType = 'research';
    final relativePath = p.join('ePubs', 'EGW_Books', fileName);
    final itemId = canonicalLibraryItemId(
      folderType: folderType,
      relativePath: relativePath,
    );
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': fileName,
      'file_name': fileName,
      'relative_path': relativePath,
      'file_format': 'epub',
      'folder_type': folderType,
      'library_role': folderType,
      'collection_name': 'EGW_Books',
      'source_type': 'official_download',
      'index_status': 'metadata_only',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return (itemId: itemId, relativePath: relativePath);
  }

  Future<Map<String, Object?>> indexAndFetchStatus(String itemId) async {
    await CommentaryResearchLibraryService.instance.indexLocalCatalogedEpubs();
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      columns: const ['index_status', 'index_error'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    return rows.first;
  }

  Future<int> textBlockCount(String itemId) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_text_blocks',
      where: 'library_item_id = ?',
      whereArgs: [itemId],
    );
    return rows.length;
  }

  test(
    'retained EPUB recovery discovers and indexes the explicit download root',
    () async {
      final retainedRoot = Directory(p.join(supportDir.path, 'retained_root'));
      final retainedFile = _writeEpub(
        File(
          p.join(
            retainedRoot.path,
            'ePubs',
            'EGW',
            'EGW_Books',
            'en_Test.epub',
          ),
        ),
        {
          'META-INF/container.xml': _containerXml,
          'OEBPS/content.opf': _opfXml(includeSpine: true),
          'OEBPS/content1.xhtml': _healthyContentXhtml,
        },
      );

      final discovered = await LibraryCatalogService.instance
          .refreshManagedItemsFromDisk(rootPathOverride: retainedRoot.path);
      final candidates = await LibraryCatalogService.instance
          .listUnindexedManagedItems();
      final result = await CommentaryResearchLibraryService.instance
          .indexLocalCatalogedEpubs(rootPathOverride: retainedRoot.path);

      expect(await retainedFile.exists(), isTrue);
      expect(discovered, 1);
      expect(candidates, hasLength(1));
      expect(result, (indexed: 1, skipped: 0, failed: 0));

      final db = await ELibraryDatabase.instance.database;
      final rows = await db.query(
        'library_items',
        columns: const ['index_status'],
        where: 'file_name = ?',
        whereArgs: const ['en_Test.epub'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['index_status'], 'indexed');

      await LibraryCatalogService.instance.refreshManagedItemsFromDisk(
        rootPathOverride: retainedRoot.path,
      );
      final repeated = await CommentaryResearchLibraryService.instance
          .indexLocalCatalogedEpubs(rootPathOverride: retainedRoot.path);
      final duplicateRows = await db.query(
        'library_items',
        where: 'file_name = ?',
        whereArgs: const ['en_Test.epub'],
      );
      expect(repeated, (indexed: 0, skipped: 0, failed: 0));
      expect(duplicateRows, hasLength(1));
    },
  );

  test('missing OPF is flagged needs_attention, not indexed_empty', () async {
    final seeded = await seedCatalogRow(fileName: 'missing_opf.epub');
    _writeEpub(File(p.join(libraryRootDir.path, seeded.relativePath)), {
      'META-INF/container.xml': _containerXml,
      // No OEBPS/content.opf entry, mirroring the real en_IC.epub/en_COS.epub
      // shells: container.xml references it, but the archive never
      // actually contains it.
      'OEBPS/toc.html': '<html><body><p>Table of Contents</p></body></html>',
    });

    final status = await indexAndFetchStatus(seeded.itemId);
    expect(status['index_status'], 'needs_attention');
    expect(status['index_error'], contains('OPF'));
    expect(await textBlockCount(seeded.itemId), 0);
  });

  test('empty spine is flagged needs_attention', () async {
    final seeded = await seedCatalogRow(fileName: 'empty_spine.epub');
    _writeEpub(File(p.join(libraryRootDir.path, seeded.relativePath)), {
      'META-INF/container.xml': _containerXml,
      'OEBPS/content.opf': _opfXml(includeSpine: false),
      'OEBPS/content1.xhtml': _healthyContentXhtml,
    });

    final status = await indexAndFetchStatus(seeded.itemId);
    expect(status['index_status'], 'needs_attention');
    expect(status['index_error'], contains('spine'));
    expect(await textBlockCount(seeded.itemId), 0);
  });

  test(
    'zero readable sections after parsing is flagged needs_attention',
    () async {
      final seeded = await seedCatalogRow(fileName: 'zero_sections.epub');
      _writeEpub(File(p.join(libraryRootDir.path, seeded.relativePath)), {
        'META-INF/container.xml': _containerXml,
        'OEBPS/content.opf': _opfXml(includeSpine: true),
        // Structurally valid (OPF + spine + the referenced document exists)
        // but the document itself has no extractable paragraph/heading text.
        'OEBPS/content1.xhtml': _emptyContentXhtml,
      });

      final status = await indexAndFetchStatus(seeded.itemId);
      expect(status['index_status'], 'needs_attention');
      expect(
        status['index_error'],
        'No readable text content found after parsing.',
      );
      expect(await textBlockCount(seeded.itemId), 0);
    },
  );

  test('a healthy EPUB is never marked needs_attention', () async {
    final seeded = await seedCatalogRow(fileName: 'healthy.epub');
    _writeEpub(File(p.join(libraryRootDir.path, seeded.relativePath)), {
      'META-INF/container.xml': _containerXml,
      'OEBPS/content.opf': _opfXml(includeSpine: true),
      'OEBPS/content1.xhtml': _healthyContentXhtml,
    });

    final status = await indexAndFetchStatus(seeded.itemId);
    expect(status['index_status'], isNot('needs_attention'));
    expect(status['index_error'], isNull);
    expect(await textBlockCount(seeded.itemId), greaterThan(0));
  });
}
