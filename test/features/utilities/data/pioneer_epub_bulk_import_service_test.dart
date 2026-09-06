import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_bulk_import_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

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

Uint8List _wellFormedEpubBytes({
  required String title,
  String author = 'A. Pioneer Author',
  String bodyText = 'Synthetic filler paragraph text for a Pioneer book.',
}) {
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
  </metadata>
  <manifest>
    <item id="chap0" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap0"/>
  </spine>
</package>
''';
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
    'OEBPS/ch1.xhtml': '<h2>Chapter 1</h2><p>$bodyText</p>'.codeUnits,
  });
}

Uint8List _placeholderStubBytes() {
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory sourceFolder;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('pioneer_bulk_support_');
    documentsDir = await Directory.systemTemp.createTemp('pioneer_bulk_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp(
      'pioneer_bulk_root_',
    );
    sourceFolder = await Directory.systemTemp.createTemp(
      'pioneer_bulk_source_',
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
    for (final dir in [
      supportDir,
      documentsDir,
      libraryRootDir,
      sourceFolder,
    ]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('6/7/12/23/25. a valid Pioneer EPUB is copied (never moved), registered '
      'with pioneer_epub_import source type, canonically activated, and '
      'routes through the canonical reader', () async {
    final source = File(p.join(sourceFolder.path, 'Bible Readings.epub'));
    final bytes = _wellFormedEpubBytes(title: 'Bible Readings');
    await source.writeAsBytes(bytes, flush: true);

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    expect(inventory.needsImportCount, 1);

    final preparation = await PioneerEpubBulkImportService.instance.prepare(
      inventory: inventory,
    );
    expect(preparation.targets, hasLength(1));
    expect(preparation.preparationFailures, isEmpty);

    final result = await LibraryAcquisitionBatchRunner.instance.activate(
      preparation.targets,
    );
    expect(result.readyCount, 1);

    // The external source original was only read, never moved or altered.
    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), bytes);

    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[preparation.targets.single.libraryItemId],
    );
    expect(rows.single['source_type'], 'pioneer_epub_import');
    expect(rows.single['pioneer_source_relative_path'], 'Bible Readings.epub');
    expect(rows.single['pioneer_source_fingerprint'], isNotNull);

    final relativePath = rows.single['relative_path']!.toString();
    expect(
      relativePath.replaceAll('\\', '/'),
      startsWith('ImportedPioneerEpubs/'),
    );
    final item = LibraryCatalogItem(
      id: rows.single['id']!.toString(),
      title: rows.single['title']!.toString(),
      author: rows.single['author']?.toString(),
      fileName: rows.single['file_name']!.toString(),
      fileHash: rows.single['file_hash']?.toString(),
      relativePath: relativePath,
      fileFormat: 'epub',
      folderType: 'pioneer_epub_import',
      libraryRole: 'pioneer_epub_import',
      collectionName: 'Pioneer Library',
      sourceSite: null,
      sourceUrl: null,
      sourceType: 'pioneer_epub_import',
      coverPath: null,
      dateAdded: null,
      lastOpened: null,
      indexStatus: rows.single['index_status']?.toString(),
      indexError: null,
      fileSize: 0,
      mimeType: 'application/epub+zip',
      spineIndex: null,
      anchorId: null,
      epubHref: null,
      paragraphIndex: null,
      navigationCount: 0,
    );
    expect(supportsCanonicalEpubReader(item), isTrue);
  });

  test('13. a batch continues past one isolated failure', () async {
    await File(p.join(sourceFolder.path, 'good.epub')).writeAsBytes(
      _wellFormedEpubBytes(title: 'A Good Pioneer Book'),
      flush: true,
    );
    await File(
      p.join(sourceFolder.path, 'bad.epub'),
    ).writeAsBytes(_placeholderStubBytes(), flush: true);

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    // Only the structurally valid book is eligible for import.
    expect(inventory.needsImportCount, 1);
    expect(inventory.invalidCount, 1);

    final preparation = await PioneerEpubBulkImportService.instance.prepare(
      inventory: inventory,
    );
    final result = await LibraryAcquisitionBatchRunner.instance.activate(
      preparation.targets,
    );
    expect(result.readyCount, 1);
  });

  test('14/15/16. resume skips an unchanged book, stages a replacement for a '
      'changed one, and a failed replacement preserves the prior valid '
      'generation', () async {
    final source = File(p.join(sourceFolder.path, 'Patriarchs.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(title: 'Patriarchs and Prophets'),
      flush: true,
    );

    final firstInventory = await PioneerEpubFolderInventoryService.instance
        .survey(sourceFolder);
    final firstPrep = await PioneerEpubBulkImportService.instance.prepare(
      inventory: firstInventory,
    );
    final firstResult = await LibraryAcquisitionBatchRunner.instance.activate(
      firstPrep.targets,
    );
    expect(firstResult.readyCount, 1);
    final libraryItemId = firstPrep.targets.single.libraryItemId;

    // Re-running against an unchanged source must skip it.
    final rescan = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    expect(rescan.unchangedCount, 1);
    expect(rescan.needsImportCount, 0);

    // Now corrupt the source in place at the same path (simulating a
    // later re-export) — a changed source must be re-eligible.
    await source.writeAsBytes(_placeholderStubBytes(), flush: true);
    final changedScan = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    expect(changedScan.invalidCount, 1);
    expect(changedScan.needsImportCount, 0);

    // A structurally invalid replacement is never imported, so the prior
    // ready generation must remain intact and readable.
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
    expect(rows.single['index_status'], isNot('needs_attention'));
    final blocks = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
    expect(blocks, isNotEmpty);
  });

  test('legacy Pioneer identity is upgraded in place and user state stays '
      'attached to the original library item id', () async {
    const legacyId = 'legacy-cwcp-library-item';
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': legacyId,
      'title': 'The Consecrated Way',
      'author': 'A. T. Jones',
      'file_name': 'capture.html',
      'relative_path': 'TextCaptures/CWCP/capture.html',
      'file_format': 'html',
      'folder_type': 'research',
      'source_type': 'egw_html_capture',
      'epub_href': 'legacy/chapter-7.html',
      'epub_cfi': 'epubcfi(/6/14)',
      'anchor_id': 'saved-anchor',
      'spine_index': 7,
      'paragraph_index': 19,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
      'revision': 1,
      'sync_status': 'pending',
    });
    await db.insert('elibrary_markups', <String, Object?>{
      'library_item_id': legacyId,
      'epub_href': 'legacy/chapter-7.html',
      'start_block_index': 4,
      'start_char_offset': 2,
      'end_block_index': 4,
      'end_char_offset': 18,
      'selected_text_snapshot': 'preserved highlight',
      'markup_type': 'highlight',
      'color': 'yellow',
      'note_text': 'preserved note',
      'created_at': now,
      'updated_at': now,
    });

    final source = File(
      p.join(
        sourceFolder.path,
        'the_consecrated_way_to_christian_perfection.epub',
      ),
    );
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        title: 'The Consecrated Way to Christian Perfection',
        author: 'A. T. Jones',
      ),
      flush: true,
    );

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    expect(inventory.entries.single.libraryItemId, legacyId);
    expect(inventory.entries.single.reusesLegacyLibraryItemIdentity, isTrue);

    final preparation = await PioneerEpubBulkImportService.instance.prepare(
      inventory: inventory,
    );
    expect(preparation.targets.single.libraryItemId, legacyId);
    final result = await LibraryAcquisitionBatchRunner.instance.activate(
      preparation.targets,
    );
    expect(result.readyCount, 1);

    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: const <Object?>[legacyId],
    );
    expect(rows, hasLength(1));
    expect(rows.single['source_type'], 'pioneer_epub_import');
    expect(rows.single['epub_href'], 'legacy/chapter-7.html');
    expect(rows.single['epub_cfi'], 'epubcfi(/6/14)');
    expect(rows.single['anchor_id'], 'saved-anchor');
    expect(rows.single['spine_index'], 7);
    expect(rows.single['paragraph_index'], 19);
    expect(
      await db.query(
        'elibrary_markups',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>[legacyId],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'library_items',
        where: 'id != ? AND lower(title) LIKE ?',
        whereArgs: const <Object?>[legacyId, '%consecrated way%'],
      ),
      isEmpty,
    );
  });

  test(
    'legacy bridge still finds a canonical row whose own source_type is '
    'already pioneer_epub_import (regression: this used to be excluded and '
    'created a duplicate ad hoc row instead)',
    () async {
      const canonicalId = 'library_item_research_pioneer_stephen_nelson_haskell_CIS';
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      // A prior bridge (or a pre-seeded bundled row, as the real live catalog
      // has for this exact id) can leave the canonical legacy-bridge
      // target's own source_type at 'pioneer_epub_import' — exactly what
      // `_copyAndRegister` sets on every row it touches. The bridge lookup
      // must still find this row on a later re-scan rather than excluding
      // it and minting a brand new ad hoc id for the same physical file.
      // `replace` because the bundled seed database already ships this
      // exact id for this exact work.
      await db.insert('library_items', <String, Object?>{
        'id': canonicalId,
        'title': 'The Cross and its Shadow',
        'author': 'Stephen Nelson Haskell',
        'file_name': 'the_cross_and_its_shadow.epub',
        'relative_path': 'ImportedPioneerEpubs/the_cross_and_its_shadow.epub',
        'file_format': 'epub',
        'folder_type': 'pioneer_epub_import',
        'source_type': 'pioneer_epub_import',
        'is_missing': 0,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
        'revision': 1,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final source = File(
        p.join(sourceFolder.path, 'the_cross_and_its_shadow.epub'),
      );
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          title: 'The Cross and its Shadow',
          author: 'Stephen Nelson Haskell',
        ),
        flush: true,
      );

      final inventory = await PioneerEpubFolderInventoryService.instance
          .survey(sourceFolder);
      expect(inventory.entries.single.libraryItemId, canonicalId);
      expect(
        inventory.entries.single.reusesLegacyLibraryItemIdentity,
        isTrue,
      );

      final preparation = await PioneerEpubBulkImportService.instance.prepare(
        inventory: inventory,
      );
      expect(preparation.targets.single.libraryItemId, canonicalId);
      final result = await LibraryAcquisitionBatchRunner.instance.activate(
        preparation.targets,
      );
      expect(result.readyCount, 1);

      final rows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: const <Object?>[canonicalId],
      );
      expect(rows, hasLength(1));
      expect(
        await db.query(
          'library_items',
          where: 'id != ? AND lower(title) LIKE ?',
          whereArgs: const <Object?>[canonicalId, '%cross and its shadow%'],
        ),
        isEmpty,
        reason:
            'A second row for the same physical file means the bridge '
            'failed to find the canonical row and minted a duplicate.',
      );
    },
  );

  test('missing Library Root Folder throws a clear, catchable error', () async {
    await File(
      p.join(sourceFolder.path, 'x.epub'),
    ).writeAsBytes(_wellFormedEpubBytes(title: 'X'), flush: true);
    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    await LibraryRootService.instance.clearLibraryRoot();
    LibraryRootService.instance.invalidateCachedSelection();

    await expectLater(
      PioneerEpubBulkImportService.instance.prepare(inventory: inventory),
      throwsA(isA<StateError>()),
    );
  });
}
