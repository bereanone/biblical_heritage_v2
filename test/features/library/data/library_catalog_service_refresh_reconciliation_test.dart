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

/// Covers the refresh/discovery reconciliation contract in
/// `LibraryCatalogService.refreshManagedItemsFromDisk`: soft-retired rows
/// must never be resurrected by file presence alone, an active
/// `needs_attention` row must never be silently downgraded back to
/// `metadata_only` by a refresh pass, and a brand-new structurally invalid
/// EPUB (the exact shape of the real `en_IC.epub`/`en_COS.epub` shells) must
/// never render as readable even transiently.
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

const _opfXml = '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata>
    <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test Book</dc:title>
  </metadata>
  <manifest>
    <item id="content1" href="content1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="content1"/>
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

/// Writes a *valid, healthy* managed EPUB.
File _writeHealthyEpub(File file) {
  return _writeEpub(file, {
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opfXml,
    'OEBPS/content1.xhtml': _healthyContentXhtml,
  });
}

/// Writes the exact placeholder shape the real `en_IC.epub`/`en_COS.epub`
/// shells have: `container.xml` references an OPF that was never actually
/// packaged into the archive.
File _writePlaceholderEpub(File file) {
  return _writeEpub(file, {
    'META-INF/container.xml': _containerXml,
    'OEBPS/toc.html': '<html><body><p>Table of Contents</p></body></html>',
  });
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
      'refresh_reconciliation_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'refresh_reconciliation_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'refresh_reconciliation_root_',
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

  const folderType = 'research';
  const collectionName = 'EGW Books';

  String currentRelativePath(String fileName) =>
      p.join('ePubs', 'EGW', 'EGW_Books', fileName);
  String legacyRelativePath(String fileName) =>
      p.join('ePubs', 'Research', 'EGW_Books', fileName);

  Future<String> seedRow({
    required String relativePath,
    String? id,
    String? deletedAt,
    String indexStatus = 'metadata_only',
    String? indexError,
    String? sourceWorkId,
    String fileFormat = 'epub',
  }) async {
    final itemId =
        id ??
        canonicalLibraryItemId(
          folderType: folderType,
          relativePath: relativePath,
        );
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': p.basenameWithoutExtension(relativePath),
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': fileFormat,
      'folder_type': folderType,
      'library_role': folderType,
      'collection_name': collectionName,
      'source_type': 'official_download',
      'source_work_id': sourceWorkId,
      'index_status': indexStatus,
      'index_error': indexError,
      'deleted_at': deletedAt,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return itemId;
  }

  Future<Map<String, Object?>?> fetchRow(String itemId) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> fetchRowsByRelativePath(
    String relativePath,
  ) async {
    final db = await ELibraryDatabase.instance.database;
    return db.query(
      'library_items',
      where: 'LOWER(relative_path) = ?',
      whereArgs: [relativePath.toLowerCase()],
    );
  }

  Future<int> refresh() => LibraryCatalogService.instance
      .refreshManagedItemsFromDisk(rootPathOverride: libraryRootDir.path);

  test(
    'refresh does not clear deleted_at on a soft-retired duplicate',
    () async {
      final relativePath = currentRelativePath('en_COS.epub');
      _writePlaceholderEpub(File(p.join(libraryRootDir.path, relativePath)));
      final retiredAt = DateTime.now().toUtc().toIso8601String();
      final itemId = await seedRow(
        relativePath: relativePath,
        deletedAt: retiredAt,
        indexStatus: 'metadata_only',
        sourceWorkId: 'COS',
      );

      await refresh();

      final row = await fetchRow(itemId);
      expect(row, isNotNull);
      expect(row!['deleted_at'], retiredAt);
    },
  );

  test(
    'refresh does not create a replacement active row for a soft-retired duplicate',
    () async {
      final relativePath = currentRelativePath('en_IC.epub');
      _writePlaceholderEpub(File(p.join(libraryRootDir.path, relativePath)));
      await seedRow(
        relativePath: relativePath,
        deletedAt: DateTime.now().toUtc().toIso8601String(),
        indexStatus: 'metadata_only',
        sourceWorkId: 'IC',
      );

      await refresh();
      await refresh();

      final rows = await fetchRowsByRelativePath(relativePath);
      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNotNull);
    },
  );

  test(
    'an active needs_attention EPUB remains needs_attention after refresh',
    () async {
      final relativePath = currentRelativePath('en_IC.epub');
      _writePlaceholderEpub(File(p.join(libraryRootDir.path, relativePath)));
      final itemId = await seedRow(
        relativePath: relativePath,
        indexStatus: 'needs_attention',
        indexError: 'Structurally invalid EPUB (missingOpf): pre-existing.',
        sourceWorkId: 'IC',
      );

      await refresh();

      final row = await fetchRow(itemId);
      expect(row!['index_status'], 'needs_attention');
      expect(row['deleted_at'], isNull);
    },
  );

  test(
    'a structurally invalid existing EPUB is not downgraded to metadata_only merely because the file exists',
    () async {
      final relativePath = currentRelativePath('en_COS.epub');
      // The file on disk is healthy — refresh must still leave the prior
      // needs_attention verdict alone; only a real indexing pass may change
      // it, never a metadata refresh.
      _writeHealthyEpub(File(p.join(libraryRootDir.path, relativePath)));
      final itemId = await seedRow(
        relativePath: relativePath,
        indexStatus: 'needs_attention',
        indexError: 'Structurally invalid EPUB (missingOpf): pre-existing.',
        sourceWorkId: 'COS',
      );

      await refresh();

      final row = await fetchRow(itemId);
      expect(row!['index_status'], 'needs_attention');
    },
  );

  test(
    'a newly discovered placeholder EPUB is classified needs_attention immediately',
    () async {
      final relativePath = currentRelativePath('en_COS.epub');
      _writePlaceholderEpub(File(p.join(libraryRootDir.path, relativePath)));

      final touched = await refresh();

      expect(touched, 1);
      final rows = await fetchRowsByRelativePath(relativePath);
      expect(rows, hasLength(1));
      expect(rows.single['index_status'], 'needs_attention');
      expect(rows.single['index_error'], contains('Structurally invalid EPUB'));
    },
  );

  test('file presence alone does not make an item normally readable', () async {
    final validPath = currentRelativePath('en_valid.epub');
    final invalidPath = currentRelativePath('en_COS.epub');
    _writeHealthyEpub(File(p.join(libraryRootDir.path, validPath)));
    _writePlaceholderEpub(File(p.join(libraryRootDir.path, invalidPath)));

    await refresh();

    final items = await LibraryCatalogService.instance.loadItems(
      folderRoot: 'all',
    );
    final fileNames = items.map((item) => item.fileName).toSet();
    expect(fileNames, contains('en_valid.epub'));
    expect(fileNames, isNot(contains('en_COS.epub')));
  });

  test(
    'current and legacy path duplicates collapse to one active maintenance identity',
    () async {
      _writePlaceholderEpub(
        File(p.join(libraryRootDir.path, currentRelativePath('en_IC.epub'))),
      );
      _writePlaceholderEpub(
        File(p.join(libraryRootDir.path, legacyRelativePath('en_IC.epub'))),
      );

      await refresh();

      final needsAttention = await LibraryCatalogService.instance
          .listNeedsAttentionManagedItems();
      final icEntries = needsAttention
          .where((item) => item.sourceWorkId == 'IC')
          .toList();
      expect(icEntries, hasLength(1));
    },
  );

  test('COS remains hidden after one refresh', () async {
    _writePlaceholderEpub(
      File(p.join(libraryRootDir.path, currentRelativePath('en_COS.epub'))),
    );
    await refresh();

    final items = await LibraryCatalogService.instance.loadItems(
      folderRoot: 'all',
    );
    expect(items.any((item) => item.fileName == 'en_COS.epub'), isFalse);
  });

  test('COS remains hidden after repeated refreshes', () async {
    final path = currentRelativePath('en_COS.epub');
    _writePlaceholderEpub(File(p.join(libraryRootDir.path, path)));

    for (var i = 0; i < 4; i++) {
      await refresh();
    }

    final items = await LibraryCatalogService.instance.loadItems(
      folderRoot: 'all',
    );
    expect(items.any((item) => item.fileName == 'en_COS.epub'), isFalse);
    final rows = await fetchRowsByRelativePath(path);
    expect(rows, hasLength(1));
    expect(rows.single['index_status'], 'needs_attention');
  });

  test('IC remains hidden after one refresh', () async {
    _writePlaceholderEpub(
      File(p.join(libraryRootDir.path, currentRelativePath('en_IC.epub'))),
    );
    await refresh();

    final items = await LibraryCatalogService.instance.loadItems(
      folderRoot: 'all',
    );
    expect(items.any((item) => item.fileName == 'en_IC.epub'), isFalse);
  });

  test('IC remains hidden after repeated refreshes', () async {
    final path = currentRelativePath('en_IC.epub');
    _writePlaceholderEpub(File(p.join(libraryRootDir.path, path)));

    for (var i = 0; i < 4; i++) {
      await refresh();
    }

    final items = await LibraryCatalogService.instance.loadItems(
      folderRoot: 'all',
    );
    expect(items.any((item) => item.fileName == 'en_IC.epub'), isFalse);
    final rows = await fetchRowsByRelativePath(path);
    expect(rows, hasLength(1));
    expect(rows.single['index_status'], 'needs_attention');
  });

  test(
    'Books/List/Recent/Search-facing loadItems stays free of COS/IC shells across repeated refresh',
    () async {
      _writeHealthyEpub(
        File(p.join(libraryRootDir.path, currentRelativePath('en_valid.epub'))),
      );
      _writePlaceholderEpub(
        File(p.join(libraryRootDir.path, currentRelativePath('en_COS.epub'))),
      );
      _writePlaceholderEpub(
        File(p.join(libraryRootDir.path, currentRelativePath('en_IC.epub'))),
      );

      for (var i = 0; i < 3; i++) {
        await refresh();
      }

      final items = await LibraryCatalogService.instance.loadItems(
        folderRoot: 'all',
      );
      final fileNames = items.map((item) => item.fileName).toSet();
      expect(fileNames, contains('en_valid.epub'));
      expect(fileNames, isNot(contains('en_COS.epub')));
      expect(fileNames, isNot(contains('en_IC.epub')));
    },
  );

  test('valid EPUBs continue refreshing normally', () async {
    final relativePath = currentRelativePath('en_valid.epub');
    _writeHealthyEpub(File(p.join(libraryRootDir.path, relativePath)));

    final touched = await refresh();
    expect(touched, 1);

    final rows = await fetchRowsByRelativePath(relativePath);
    expect(rows, hasLength(1));
    expect(rows.single['index_status'], 'metadata_only');

    final repeated = await refresh();
    expect(repeated, 0);
    final rowsAfterSecondRefresh = await fetchRowsByRelativePath(relativePath);
    expect(rowsAfterSecondRefresh, hasLength(1));
  });

  test(
    'a valid CaptureClipper HTML book row is untouched by managed EPUB/PDF refresh',
    () async {
      final relativePath = p.join('CaptureClipper', 'user_book.html');
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      const itemId = 'library_item_capture_clipper_user_book';
      await db.insert('library_items', <String, Object?>{
        'id': itemId,
        'title': 'User Captured Book',
        'file_name': 'user_book.html',
        'relative_path': relativePath,
        'file_format': 'html',
        'folder_type': 'capture',
        'library_role': 'capture',
        'collection_name': 'Pioneer Authors',
        'source_type': 'pioneer_captured_html',
        'index_status': 'indexed',
        'is_missing': 0,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await refresh();

      final row = await fetchRow(itemId);
      expect(row, isNotNull);
      expect(row!['index_status'], 'indexed');
      expect(row['deleted_at'], isNull);
    },
  );
}
