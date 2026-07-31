import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/canonical_epub_generation_repair_service.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';

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

Uint8List _placeholderStubBytes({required String title}) {
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/toc.html':
        '<html><head><title>$title</title></head><body>'
                '<div class="chapter" id="toc"><h3>Table of Contents</h3>'
                '<p><a href="aboutbook.html">Information about this Book</a></p></div>'
                '</body></html>'
            .codeUnits,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory rootDir;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    rootDir = await Directory.systemTemp.createTemp('canonical_repair_');
    db = await openDatabase(p.join(rootDir.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    await rootDir.delete(recursive: true);
  });

  Future<void> seedLibraryItem({
    required String id,
    required String title,
    required String relativePath,
    String epubStorageState = 'present',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': title,
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': 'epub',
      'source_type': 'official_download',
      'epub_storage_state': epubStorageState,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
  }

  test('startup-safe mode does not mass-upgrade old generations but still '
      'reconciles missing storage state', () async {
    const itemId = 'OLD_EGW';
    await seedLibraryItem(
      id: itemId,
      title: 'Old EGW Generation',
      relativePath: 'missing.epub',
    );
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
      'source_hash': 'old-hash',
      'status': 'complete',
    });

    final report = await CanonicalEpubGenerationRepairService.instance.repair(
      db: db,
      rootPath: rootDir.path,
      allowVersionUpgrade: false,
    );

    expect(report.staleGenerationsScanned, 0);
    expect(report.regenerated, 0);
    expect(report.rejected, 0);
    expect(report.staleStorageStatesRepaired, 1);
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[itemId],
    );
    expect(
      conversion.single['canonicalizer_version'],
      LibraryDocumentCanonicalizer.version - 1,
    );
  });

  test('a stale generation for a real placeholder EPUB (COS-style) is removed '
      'and the item is marked Needs Attention', () async {
    const itemId = 'COS';
    await seedLibraryItem(
      id: itemId,
      title: 'Christ Our Saviour',
      relativePath: 'cos.epub',
    );
    final file = File(p.join(rootDir.path, 'cos.epub'));
    await file.writeAsBytes(
      _placeholderStubBytes(title: 'Christ Our Saviour'),
      flush: true,
    );
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
      'source_hash': 'stale-hash',
      'status': 'complete',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'error_message': null,
    });
    await db.insert('library_document_sections', <String, Object?>{
      'id': 'cos-section',
      'library_item_id': itemId,
      'display_order': 0,
      'title': 'Table of Contents',
      'source_href': 'toc.html',
      'content_hash': 'stale',
    });
    await db.insert('library_document_blocks', <String, Object?>{
      'id': 'cos-block',
      'library_item_id': itemId,
      'section_id': 'cos-section',
      'display_order': 0,
      'block_type': 'heading',
      'plain_text': 'Table of Contents',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'stale',
    });
    final markupNow = DateTime.now().toUtc().toIso8601String();
    await db.insert('elibrary_markups', <String, Object?>{
      'library_item_id': itemId,
      'epub_href': 'canonical:cos-block',
      'start_block_index': 0,
      'start_char_offset': 0,
      'end_block_index': 0,
      'end_char_offset': 5,
      'ref_start': 'COS 1.1',
      'ref_end': 'COS 1.1',
      'compact_ref': 'COS 1.1',
      'selected_text_snapshot': 'A user highlight',
      'markup_type': 'highlight',
      'color': 'yellow',
      'note_text': 'A user note the repair must never touch.',
      'created_at': markupNow,
      'updated_at': markupNow,
    });

    final report = await CanonicalEpubGenerationRepairService.instance.repair(
      db: db,
      rootPath: rootDir.path,
    );

    expect(report.staleGenerationsScanned, 1);
    expect(report.rejected, 1);
    expect(report.regenerated, 0);

    expect(
      await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[itemId],
      ),
      isEmpty,
    );
    // User-owned highlight/note data lives independently of the
    // canonical generation and must survive the repair untouched.
    final markups = await db.query(
      'elibrary_markups',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(markups, hasLength(1));
    expect(
      markups.single['note_text'],
      'A user note the repair must never touch.',
    );

    final itemRow = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(itemRow.single['index_status'], 'needs_attention');
    expect(itemRow.single['title'], 'Christ Our Saviour');
    expect(itemRow.single['relative_path'], 'cos.epub');
  });

  test(
    'a stale generation for a real placeholder EPUB (IC-style) is removed',
    () async {
      const itemId = 'IC';
      await seedLibraryItem(
        id: itemId,
        title: 'The Impending Conflict',
        relativePath: 'ic.epub',
      );
      final file = File(p.join(rootDir.path, 'ic.epub'));
      await file.writeAsBytes(
        _placeholderStubBytes(title: 'The Impending Conflict'),
        flush: true,
      );
      await db.insert('library_document_conversion', <String, Object?>{
        'library_item_id': itemId,
        'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
        'source_hash': 'stale-hash',
        'status': 'complete',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'error_message': null,
      });
      await db.insert('library_document_blocks', <String, Object?>{
        'id': 'ic-block',
        'library_item_id': itemId,
        'section_id': 'ic-section',
        'display_order': 0,
        'block_type': 'heading',
        'plain_text': 'Table of Contents',
        'formatted_content': '{"version":1,"nodes":[]}',
        'content_hash': 'stale',
      });

      final report = await CanonicalEpubGenerationRepairService.instance.repair(
        db: db,
        rootPath: rootDir.path,
      );

      expect(report.rejected, 1);
      expect(
        await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: <Object?>[itemId],
        ),
        isEmpty,
      );
    },
  );

  test('a stale generation for a genuinely valid EPUB is rebuilt under the '
      'current version, not removed', () async {
    const itemId = 'REAL_BOOK';
    await seedLibraryItem(
      id: itemId,
      title: 'A Real Book',
      relativePath: 'real.epub',
    );
    final file = File(p.join(rootDir.path, 'real.epub'));
    await file.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>Real paragraph text.</p>',
        },
      ),
      flush: true,
    );
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
      'source_hash': 'stale-hash',
      'status': 'complete',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'error_message': null,
    });

    final report = await CanonicalEpubGenerationRepairService.instance.repair(
      db: db,
      rootPath: rootDir.path,
    );

    expect(report.regenerated, 1);
    expect(report.rejected, 0);
    final blocks = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(blocks, isNotEmpty);
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(conversion.single['status'], 'complete');
    expect(
      conversion.single['canonicalizer_version'],
      LibraryDocumentCanonicalizer.version,
    );
  });

  test(
    'an item whose source file cannot be found on disk is left untouched',
    () async {
      const itemId = 'MISSING_FILE';
      await seedLibraryItem(
        id: itemId,
        title: 'Missing On Disk',
        relativePath: 'nope.epub',
      );
      await db.insert('library_document_conversion', <String, Object?>{
        'library_item_id': itemId,
        'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
        'source_hash': 'stale-hash',
        'status': 'complete',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'error_message': null,
      });
      await db.insert('library_document_blocks', <String, Object?>{
        'id': 'missing-block',
        'library_item_id': itemId,
        'section_id': 'missing-section',
        'display_order': 0,
        'block_type': 'paragraph',
        'plain_text': 'Kept as-is.',
        'formatted_content': '{"version":1,"nodes":[]}',
        'content_hash': 'stale',
      });

      final report = await CanonicalEpubGenerationRepairService.instance.repair(
        db: db,
        rootPath: rootDir.path,
      );

      expect(report.skippedMissingFile, 1);
      expect(report.rejected, 0);
      expect(report.regenerated, 0);
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[itemId],
      );
      expect(blocks, hasLength(1), reason: 'never fabricate/guess a file');
    },
  );

  test(
    'a generation already built by the current version is never rescanned',
    () async {
      const itemId = 'ALREADY_CURRENT';
      await seedLibraryItem(
        id: itemId,
        title: 'Already Current',
        relativePath: 'current.epub',
      );
      await db.insert('library_document_conversion', <String, Object?>{
        'library_item_id': itemId,
        'canonicalizer_version': LibraryDocumentCanonicalizer.version,
        'source_hash': 'current-hash',
        'status': 'complete',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'error_message': null,
      });

      final report = await CanonicalEpubGenerationRepairService.instance.repair(
        db: db,
        rootPath: rootDir.path,
      );

      expect(report.staleGenerationsScanned, 0);
    },
  );

  test('library_items.epub_storage_state stuck on "present" for a missing file '
      'is repaired to removed_after_index', () async {
    const itemId = 'STALE_STATE';
    await seedLibraryItem(
      id: itemId,
      title: 'Stale State Book',
      relativePath: 'stale_state.epub',
      epubStorageState: 'present',
    );
    // Deliberately never write stale_state.epub to disk.

    final report = await CanonicalEpubGenerationRepairService.instance.repair(
      db: db,
      rootPath: rootDir.path,
    );

    expect(report.staleStorageStatesRepaired, 1);
    final itemRow = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(itemRow.single['epub_storage_state'], 'removed_after_index');
    expect(itemRow.single['epub_removed_at'], isNotNull);
  });

  test('library_items.epub_storage_state is left alone when the file is '
      'actually present', () async {
    const itemId = 'STILL_PRESENT';
    await seedLibraryItem(
      id: itemId,
      title: 'Still Present Book',
      relativePath: 'still_present.epub',
      epubStorageState: 'present',
    );
    await File(p.join(rootDir.path, 'still_present.epub')).writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{'ch1.xhtml': '<p>Body.</p>'},
      ),
      flush: true,
    );

    final report = await CanonicalEpubGenerationRepairService.instance.repair(
      db: db,
      rootPath: rootDir.path,
    );

    expect(report.staleStorageStatesRepaired, 0);
    final itemRow = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(itemRow.single['epub_storage_state'], 'present');
  });
}
