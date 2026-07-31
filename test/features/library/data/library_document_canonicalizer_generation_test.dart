import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/utilities/data/epub_download_validator.dart';

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

/// Builds a structurally complete EPUB (container.xml -> OPF -> spine, each
/// chapter listed as both a manifest item and a spine itemref) so tests can
/// exercise the canonicalizer's happy path under the same structural gate
/// [EpubDownloadValidator] enforces at download time.
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

/// Reproduces the exact shape returned by EGW's media CDN for titles that
/// only have a teaser/stub package: container.xml points at
/// OEBPS/content.opf, but no such entry is actually in the archive. This is
/// the real defect shape behind the COS ("Christ Our Saviour") and IC ("The
/// Impending Conflict") titles that the canonical importer used to accept.
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
  late Directory directory;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('canonical_generation_');
    db = await openDatabase(p.join(directory.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('staging tables exist and start empty', () async {
    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(<String>{
        'library_document_conversion_staging',
        'library_document_sections_staging',
        'library_document_blocks_staging',
        'library_block_source_map_staging',
      }),
    );
    for (final table in <String>[
      'library_document_conversion_staging',
      'library_document_sections_staging',
      'library_document_blocks_staging',
      'library_block_source_map_staging',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
  });

  test('a validated import activates and clears staging tables', () async {
    final source = File(p.join(directory.path, 'book.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>First paragraph.</p>',
        },
      ),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'BOOK1',
      source: source,
    );

    expect(result.activated, isTrue);
    expect(result.blockCount, 2);
    for (final table in <String>[
      'library_document_conversion_staging',
      'library_document_sections_staging',
      'library_document_blocks_staging',
      'library_block_source_map_staging',
    ]) {
      expect(
        await db.query(
          table,
          where: 'library_item_id = ?',
          whereArgs: <Object?>['BOOK1'],
        ),
        isEmpty,
        reason: table,
      );
    }
    final blocks = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: <Object?>['BOOK1'],
    );
    expect(blocks, hasLength(2));
  });

  test(
    'EPUB sections follow spine order when chapter filenames sort lexically',
    () async {
      final source = File(p.join(directory.path, 'numeric-chapters.epub'));
      final chapters = <String, String>{
        for (var chapter = 1; chapter <= 10; chapter++)
          'chapter-$chapter.xhtml':
              '<html><head><title>Chapter $chapter</title></head>'
              '<body><h2>Chapter $chapter</h2>'
              '<p>Readable content for chapter $chapter.</p></body></html>',
      };
      await source.writeAsBytes(
        _wellFormedEpubBytes(chapters: chapters),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'NUMERIC_CHAPTERS',
        source: source,
      );

      expect(result.activated, isTrue);
      final sections = await db.query(
        'library_document_sections',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['NUMERIC_CHAPTERS'],
        orderBy: 'display_order',
      );
      expect(
        sections.map((row) => row['source_href']),
        orderedEquals(<String>[
          for (var chapter = 1; chapter <= 10; chapter++)
            'oebps/chapter-$chapter.xhtml',
        ]),
      );
      final firstHeadings = await db.rawQuery(
        '''
        SELECT plain_text
        FROM library_document_blocks
        WHERE library_item_id = ? AND block_type = 'heading'
        ORDER BY display_order
        ''',
        const <Object?>['NUMERIC_CHAPTERS'],
      );
      expect(
        firstHeadings.map((row) => row['plain_text']),
        orderedEquals(<String>[
          for (var chapter = 1; chapter <= 10; chapter++) 'Chapter $chapter',
        ]),
      );
    },
  );

  test(
    'a failed validation preserves the prior active generation and the source file',
    () async {
      final source = File(p.join(directory.path, 'book.epub'));
      final goodBytes = _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>First paragraph.</p>',
        },
      );
      await source.writeAsBytes(goodBytes, flush: true);

      final first = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'BOOK2',
        source: source,
      );
      expect(first.activated, isTrue);
      final activeBefore = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['BOOK2'],
        orderBy: 'display_order',
      );

      // A structurally incomplete replacement (no container.xml/OPF at all)
      // must be rejected before any parsing happens, leaving the prior
      // generation untouched.
      final badBytes = _epubBytes(<String, List<int>>{
        'OEBPS/ch1.xhtml': '<hr>'.codeUnits,
      });
      await source.writeAsBytes(badBytes, flush: true);

      final second = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'BOOK2',
        source: source,
      );

      expect(second.activated, isFalse);
      expect(second.validationFailureReason, isNotNull);

      final activeAfter = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['BOOK2'],
        orderBy: 'display_order',
      );
      expect(
        activeAfter.map((row) => row['id']),
        activeBefore.map((row) => row['id']),
      );

      final conversion = await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['BOOK2'],
      );
      expect(conversion.single['status'], 'complete');

      final stagingConversion = await db.query(
        'library_document_conversion_staging',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['BOOK2'],
      );
      expect(stagingConversion.single['status'], 'failed');
      expect(
        stagingConversion.single['error_message'],
        second.validationFailureReason,
      );

      for (final table in <String>[
        'library_document_sections_staging',
        'library_document_blocks_staging',
        'library_block_source_map_staging',
      ]) {
        expect(
          await db.query(
            table,
            where: 'library_item_id = ?',
            whereArgs: <Object?>['BOOK2'],
          ),
          isEmpty,
          reason: table,
        );
      }
    },
  );

  test(
    'a first-time import that fails validation leaves no active generation',
    () async {
      final source = File(p.join(directory.path, 'blank.epub'));
      await source.writeAsBytes(
        _epubBytes(<String, List<int>>{'OEBPS/ch1.xhtml': '<hr>'.codeUnits}),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'BOOK3',
        source: source,
      );

      expect(result.activated, isFalse);
      expect(
        await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: <Object?>['BOOK3'],
        ),
        isEmpty,
      );
      final conversion = await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['BOOK3'],
      );
      expect(conversion.single['status'], 'failed');
    },
  );

  test(
    'images referenced from a real EPUB are extracted next to the source and resolvable',
    () async {
      final source = File(p.join(directory.path, 'illustrated.epub'));
      final pngBytes = List<int>.generate(64, (i) => i % 256);
      // The <img> reference below must physically exist inside the
      // archive: rebuild the well-formed EPUB bytes with the binary asset
      // entry added alongside the chapter.
      final wrapped = _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml':
              '<h2>Chapter 1</h2><p>Text.</p><img src="images/pic.png" alt="A picture">',
        },
      );
      final archive = ZipDecoder().decodeBytes(wrapped, verify: false);
      archive.addFile(
        ArchiveFile('OEBPS/images/pic.png', pngBytes.length, pngBytes),
      );
      await source.writeAsBytes(
        Uint8List.fromList(ZipEncoder().encode(archive)),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'BOOK4',
        source: source,
      );

      expect(result.activated, isTrue);
      final imageRows = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>['BOOK4', 'image'],
      );
      expect(imageRows, hasLength(1));
      final formatted = imageRows.single['formatted_content']!.toString();
      expect(formatted, isNot(contains('images/pic.png')));

      final assetDirectory = Directory(
        p.join(directory.path, '_canonical_assets', 'BOOK4'),
      );
      final extractedFiles = assetDirectory.existsSync()
          ? assetDirectory.listSync()
          : const <FileSystemEntity>[];
      expect(extractedFiles, hasLength(1));
      expect((extractedFiles.single as File).readAsBytesSync(), pngBytes);
    },
  );

  test(
    'a structurally sound EPUB with a missing OPF (placeholder/teaser package) is rejected',
    () async {
      final source = File(p.join(directory.path, 'missing_opf.epub'));
      await source.writeAsBytes(
        _epubBytes(<String, List<int>>{
          'mimetype': 'application/epub+zip'.codeUnits,
          'META-INF/container.xml': _containerXml.codeUnits,
          // Deliberately no OEBPS/content.opf entry.
        }),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'MISSING_OPF',
        source: source,
      );

      expect(result.activated, isFalse);
      expect(
        await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: <Object?>['MISSING_OPF'],
        ),
        isEmpty,
      );
      final conversion = await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['MISSING_OPF'],
      );
      expect(conversion.single['status'], 'failed');
    },
  );

  test('an OPF with manifest items but no spine is rejected', () async {
    final source = File(p.join(directory.path, 'no_spine.epub'));
    await source.writeAsBytes(
      _epubBytes(<String, List<int>>{
        'mimetype': 'application/epub+zip'.codeUnits,
        'META-INF/container.xml': _containerXml.codeUnits,
        'OEBPS/content.opf':
            '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>No Spine</dc:title></metadata>
  <manifest>
    <item id="chap0" href="chap0.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine></spine>
</package>
'''
                .codeUnits,
        'OEBPS/chap0.xhtml':
            '<html><body><p>Real content here.</p></body></html>'.codeUnits,
      }),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'NO_SPINE',
      source: source,
    );

    expect(result.activated, isFalse);
    expect(
      await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['NO_SPINE'],
      ),
      isEmpty,
    );
  });

  test(
    'a placeholder/teaser EPUB (the real COS/IC defect shape) cannot activate',
    () async {
      for (final title in <String>[
        'Christ Our Saviour',
        'The Impending Conflict',
      ]) {
        final source = File(p.join(directory.path, '${title.hashCode}.epub'));
        await source.writeAsBytes(
          _placeholderStubBytes(title: title),
          flush: true,
        );

        final result = await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'PLACEHOLDER_${title.hashCode}',
          source: source,
        );

        expect(result.activated, isFalse, reason: title);
        expect(
          await db.query(
            'library_document_blocks',
            where: 'library_item_id = ?',
            whereArgs: <Object?>['PLACEHOLDER_${title.hashCode}'],
          ),
          isEmpty,
          reason: title,
        );
      }
    },
  );

  test('a stale generation built by an older canonicalizer version is removed '
      'when the same on-disk file now fails structural validation (COS/IC '
      'self-healing on next open)', () async {
    const itemId = 'STALE_COS';
    final now = DateTime.now().toUtc().toIso8601String();
    // Simulate a generation accepted by a pre-structural-gate
    // canonicalizer version: a "complete" conversion row plus real
    // section/block rows, all tagged with an older version number.
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': 'Christ Our Saviour',
      'file_name': 'cos.epub',
      'relative_path': 'cos.epub',
      'file_format': 'epub',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': itemId,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version - 1,
      'source_hash': 'stale-hash',
      'status': 'complete',
      'completed_at': now,
      'error_message': null,
    });
    await db.insert('library_document_sections', <String, Object?>{
      'id': 'stale-section',
      'library_item_id': itemId,
      'display_order': 0,
      'title': 'Table of Contents',
      'source_href': 'toc.html',
      'content_hash': 'stale',
    });
    await db.insert('library_document_blocks', <String, Object?>{
      'id': 'stale-block',
      'library_item_id': itemId,
      'section_id': 'stale-section',
      'display_order': 0,
      'block_type': 'heading',
      'plain_text': 'Table of Contents',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'stale',
    });

    final source = File(p.join(directory.path, 'cos.epub'));
    await source.writeAsBytes(
      _placeholderStubBytes(title: 'Christ Our Saviour'),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: itemId,
      source: source,
    );

    expect(result.activated, isFalse);
    expect(
      await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[itemId],
      ),
      isEmpty,
      reason: 'the stale placeholder generation must be removed',
    );
    expect(
      await db.query(
        'library_document_sections',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[itemId],
      ),
      isEmpty,
    );
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(conversion.single['status'], 'failed');

    final itemRow = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(itemRow.single['index_status'], 'needs_attention');
    expect(itemRow.single['index_error'], isNotNull);
    // User-owned identity fields must survive the repair untouched.
    expect(itemRow.single['title'], 'Christ Our Saviour');
  });

  test('a genuinely valid generation built under the current version survives '
      'a later structurally-invalid replacement, and the item is still '
      'flagged Needs Attention', () async {
    const itemId = 'GOOD_THEN_BAD';
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': 'A Real Book',
      'file_name': 'real.epub',
      'relative_path': 'real.epub',
      'file_format': 'epub',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    final source = File(p.join(directory.path, 'real.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>Real paragraph text.</p>',
        },
      ),
      flush: true,
    );
    final first = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: itemId,
      source: source,
    );
    expect(first.activated, isTrue);

    await source.writeAsBytes(
      _placeholderStubBytes(title: 'A Real Book'),
      flush: true,
    );
    final second = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: itemId,
      source: source,
    );

    expect(second.activated, isFalse);
    final blocks = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(blocks, isNotEmpty, reason: 'the valid generation must survive');
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(conversion.single['status'], 'complete');

    final itemRow = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    expect(itemRow.single['index_status'], 'needs_attention');
  });

  test(
    'the canonicalizer rejects exactly the same bytes EpubDownloadValidator '
    'rejects, for the same reason (single shared structural validator)',
    () async {
      for (final title in <String>[
        'Christ Our Saviour',
        'The Impending Conflict',
      ]) {
        final bytes = _placeholderStubBytes(title: title);
        final downloaderResult = EpubDownloadValidator.validate(bytes);
        expect(downloaderResult.isValid, isFalse, reason: title);

        final source = File(
          p.join(directory.path, 'shared_${title.hashCode}.epub'),
        );
        await source.writeAsBytes(bytes, flush: true);
        final canonicalizerResult = await const LibraryDocumentCanonicalizer()
            .canonicalize(
              db: db,
              libraryItemId: 'SHARED_${title.hashCode}',
              source: source,
            );

        expect(canonicalizerResult.activated, isFalse, reason: title);
        expect(
          canonicalizerResult.validationFailureReason,
          contains(downloaderResult.rejectionReason!.name),
          reason: title,
        );
      }
    },
  );
}
