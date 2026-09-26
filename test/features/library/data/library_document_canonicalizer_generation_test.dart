import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
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

Uint8List _withNcx(Uint8List epub, String ncx) {
  final archive = ZipDecoder().decodeBytes(epub, verify: false)
    ..addFile(ArchiveFile('OEBPS/toc.ncx', ncx.length, ncx.codeUnits));
  return Uint8List.fromList(ZipEncoder().encode(archive));
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

  test(
    'image orientation survives SQLite import without changing its bytes or ID',
    () async {
      final source = File(p.join(directory.path, 'oriented.epub'));
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      Future<void> write(String attributes) async {
        final archive = ZipDecoder().decodeBytes(
          _wellFormedEpubBytes(
            chapters: {
              'body.xhtml':
                  '<h2>Chapter</h2><p>Reading text remains intact.</p>'
                  '<p><img id="plate" src="plate.png" alt="Original illustration" $attributes/></p>',
            },
          ),
        );
        archive.addFile(ArchiveFile('OEBPS/plate.png', bytes.length, bytes));
        await source.writeAsBytes(ZipEncoder().encode(archive));
      }

      await write('');
      final initial = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'oriented',
        source: source,
      );
      expect(initial.activated, true, reason: initial.validationFailureReason);
      final before = (await db.query(
        'library_document_blocks',
        where: "block_type='image'",
      )).single;
      for (final degrees in [90, 180, 270, 0]) {
        await write('data-image-rotation="$degrees"');
        final result = await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'oriented',
          source: source,
          force: true,
        );
        expect(result.activated, true);
        final row = (await db.query(
          'library_document_blocks',
          where: "block_type='image'",
        )).single;
        expect(row['id'], before['id']);
        expect(row['plain_text'], before['plain_text']);
        final f = LibraryFormattedContent.fromJson(
          row['formatted_content'] as String,
        );
        expect(
          f.nodes.single['rotation_degrees'],
          degrees == 0 ? isNull : degrees,
        );
        final asset = File(
          p.join(
            directory.path,
            '_canonical_assets',
            'oriented',
            f.nodes.single['source'] as String,
          ),
        );
        expect(await asset.readAsBytes(), bytes);
      }
      final blocks = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final conversion = await db.query('library_document_conversion');
      await write('data-image-rotation="45"');
      await expectLater(
        const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'oriented',
          source: source,
          force: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Unsupported image orientation'),
          ),
        ),
      );
      expect(
        await db.query('library_document_blocks', orderBy: 'display_order'),
        blocks,
      );
      expect(await db.query('library_document_conversion'), conversion);
    },
  );

  test(
    'nested page and named anchors remain independent link targets without changing prose',
    () async {
      final source = File(p.join(directory.path, 'anchors.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml':
                '<h1>Reading</h1><p id="paragraph">Before '
                '<span id="Page20" role="doc-pagebreak" aria-label="20"></span>'
                '<em>middle</em><span id="Page21" role="doc-pagebreak" aria-label="21"></span>'
                ' after<a name="note-end"></a>.</p>',
            'index.xhtml':
                '<p><a href="body.xhtml#Page20">20</a>, '
                '<a href="body.xhtml#Page21">21</a></p>',
          },
        ),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'anchors',
        source: source,
      );
      final body = (await db.query(
        'library_document_blocks',
        where: "source_anchor='paragraph'",
      )).single;
      expect(body['plain_text'], 'Before middle after.');
      final formatted = LibraryFormattedContent.fromJson(
        body['formatted_content'] as String,
      );
      expect(formatted.metadata['source_anchor_aliases'], [
        'Page20',
        'Page21',
        'note-end',
      ]);
      expect(
        formatted.nodes.any(
          (n) => (n['marks'] as List?)?.contains('italic') ?? false,
        ),
        true,
      );
      final repository = LibraryDocumentRepository(db);
      for (final anchor in ['Page20', 'Page21', 'note-end']) {
        final target = await repository.resolveSourceLink(
          'anchors',
          fromHref: 'oebps/index.xhtml',
          href: 'body.xhtml#$anchor',
        );
        expect(target?.id, body['id']);
        expect(target?.plainText, body['plain_text']);
      }
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'anchors',
        source: source,
        force: true,
      );
      expect(
        await db.query('library_document_blocks', orderBy: 'display_order'),
        rows,
      );
    },
  );

  test(
    'index grouping and print provenance survive storage with separate source references',
    () async {
      final source = File(p.join(directory.path, 'index-group.epub'));
      const witness = 'https://archive.org/details/original/page/n865/mode/1up';
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'index.xhtml':
                '<h1>General Index</h1>'
                '<p id="entry-one" data-refcode="DAR 754.31" data-index-entry-group="DAR 754.31" '
                'data-index-letter="I" data-text-witness="$witness">Interpretation, two systems</p>'
                '<p id="entry-two" data-refcode="DAR 754.32" data-index-entry-group="DAR 754.31" '
                'data-index-letter="I" data-text-witness="$witness">of, 4; Origen’s mystical system, <em>id.</em></p>',
          },
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'index-group',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(rows.length, 3);
      final heading = LibraryFormattedContent.fromJson(
        rows.first['formatted_content'] as String,
      );
      expect(heading.metadata.containsKey('source_index_entry_group'), false);
      for (final row in rows.skip(1)) {
        final stored = LibraryFormattedContent.fromJson(
          row['formatted_content'] as String,
        );
        expect(stored.metadata['source_index_entry_group'], 'DAR 754.31');
        expect(stored.metadata['source_index_letter'], 'I');
        expect(stored.metadata['text_witness'], witness);
      }
      expect(rows[1]['source_refcode'], 'DAR 754.31');
      expect(rows[2]['source_refcode'], 'DAR 754.32');
      expect(rows[1]['id'], isNot(rows[2]['id']));
      final last = LibraryFormattedContent.fromJson(
        rows.last['formatted_content'] as String,
      );
      expect(last.nodes.last['text'], 'id.');
      expect(last.nodes.last['marks'], contains('italic'));
    },
  );

  test('authored whole-file year headings survive internal chapter splitting', () async {
    final source = File(p.join(directory.path, 'years.epub'));
    await source.writeAsBytes(
      _withNcx(
        _wellFormedEpubBytes(
          chapters: {
            'year.xhtml':
                '<html><head><title>2 1893 | Collected articles</title></head><body>'
                '<h1><span id="year-start"/>1893</h1>'
                '<h2 id="first">First address</h2><p>First original paragraph.</p>'
                '<h2 id="second">Second address</h2><p>Second original paragraph.</p></body></html>',
          },
        ),
        '<ncx><navMap><navPoint id="year"><navLabel><text>1893</text></navLabel>'
        '<content src="year.xhtml"/>'
        '<navPoint id="one"><navLabel><text>First address</text></navLabel><content src="year.xhtml#first"/></navPoint>'
        '<navPoint id="two"><navLabel><text>Second address</text></navLabel><content src="year.xhtml#second"/></navPoint>'
        '</navPoint></navMap></ncx>',
      ),
    );
    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'years',
      source: source,
    );
    expect(result.activated, true, reason: result.validationFailureReason);
    final rows = await db.query(
      'library_document_blocks',
      orderBy: 'display_order',
    );
    expect(rows.map((r) => r['plain_text']).toList(), [
      '1893',
      'First address',
      'First original paragraph.',
      'Second address',
      'Second original paragraph.',
    ]);
    expect(rows.first['block_type'], 'heading');
    expect(rows.first['source_anchor'], 'year-start');
    expect(
      rows.any(
        (r) => (r['formatted_content'] as String).contains('source_page_start'),
      ),
      false,
    );
    final nav = await LibraryDocumentRepository(
      db,
    ).loadCanonicalNavigationDestinations('years');
    expect(nav.first.label, '1893');
    expect(nav.first.block.id, rows.first['id']);
  });

  test(
    'numeric Contents targets preserve only their own anchored headings',
    () async {
      final source = File(p.join(directory.path, 'numbered-sections.epub'));
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: {
              'body.xhtml':
                  '<h6>12</h6><h2><span id="section-twelve"/>12</h2><p>Section twelve text.</p>',
            },
          ),
          '<ncx><navMap><navPoint id="twelve"><navLabel><text>12</text></navLabel>'
          '<content src="body.xhtml#section-twelve"/></navPoint></navMap></ncx>',
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'numbered-sections',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(rows.map((r) => r['plain_text']).toList(), [
        '12',
        'Section twelve text.',
      ]);
      expect(rows.first['source_anchor'], 'section-twelve');
      expect(rows.first['block_type'], 'heading');
    },
  );

  test(
    'explicit printed-page semantics override a matching numeric Contents label',
    () async {
      final source = File(p.join(directory.path, 'explicit-page.epub'));
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: {
              'body.xhtml':
                  '<h6 role="doc-pagebreak">748</h6><h1>Index</h1><p>Original index text.</p>',
            },
          ),
          '<ncx><navMap><navPoint id="page"><navLabel><text>748</text></navLabel>'
          '<content src="body.xhtml"/></navPoint></navMap></ncx>',
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'explicit-page',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(rows.map((r) => r['plain_text']).toList(), [
        'Index',
        'Original index text.',
      ]);
      expect(
        (jsonDecode(rows.first['formatted_content'] as String)
            as Map)['metadata']['source_page_start'],
        748,
      );
    },
  );

  test(
    'an update cannot orphan an existing canonical saved reading position',
    () async {
      final source = File(p.join(directory.path, 'saved-position.epub'));
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', {
        'id': 'saved-position',
        'title': 'Position fixture',
        'file_name': 'saved-position.epub',
        'relative_path': 'saved-position.epub',
        'source_type': 'user_epub_import',
        'created_at': now,
        'updated_at': now,
        'device_id': 'test',
      });
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml':
                '<h1>Opening</h1><p id="original-target">Keep this reading position.</p>',
          },
        ),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'saved-position',
        source: source,
      );
      final before = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final conversion = await db.query('library_document_conversion');
      await db.update(
        'library_items',
        {'anchor_id': 'canonical:${before.last['id']}'},
        where: 'id=?',
        whereArgs: ['saved-position'],
      );
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml':
                '<h1>Opening</h1><p id="different-target">Keep this reading position.</p>',
          },
        ),
      );
      await expectLater(
        const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'saved-position',
          source: source,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('saved reading position'),
          ),
        ),
      );
      expect(
        await db.query('library_document_blocks', orderBy: 'display_order'),
        before,
      );
      expect(await db.query('library_document_conversion'), conversion);
      expect(
        (await db.query('library_items')).single['anchor_id'],
        'canonical:${before.last['id']}',
      );
    },
  );

  test(
    'a restored heading preserves existing paragraph IDs, annotations and navigation across imports',
    () async {
      final source = File(p.join(directory.path, 'restored-heading.epub'));
      const item = 'restored-heading';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', {
        'id': item,
        'title': 'Reconciliation fixture',
        'file_name': 'restored-heading.epub',
        'relative_path': 'restored-heading.epub',
        'source_type': 'user_epub_import',
        'created_at': now,
        'updated_at': now,
        'device_id': 'test',
      });
      const paragraphs =
          '<p>Alpha has selected words.</p><p>Beta has selected words.</p>';
      await source.writeAsBytes(
        _wellFormedEpubBytes(chapters: {'body.xhtml': paragraphs}),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: item,
        source: source,
      );
      final before = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      for (var i = 0; i < before.length; i++) {
        final row = before[i], text = before[i]['plain_text'] as String;
        await db.insert('elibrary_markups', {
          'library_item_id': item,
          'epub_href': 'canonical:${row['id']}',
          'start_block_index': 0,
          'end_block_index': 0,
          'start_char_offset': 0,
          'end_char_offset': 4,
          'selected_text_snapshot': text.substring(0, 4),
          'markup_type': i == 0 ? 'highlight' : 'underline',
          'color': '#FFFF00',
          'created_at': now,
          'updated_at': now,
        });
      }
      await db.update(
        'library_items',
        {'anchor_id': 'canonical:${before.last['id']}'},
        where: 'id=?',
        whereArgs: [item],
      );
      final markups = await db.query('elibrary_markups');
      final catalog = await db.query('library_items');
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: {'body.xhtml': '<h1 id="year">1897</h1>$paragraphs'},
          ),
          '<ncx><navMap><navPoint><navLabel><text>1897</text></navLabel>'
          '<content src="body.xhtml#year"/></navPoint></navMap></ncx>',
        ),
      );
      for (var pass = 0; pass < 2; pass++) {
        final result = await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: item,
          source: source,
          force: true,
        );
        expect(result.activated, true, reason: result.validationFailureReason);
        final rows = await db.query(
          'library_document_blocks',
          orderBy: 'display_order',
        );
        expect(rows.map((r) => r['plain_text']), [
          '1897',
          ...before.map((r) => r['plain_text']),
        ]);
        expect(rows.skip(1).map((r) => r['id']), before.map((r) => r['id']));
        expect(await db.query('elibrary_markups'), markups);
        expect(await db.query('library_items'), catalog);
        expect(
          (await db.query(
            'library_document_navigation',
          )).single['target_block_id'],
          rows.first['id'],
        );
        final maps = await db.query('library_block_source_map');
        expect(
          maps.map((r) => r['block_id']).toSet(),
          rows.map((r) => r['id']).toSet(),
        );
        expect(
          await LibraryDocumentRepository(
            db,
          ).displayOrderForBlockId(item, before.last['id'] as String),
          2,
        );
      }
    },
  );

  test(
    'a saved position cannot silently attach to replacement text at the same ordinal',
    () async {
      final source = File(p.join(directory.path, 'ordinal-replacement.epub'));
      const item = 'ordinal-replacement';
      await db.insert('library_items', {
        'id': item,
        'title': 'Ordinal fixture',
        'file_name': 'ordinal-replacement.epub',
        'relative_path': 'ordinal-replacement.epub',
        'source_type': 'user_epub_import',
        'created_at': 'test',
        'updated_at': 'test',
        'device_id': 'test',
      });
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {'body.xhtml': '<p>Original words.</p>'},
        ),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: item,
        source: source,
      );
      final before = await db.query('library_document_blocks');
      await db.update(
        'library_items',
        {'anchor_id': 'canonical:${before.single['id']}'},
        where: 'id=?',
        whereArgs: [item],
      );
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {'body.xhtml': '<p>Different paragraph.</p>'},
        ),
      );
      await expectLater(
        const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: item,
          source: source,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('saved reading position'),
          ),
        ),
      );
      expect(await db.query('library_document_blocks'), before);
    },
  );

  test(
    'page-only prefix before an authored target never becomes stylesheet prose',
    () async {
      final source = File(p.join(directory.path, 'page-prefix.epub'));
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: {
              'index.xhtml':
                  '<html><head><title>Index</title><style>body { margin: 1em; }</style></head>'
                  '<body><h6>748</h6><h1 id="index">Index</h1><p>Original index text.</p></body></html>',
            },
          ),
          '<ncx><navMap><navPoint id="index"><navLabel><text>Index</text></navLabel>'
          '<content src="index.xhtml#index"/></navPoint></navMap></ncx>',
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'page-prefix',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(rows.map((r) => r['plain_text']).toList(), [
        'Index',
        'Original index text.',
      ]);
      for (final row in rows) {
        expect(
          (jsonDecode(row['formatted_content'] as String)
              as Map)['metadata']['source_page_start'],
          748,
        );
      }
      final navigation = await LibraryDocumentRepository(
        db,
      ).loadCanonicalNavigationDestinations('page-prefix');
      expect(navigation.single.block.id, rows.first['id']);
    },
  );

  test(
    'metadata and scripts containing apparent paragraphs cannot become book text',
    () async {
      final source = File(p.join(directory.path, 'non-reading.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml':
                '<html><head><title>Metadata title</title>'
                '<style>.example:after { content: "<p>CSS sample</p>"; }</style></head>'
                '<body><!-- <p>Comment sample</p> --><p>Original reading text.</p>'
                '<script>const sample = "<p>Script sample</p>";</script></body></html>',
          },
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'non-reading',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      expect(
        (await db.query('library_document_blocks')).single['plain_text'],
        'Original reading text.',
      );
    },
  );

  test(
    'fallback retains unwrapped body text while excluding page numbers and metadata',
    () async {
      final source = File(p.join(directory.path, 'unwrapped.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml':
                '<html><head><title>Metadata</title></head><body><h6>42</h6>'
                '<span>Keep the original &lt;p&gt; example and all unwrapped text.</span></body></html>',
          },
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'unwrapped',
        source: source,
      );
      expect(result.activated, true, reason: result.validationFailureReason);
      expect(
        (await db.query('library_document_blocks')).single['plain_text'],
        'Keep the original <p> example and all unwrapped text.',
      );
    },
  );

  test(
    'verified citations follow source identity and preserve marked text',
    () async {
      const text = 'Keep these selected words intact.';
      final source = File(p.join(directory.path, 'source.epub'));
      final bytes = _wellFormedEpubBytes(
        chapters: {'chapter.xhtml': '<h1>Chapter One</h1><p>$text</p>'},
      );
      await source.writeAsBytes(bytes);
      const importer = LibraryDocumentCanonicalizer();
      await importer.canonicalize(
        db: db,
        libraryItemId: 'first-id',
        source: source,
      );
      final before = (await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      )).last;
      await db.insert('elibrary_markups', {
        'library_item_id': 'first-id',
        'epub_href': 'canonical:${before['id']}',
        'start_block_index': 0,
        'start_char_offset': 11,
        'end_block_index': 0,
        'end_char_offset': 25,
        'selected_text_snapshot': 'selected words',
        'markup_type': 'underline',
        'color': '#FFFF00',
        'note_text': 'Keep my note',
        'created_at': 'original',
        'updated_at': 'original',
      });
      final markups = await db.query('elibrary_markups');
      final alignment = <String, Object?>{
        'source_hash': sha256.convert(bytes).toString(),
        'source_href': 'oebps/chapter.xhtml',
        'source_block_ordinal': 1,
        'source_text_hash': sha256.convert(utf8.encode(text)).toString(),
        'work_prefix': 'DAR',
        'page_number': 24,
        'paragraph_number': 2,
        'witness_uri': 'https://example.org/edition/paragraph',
        'witness_text_hash': sha256.convert(utf8.encode(text)).toString(),
        'match_method': 'normalized_exact',
      };
      await db.insert('library_source_reference_map', alignment);
      await importer.canonicalize(
        db: db,
        libraryItemId: 'first-id',
        source: source,
        force: true,
      );
      final after = (await db.query(
        'library_document_blocks',
        where: 'id = ?',
        whereArgs: [before['id']],
      )).single;
      expect(after['plain_text'], before['plain_text']);
      expect(after['source_refcode'], 'DAR 24.2');
      expect(after['reference_prefix'], 'DAR');
      expect(after['reference_page'], 24);
      expect(after['reference_paragraph'], 2);
      expect(after['reference_origin'], 'verified_source_alignment');
      expect(after['reference_witness'], alignment['witness_uri']);
      expect(await db.query('elibrary_markups'), markups);
      final renamed = await source.copy(
        p.join(directory.path, 'another-name.epub'),
      );
      await importer.canonicalize(
        db: db,
        libraryItemId: 'second-id',
        source: renamed,
      );
      expect(
        (await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: ['second-id'],
          orderBy: 'display_order',
        )).last['source_refcode'],
        'DAR 24.2',
      );

      await db.update('library_source_reference_map', {
        'source_text_hash': 'wrong',
      });
      await expectLater(
        importer.canonicalize(
          db: db,
          libraryItemId: 'first-id',
          source: source,
          force: true,
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'library_document_blocks',
          where: 'id = ?',
          whereArgs: [before['id']],
        )).single,
        after,
      );
      expect(await db.query('elibrary_markups'), markups);

      await db.update('library_source_reference_map', {
        'source_text_hash': alignment['source_text_hash'],
        'source_block_ordinal': 999,
      });
      await expectLater(
        importer.canonicalize(
          db: db,
          libraryItemId: 'first-id',
          source: source,
          force: true,
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'library_document_blocks',
          where: 'id = ?',
          whereArgs: [before['id']],
        )).single,
        after,
      );
      await renamed.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {'chapter.xhtml': '<h1>Different edition</h1><p>$text</p>'},
        ),
      );
      await importer.canonicalize(
        db: db,
        libraryItemId: 'different-edition',
        source: renamed,
      );
      expect(
        (await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: ['different-edition'],
          orderBy: 'display_order',
        )).last['source_refcode'],
        isNull,
      );
    },
  );

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
    'inserting content preserves markup but changing its selected words blocks activation',
    () async {
      final source = File(p.join(directory.path, 'marked.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'chapter.xhtml':
                '<h1>Chapter One</h1><p>Keep these selected words intact.</p>',
          },
        ),
      );
      const importer = LibraryDocumentCanonicalizer();
      await importer.canonicalize(
        db: db,
        libraryItemId: 'marked',
        source: source,
      );
      final before = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['marked'],
        orderBy: 'display_order',
      );
      final paragraph = before.last;
      await db.insert('elibrary_markups', {
        'library_item_id': 'marked',
        'epub_href': 'canonical:${paragraph['id']}',
        'start_block_index': 0,
        'start_char_offset': 11,
        'end_block_index': 0,
        'end_char_offset': 25,
        'selected_text_snapshot': 'selected words',
        'markup_type': 'underline',
        'color': '#FFFF00',
        'note_text': 'My original note',
        'created_at': 'original',
        'updated_at': 'original',
      });
      final originalMarkup = await db.query('elibrary_markups');
      await importer.canonicalize(
        db: db,
        libraryItemId: 'marked',
        source: source,
        force: true,
      );
      expect(await db.query('elibrary_markups'), originalMarkup);
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'chapter.xhtml':
                '<h1>New heading</h1><p>Inserted paragraph.</p>'
                '<h1>Chapter One</h1><p>Keep these selected words intact.</p>',
          },
        ),
      );
      final inserted = await importer.canonicalize(
        db: db,
        libraryItemId: 'marked',
        source: source,
        force: true,
      );
      expect(inserted.activated, true);
      final afterInsertion = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['marked'],
        orderBy: 'display_order',
      );
      expect(
        afterInsertion.skip(2).map((b) => b['id']),
        before.map((b) => b['id']),
      );
      expect(afterInsertion.last['plain_text'], paragraph['plain_text']);
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'chapter.xhtml':
                '<h1>New heading</h1><p>Inserted paragraph.</p>'
                '<h1>Chapter One</h1><p>Keep these different words intact.</p>',
          },
        ),
      );
      await expectLater(
        importer.canonicalize(
          db: db,
          libraryItemId: 'marked',
          source: source,
          force: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await db.query(
          'library_document_blocks',
          where: 'library_item_id=?',
          whereArgs: ['marked'],
          orderBy: 'display_order',
        ),
        afterInsertion,
      );
      expect(await db.query('elibrary_markups'), originalMarkup);
      expect(
        (await db.query('library_document_conversion')).single['status'],
        'complete',
      );
    },
  );

  test(
    'preserves source spelling in the SL27 heading for explicit reconciliation',
    () async {
      final source = File(p.join(directory.path, 'sl27.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: <String, String>{
            'ch1.xhtml': '<h2>ARGUMET</h2><p>Senator Blair. - Very well.</p>',
          },
        ),
        flush: true,
      );

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'SL27',
        source: source,
      );

      final heading = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>['SL27', 'heading'],
      );
      expect(heading.single['plain_text'], 'ARGUMET');
    },
  );

  test('preserves source wording in both headings and paragraphs', () async {
    final source = File(p.join(directory.path, 'unrelated.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml':
              '<h2>COUNTERARGUMET Section</h2>'
              '<p>ARGUMET should not change here.</p>',
        },
      ),
      flush: true,
    );

    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'UNRELATED',
      source: source,
    );

    final heading = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['UNRELATED', 'heading'],
    );
    // Importing does not perform editorial spelling corrections.
    expect(heading.single['plain_text'], 'COUNTERARGUMET Section');
    final paragraph = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['UNRELATED', 'paragraph'],
    );
    // Editorial corrections belong in separately logged source revisions.
    expect(paragraph.single['plain_text'], 'ARGUMET should not change here.');
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
    'preserves a whole-file parent H1 and lead prose before anchored children',
    () async {
      final source = File(p.join(directory.path, 'parent-with-children.epub'));
      const chapter = '''<html><head><title>Parent chapter</title></head><body>
<h1>Parent Chapter</h1><p>Parent lead prose survives.</p>
<h2 id="child-one">First Child</h2><p>First child prose.</p>
<h2 id="child-two">Second Child</h2><p>Second child prose.</p>
</body></html>''';
      const ncx = '''<ncx><navMap>
<navPoint><navLabel><text>Parent Chapter</text></navLabel><content src="chapter.xhtml"/>
  <navPoint><navLabel><text>First Child</text></navLabel><content src="chapter.xhtml#child-one"/></navPoint>
  <navPoint><navLabel><text>Second Child</text></navLabel><content src="chapter.xhtml#child-two"/></navPoint>
</navPoint></navMap></ncx>''';
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: <String, String>{'chapter.xhtml': chapter},
          ),
          ncx,
        ),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'PARENT_WITH_CHILDREN',
        source: source,
      );

      expect(result.activated, isTrue);
      final sections = await db.query(
        'library_document_sections',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['PARENT_WITH_CHILDREN'],
        orderBy: 'display_order',
      );
      expect(
        sections.map((row) => row['title']),
        orderedEquals(<String>[
          'Parent Chapter',
          'First Child',
          'Second Child',
        ]),
      );
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['PARENT_WITH_CHILDREN'],
        orderBy: 'display_order',
      );
      expect(
        blocks.map((row) => row['plain_text']),
        orderedEquals(<String>[
          'Parent Chapter',
          'Parent lead prose survives.',
          'First Child',
          'First child prose.',
          'Second Child',
          'Second child prose.',
        ]),
      );
    },
  );

  test(
    'printed pages survive across sections without inventing paragraph codes',
    () async {
      final source = File(p.join(directory.path, 'printed-pages.epub'));
      final bytes = _wellFormedEpubBytes(
        chapters: {
          'one.xhtml': '<h2>Chapter One</h2><h1>10</h1><p>First paragraph.</p>',
          'two.xhtml':
              '<p>Still page ten. <span class="Red">[11]</span> Continues.</p><p>Page eleven, with ordinary [42] in prose.</p>',
        },
      );
      await source.writeAsBytes(bytes);
      await db.insert('library_source_page_profiles', {
        'source_hash': sha256.convert(bytes).toString(),
        'page_marker_span_class': 'Red',
        'evidence': 'Synthetic fixture with explicit print page markers',
      });
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'PRINT_PAGES',
        source: source,
      );
      expect(result.activated, isTrue);
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['PRINT_PAGES'],
        orderBy: 'display_order',
      );
      final blocks = rows.map(LibraryDocumentBlock.fromRow).toList();
      expect(blocks[1].pageReference, 'p. 10');
      expect(blocks[2].pageReference, 'pp. 10–11');
      expect(blocks[3].pageReference, 'p. 11');
      expect(blocks[2].plainText, contains('[11]'));
      expect(blocks.every((b) => b.sourceRefcode == null), isTrue);

      // A changed file does not inherit assumptions made about another source.
      final changed = _wellFormedEpubBytes(
        chapters: {
          'one.xhtml':
              '<h2>Chapter One</h2><p>Ordinary <span class="Red">[42]</span> label.</p>',
        },
      );
      await source.writeAsBytes(changed);
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'OTHER_SOURCE',
        source: source,
      );
      final other = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['OTHER_SOURCE'],
      );
      expect(
        other
            .map(LibraryDocumentBlock.fromRow)
            .every((b) => b.pageReference == null),
        isTrue,
      );
    },
  );

  test(
    'nested span anchors keep authored headings and every paragraph',
    () async {
      final source = File(p.join(directory.path, 'nested-headings.epub'));
      const chapter =
          '<html><body><p>Unlisted preface survives.</p>'
          '<h2 class="title"><span id="first"/>FIRST ARTICLE</h2>'
          '<p>First body with <em>emphasis</em>.</p>'
          '<h2><span id="second"/>SECOND ARTICLE</h2><p>Last body.</p>'
          '</body></html>';
      const ncx =
          '<ncx><navMap>'
          '<navPoint><navLabel><text>First article</text></navLabel>'
          '<content src="content.xhtml#first"/></navPoint>'
          '<navPoint><navLabel><text>Second article</text></navLabel>'
          '<content src="content.xhtml#second"/></navPoint></navMap></ncx>';
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(chapters: {'content.xhtml': chapter}),
          ncx,
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'NESTED_ANCHORS',
        source: source,
      );
      expect(result.activated, isTrue);
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['NESTED_ANCHORS'],
        orderBy: 'display_order',
      );
      expect(blocks.map((b) => b['plain_text']), [
        'Unlisted preface survives.',
        'FIRST ARTICLE',
        'First body with emphasis.',
        'SECOND ARTICLE',
        'Last body.',
      ]);
      expect(blocks[1]['source_anchor'], 'first');
      expect(blocks[3]['source_anchor'], 'second');
    },
  );

  test(
    'leaf div headings and paragraphs survive inside nested layout wrappers',
    () async {
      final source = File(p.join(directory.path, 'div-blocks.epub'));
      const html =
          '<html><body><div class="layout">'
          '<div class="image-frame"><img src="plate.png" alt="Original plate"/></div>'
          '<div><p>Unlisted preface survives.</p></div>'
          '<div class="s8"><span id="first"/>FIRST ARTICLE</div>'
          '<div class="s1">First body with <em>emphasis</em>.</div>'
          '<div class="nested"><div class="s8"><span id="second"/>SECOND ARTICLE</div>'
          '<div class="s1">Last body.</div></div></div></body></html>';
      const ncx =
          '<ncx><navMap>'
          '<navPoint><navLabel><text>First article</text></navLabel>'
          '<content src="content.xhtml#first"/></navPoint>'
          '<navPoint><navLabel><text>Second article</text></navLabel>'
          '<content src="content.xhtml#second"/></navPoint></navMap></ncx>';
      final archive = ZipDecoder().decodeBytes(
        _withNcx(_wellFormedEpubBytes(chapters: {'content.xhtml': html}), ncx),
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      archive.addFile(ArchiveFile('OEBPS/plate.png', png.length, png));
      await source.writeAsBytes(ZipEncoder().encode(archive));
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'DIV_BLOCKS',
        source: source,
      );
      expect(result.activated, isTrue, reason: result.validationFailureReason);
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['DIV_BLOCKS'],
        orderBy: 'display_order',
      );
      expect(blocks.map((b) => b['plain_text']), [
        'Original plate',
        'Unlisted preface survives.',
        'FIRST ARTICLE',
        'First body with emphasis.',
        'SECOND ARTICLE',
        'Last body.',
      ]);
      final resolved = await db.rawQuery(
        'SELECT n.label, b.plain_text FROM library_document_navigation n '
        'LEFT JOIN library_document_blocks b ON b.id = n.target_block_id '
        'WHERE n.library_item_id = ? ORDER BY n.display_order',
        ['DIV_BLOCKS'],
      );
      expect(resolved.map((r) => r['plain_text']), [
        'FIRST ARTICLE',
        'SECOND ARTICLE',
      ]);
      expect(blocks.first['block_type'], 'image');
      final formatted =
          jsonDecode(blocks[3]['formatted_content'] as String) as Map;
      expect(formatted['metadata']['source_tag'], 'div');
      expect(
        (formatted['nodes'] as List).cast<Map>().firstWhere(
          (n) => n['text'] == 'emphasis',
        )['marks'],
        contains('italic'),
      );
    },
  );

  test(
    'linked CSS emphasis survives anchored chapter splits and nested spans',
    () async {
      final source = File(p.join(directory.path, 'css-emphasis.epub'));
      const html =
          '<html><head><link rel="stylesheet" href="styles.css"/></head>'
          '<body><h2 id="first">First</h2>'
          '<p>Plain <span class="Italic">italic <span>nested</span> '
          '<span style="font-style:normal">normal</span> italic again</span> '
          '<span class="Bold">bold</span> end.</p>'
          '<h2 id="second">Second</h2><p class="outline">Styled paragraph.</p>'
          '</body></html>';
      const ncx =
          '<ncx><navMap>'
          '<navPoint><navLabel><text>First</text></navLabel><content src="content.xhtml#first"/></navPoint>'
          '<navPoint><navLabel><text>Second</text></navLabel><content src="content.xhtml#second"/></navPoint>'
          '</navMap></ncx>';
      final archive = ZipDecoder().decodeBytes(
        _withNcx(_wellFormedEpubBytes(chapters: {'content.xhtml': html}), ncx),
      );
      const css =
          'span.Italic {font-style:italic;font-weight:normal;}'
          'span.Bold {font-weight:bold;} p.outline {font-style:italic;}';
      archive.addFile(
        ArchiveFile('OEBPS/styles.css', css.length, css.codeUnits),
      );
      await source.writeAsBytes(ZipEncoder().encode(archive));
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'CSS',
        source: source,
      );
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['CSS'],
        orderBy: 'display_order',
      );
      final nodes =
          (jsonDecode(blocks[1]['formatted_content'] as String)['nodes']
                  as List)
              .cast<Map>();
      Map containing(String text) =>
          nodes.firstWhere((n) => (n['text'] as String).contains(text));
      expect(containing('nested')['marks'], contains('italic'));
      expect(containing('normal')['marks'], isNull);
      expect(containing('italic again')['marks'], contains('italic'));
      expect(containing('bold')['marks'], contains('bold'));
      expect(containing('end.')['marks'], isNull);
      expect(
        blocks[1]['plain_text'],
        'Plain italic nested normal italic again bold end.',
      );
      expect(
        jsonDecode(
          blocks.last['formatted_content'] as String,
        )['nodes'][0]['marks'],
        contains('italic'),
      );
    },
  );

  test(
    'unstyled nested spans preserve outer emphasis and stop at its closing tag',
    () async {
      final source = File(p.join(directory.path, 'nested-emphasis.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'chapter.xhtml':
                '<p><em>First <span>middle</span> last</em> plain '
                '<strong>bold <a href="#note"><span>link</span></a> end</strong>.</p>',
          },
        ),
      );
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'EMPHASIS',
        source: source,
      );
      expect(result.activated, isTrue);
      final row = (await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: ['EMPHASIS'],
      )).single;
      final nodes =
          (jsonDecode(row['formatted_content'] as String) as Map)['nodes']
              as List;
      Map nodeContaining(String text) =>
          nodes.cast<Map>().firstWhere((n) => (n['text'] ?? '').contains(text));
      expect(nodeContaining('middle')['marks'], contains('italic'));
      expect(nodeContaining('last')['marks'], contains('italic'));
      expect(nodeContaining('plain')['marks'], isNull);
      expect(nodeContaining('link')['marks'], contains('bold'));
      expect(nodeContaining('link')['link'], '#note');
      expect(nodeContaining('end')['marks'], contains('bold'));
      expect(nodeContaining('end')['link'], isNull);
      expect(row['plain_text'], 'First middle last plain bold link end.');
    },
  );

  test('paragraph heading classes retain structure and source identity', () async {
    final source = File(p.join(directory.path, 'paragraph-headings.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: {
          'part.xhtml':
              '<p id="part" class="Header-Main">Response of History to the Revelation</p>'
              '<p id="chapter" class="Heading-1">Chapter 1 — Opening Vision</p>'
              '<p>Body remains body.</p>',
        },
      ),
    );
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'PARAGRAPH_HEADINGS',
      source: source,
    );
    final headings = await LibraryDocumentRepository(
      db,
    ).loadHeadings('PARAGRAPH_HEADINGS');
    expect(headings.map((b) => b.sourceAnchor), ['part', 'chapter']);
    expect(headings.map((b) => b.headingRole), ['part', 'chapter']);
  });

  test('keeps fragment-only single-spine splitting unchanged', () async {
    final source = File(p.join(directory.path, 'fragment-only.epub'));
    const chapter = '''<html><body>
<h2 id="introduction">INTRODUCTION</h2><p>Introduction prose.</p>
<h2 id="appendix">APPENDIX A</h2><p>Appendix prose.</p>
</body></html>''';
    const ncx = '''<ncx><navMap>
<navPoint><navLabel><text>INTRODUCTION</text></navLabel><content src="content.xhtml#introduction"/></navPoint>
<navPoint><navLabel><text>APPENDIX A</text></navLabel><content src="content.xhtml#appendix"/></navPoint>
</navMap></ncx>''';
    await source.writeAsBytes(
      _withNcx(
        _wellFormedEpubBytes(
          chapters: <String, String>{'content.xhtml': chapter},
        ),
        ncx,
      ),
      flush: true,
    );

    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'FRAGMENT_ONLY',
      source: source,
    );
    final sections = await db.query(
      'library_document_sections',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>['FRAGMENT_ONLY'],
      orderBy: 'display_order',
    );
    expect(
      sections.map((row) => row['title']),
      orderedEquals(<String>['INTRODUCTION', 'APPENDIX A']),
    );
  });

  test(
    'rejects invalid authored navigation while preserving the complete source',
    () async {
      final source = File(p.join(directory.path, 'invalid-anchor.epub'));
      const chapter = '''<html><body>
<h1>Parent Chapter</h1><p>Parent lead prose.</p>
<h2 id="child-one">First Child</h2><p>First child prose.</p>
<h2 id="child-two">Second Child</h2><p>Second child prose.</p>
</body></html>''';
      const ncx = '''<ncx><navMap>
<navPoint><navLabel><text>Parent Chapter</text></navLabel><content src="chapter.xhtml"/>
  <navPoint><navLabel><text>First Child</text></navLabel><content src="chapter.xhtml#child-one"/></navPoint>
  <navPoint><navLabel><text>Missing Child</text></navLabel><content src="chapter.xhtml#missing"/></navPoint>
  <navPoint><navLabel><text>Second Child</text></navLabel><content src="chapter.xhtml#child-two"/></navPoint>
</navPoint></navMap></ncx>''';
      await source.writeAsBytes(
        _withNcx(
          _wellFormedEpubBytes(
            chapters: <String, String>{'chapter.xhtml': chapter},
          ),
          ncx,
        ),
        flush: true,
      );

      final sourceBefore = await source.readAsBytes();
      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'INVALID_ANCHOR',
        source: source,
      );
      expect(result.activated, isFalse);
      expect(result.validationFailureReason, contains('Missing Child'));
      expect(await source.readAsBytes(), sourceBefore);
      expect(
        await db.query(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: ['INVALID_ANCHOR'],
        ),
        isEmpty,
      );
      final preservedArchive = ZipDecoder().decodeBytes(
        await source.readAsBytes(),
      );
      expect(
        utf8.decode(preservedArchive.findFile('OEBPS/chapter.xhtml')!.content),
        chapter,
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

  test('image-only paragraphs preserve assets and both navigation anchors', () async {
    final source = File(p.join(directory.path, 'wrapped-cover.epub'));
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    final archive = ZipDecoder().decodeBytes(
      _withNcx(
        _wellFormedEpubBytes(
          chapters: {
            'cover.xhtml':
                '<html><head><title>Metadata title is not prose</title></head><body>'
                '<p id="cover-wrapper" class="center"><img id="cover-image" '
                'src="cover.png" alt="Original plate"/> &nbsp;&#160;&#xA0;</p></body></html>',
            'body.xhtml': '<h1>Opening</h1><p>Original body text.</p>',
          },
        ),
        '<ncx><navMap>'
        '<navPoint><navLabel><text>Cover wrapper</text></navLabel>'
        '<content src="cover.xhtml#cover-wrapper"/></navPoint>'
        '<navPoint><navLabel><text>Cover image</text></navLabel>'
        '<content src="cover.xhtml#cover-image"/></navPoint>'
        '</navMap></ncx>',
      ),
    );
    archive.addFile(ArchiveFile('OEBPS/cover.png', png.length, png));
    await source.writeAsBytes(ZipEncoder().encode(archive));
    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'wrapped-cover',
      source: source,
    );
    expect(result.activated, true, reason: result.validationFailureReason);
    final rows = await db.query(
      'library_document_blocks',
      orderBy: 'display_order',
    );
    expect(rows.map((r) => r['plain_text']), [
      'Original plate',
      'Opening',
      'Original body text.',
    ]);
    expect(rows.first['block_type'], 'image');
    expect(rows.first['source_anchor'], 'cover-wrapper');
    final formatted = LibraryFormattedContent.fromJson(
      rows.first['formatted_content'] as String,
    );
    expect(formatted.metadata['source_anchor_aliases'], ['cover-image']);
    expect(formatted.alignment, 'center');
    final asset =
        Directory(
              p.join(directory.path, '_canonical_assets', 'wrapped-cover'),
            ).listSync().single
            as File;
    expect(asset.readAsBytesSync(), png);
    final nav = await db.query(
      'library_document_navigation',
      orderBy: 'display_order',
    );
    expect(nav, hasLength(2));
    expect(nav.every((n) => n['target_block_id'] == rows.first['id']), true);
  });

  test(
    'mixed text and nested image fail visibly without replacing prior content',
    () async {
      final source = File(p.join(directory.path, 'mixed-image.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: {
            'body.xhtml': '<h1>Opening</h1><p>Previously readable text.</p>',
          },
        ),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'mixed-image',
        source: source,
      );
      final before = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final conversion = await db.query('library_document_conversion');
      final changed = _wellFormedEpubBytes(
        chapters: {
          'body.xhtml':
              '<h1>Opening</h1><p>Before <img src="plate.png"/> after.</p>',
        },
      );
      await source.writeAsBytes(changed);
      await expectLater(
        const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'mixed-image',
          source: source,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('Nested image layout'),
          ),
        ),
      );
      expect(
        await db.query('library_document_blocks', orderBy: 'display_order'),
        before,
      );
      expect(await db.query('library_document_conversion'), conversion);
      expect(await source.readAsBytes(), changed);
      expect(
        (await db.query(
          'library_document_conversion_staging',
        )).single['status'],
        'failed',
      );
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

  test(
    'combined OCR work restarts chapters only at an explicit new part',
    () async {
      final source = File(p.join(directory.path, 'combined.epub'));
      final chapters = <String, String>{
        'front.xhtml':
            '<p>Table of Contents 01 - DANIEL IN CAPTIVITY '
            '02 - THE GREAT IMAGE 03 - THE FIERY ORDEAL</p>',
        'daniel.xhtml':
            '<p>Response of History to the Prophecy of Daniel '
            '01 - DANIEL IN CAPTIVITY Here is the first chapter.</p>'
            '<p id="preserved" style="text-align:right">See John 3:16 and '
            '<em>emphasis</em> with '
            '<a href="https://example.org/reference">authored link</a>.</p>',
        for (var i = 2; i <= 12; i++)
          'daniel_$i.xhtml': i == 11
              ? '<p>11 - A LITERAL PROPHECY Succession of kings.</p>'
              : '<p>$i - DANIEL CHAPTER Body text of chapter $i.</p>',
        // An isolated repeated chapter number is not permission to restart.
        'quotation.xhtml':
            '<p>01 - AN INCIDENTAL QUOTATION Within later prose.</p>',
        'revelation_intro.xhtml':
            '<p>Response of History to The Revelation '
            'This is the introduction to the second part.</p>',
        'revelation.xhtml':
            '<p>01 - THE OPENING VISION Here is Revelation one.</p>',
        for (var i = 2; i <= 22; i++)
          'revelation_$i.xhtml':
              '<p>$i - REVELATION CHAPTER Body text of chapter $i.</p>',
      };
      await source.writeAsBytes(_wellFormedEpubBytes(chapters: chapters));
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'combined',
        source: source,
      );
      final preserved = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ? AND source_anchor = ?',
        whereArgs: ['combined', 'preserved'],
      );
      expect(preserved, hasLength(1));
      expect(
        preserved.single['plain_text'],
        'See John 3:16 and emphasis with authored link.',
      );
      final formatted = LibraryFormattedContent.fromJson(
        preserved.single['formatted_content'] as String,
      );
      expect(formatted.alignment, 'right');
      expect(
        formatted.nodes.any(
          (node) =>
              node['text'] == 'emphasis' &&
              (node['marks'] as List?)?.contains('italic') == true,
        ),
        isTrue,
      );
      expect(
        formatted.nodes.any(
          (node) => node['link'] == 'https://example.org/reference',
        ),
        isTrue,
      );
      expect(
        formatted.nodes.any(
          (node) =>
              node['text'] == 'John 3:16' &&
              node['link'].toString().startsWith('studybible-citation:'),
        ),
        isTrue,
      );
      final headings = await db.rawQuery('''
      SELECT plain_text FROM library_document_blocks
      WHERE library_item_id = 'combined' AND block_type = 'heading'
        AND json_extract(formatted_content, '\$.metadata.heading_role') = 'chapter'
      ORDER BY display_order
    ''');
      expect(headings, hasLength(34));
      expect(headings[12]['plain_text'], '01 - THE OPENING VISION');
      expect(headings.last['plain_text'], '22 - REVELATION CHAPTER');
      final prose = await db.rawQuery('''
      SELECT plain_text FROM library_document_blocks
      WHERE library_item_id = 'combined' AND block_type = 'paragraph'
    ''');
      expect(
        prose.any(
          (r) => r['plain_text'].toString().contains('AN INCIDENTAL QUOTATION'),
        ),
        isTrue,
      );
    },
  );

  test('recovers chapter headings from unmarked OCR "NN - TITLE" runs when a '
      'book has no semantic heading tags anywhere in its spine', () async {
    final source = File(p.join(directory.path, 'archive_org_scan.epub'));
    // Reproduces the real archive.org page-scan shape: one flat <p> per
    // scanned page, no <h#> tags anywhere, chapter titles buried
    // mid-paragraph with no boundary marker, and a front-matter page that
    // dumps the whole table of contents as one more "NN - CAPS" blob (out
    // of sequence, so it must be rejected rather than misread as chapter
    // 21).
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'page_0.xhtml': '<p>The Test Book Some Author</p>',
          'page_1.xhtml':
              '<p>21 - THE NEW JERUSALEM 22 - THE TREE AND THE RIVER OF LIFE '
              'APPENDIX 1. RESEMBLANCE BETWEEN OUR TIMES</p>',
          'page_2.xhtml':
              '<p>Response of History to the Prophecy 01 - DANIEL IN '
              'CAPTIVITY Character sketch of Daniel continues here as '
              'real body prose about his early life.</p>',
          'page_3.xhtml':
              '<p>More body text continuing chapter one across a page '
              'boundary with no heading markup at all.</p>',
          'page_4.xhtml':
              '<p>02 - THE GREAT IMAGE A Difficulty Explained - Daniel '
              'Enters upon His Work - outline text. VERSE 1. And in '
              'the second year of the reign of Nebuchadnezzar.</p>',
        },
      ),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'OCR_SCAN',
      source: source,
    );
    expect(result.activated, isTrue);

    final headingRows = await db.query(
      'library_document_blocks',
      columns: const <String>['plain_text', 'formatted_content'],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['OCR_SCAN', 'heading'],
      orderBy: 'display_order',
    );
    expect(
      headingRows.map((row) => row['plain_text']),
      orderedEquals(<String>[
        '01 - DANIEL IN CAPTIVITY',
        '02 - THE GREAT IMAGE',
      ]),
    );
    for (final row in headingRows) {
      expect(
        row['formatted_content'].toString(),
        contains('"heading_role":"chapter"'),
      );
    }

    // The TOC dump's out-of-sequence "21 -"/"22 -" runs must survive as
    // ordinary paragraph text, not be misread as chapters.
    final tocParagraph = await db.query(
      'library_document_blocks',
      columns: const <String>['plain_text'],
      where: 'library_item_id = ? AND block_type = ? AND plain_text LIKE ?',
      whereArgs: <Object?>['OCR_SCAN', 'paragraph', '21 - THE NEW JERUSALEM%'],
    );
    expect(tocParagraph, hasLength(1));

    final repository = LibraryDocumentRepository(db);
    final opening = await repository.openingDisplayOrder('OCR_SCAN');
    final openingRow = await db.query(
      'library_document_blocks',
      columns: const <String>['plain_text'],
      where: 'library_item_id = ? AND display_order = ?',
      whereArgs: <Object?>['OCR_SCAN', opening],
    );
    expect(openingRow.single['plain_text'], '01 - DANIEL IN CAPTIVITY');
  });

  test(
    'a book with at least one real semantic heading anywhere is never '
    'touched by OCR heading recovery, even if most pages are flat <p> text',
    () async {
      final source = File(p.join(directory.path, 'mixed.epub'));
      await source.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: <String, String>{
            'page_0.xhtml': '<p>Front matter with no heading markup.</p>',
            'page_1.xhtml': '<h2>Chapter 1</h2><p>Real semantic heading.</p>',
            'page_2.xhtml':
                '<p>02 - SOME LATER PAGE that would match the OCR pattern '
                'if recovery were active here, but it must not be.</p>',
          },
        ),
        flush: true,
      );

      final result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'MIXED',
        source: source,
      );
      expect(result.activated, isTrue);

      final headingRows = await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>['MIXED', 'heading'],
      );
      expect(headingRows.map((row) => row['plain_text']), <String>[
        'Chapter 1',
      ]);
    },
  );

  test('OCR heading recovery still fires when the only real heading tag in the '
      'whole spine belongs to the EPUB nav document itself (the real '
      'archive.org export shape: nav.xhtml carries its own <h2> title and is '
      'itself the first spine entry)', () async {
    final source = File(p.join(directory.path, 'nav_doc.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'nav.xhtml':
              '<nav epub:type="toc" id="id" role="doc-toc">'
              '<h2>Adventist Pioneer Authors - Test Author</h2>'
              '<ol><li><a href="page_0.xhtml">Notice</a></li></ol>'
              '</nav>',
          'page_0.xhtml': '<p>Test Book Test Author</p>',
          'page_1.xhtml':
              '<p>01 - CHAPTER ONE Some outline text continues the page '
              'with real body prose about the opening chapter.</p>',
          'page_2.xhtml':
              '<p>More body text finishing chapter one across a page '
              'boundary.</p>',
          'page_3.xhtml':
              '<p>02 - CHAPTER TWO More outline text and body prose for '
              'the second chapter follows here.</p>',
        },
      ),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'NAV_DOC',
      source: source,
    );
    expect(result.activated, isTrue);

    final headingRows = await db.query(
      'library_document_blocks',
      columns: const <String>['plain_text'],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['NAV_DOC', 'heading'],
      orderBy: 'display_order',
    );
    expect(headingRows.map((row) => row['plain_text']), <String>[
      'Adventist Pioneer Authors - Test Author',
      '01 - CHAPTER ONE',
      '02 - CHAPTER TWO',
    ]);
  });

  test('OCR recovered chapter titles stop cleanly at the next chapter\'s own '
      'number and at APPENDIX/INDEX/PART back-matter markers, instead of '
      'running on into adjacent text with no boundary of their own', () async {
    final source = File(p.join(directory.path, 'boundaries.epub'));
    await source.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'page_0.xhtml': '<p>Front matter with no chapter markup.</p>',
          'page_1.xhtml': '<p>Second page of front matter, still none.</p>',
          'page_2.xhtml': '<p>Third page, still no chapter markers here.</p>',
          // Back-to-back chapter headings on the same page with no body
          // text between them — chapter 1's title must not swallow "02".
          'page_3.xhtml':
              '<p>01 - CHAPTER ONE 02 - CHAPTER TWO real body text for '
              'chapter two follows immediately here.</p>',
          // The final chapter runs straight into back matter with no
          // boundary at all — must stop before "APPENDIX".
          'page_4.xhtml':
              '<p>03 - CHAPTER THREE APPENDIX 1. SOME BACK MATTER LISTING '
              'that must not be absorbed into the chapter title.</p>',
        },
      ),
      flush: true,
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'BOUNDARIES',
      source: source,
    );
    expect(result.activated, isTrue);

    final headingRows = await db.query(
      'library_document_blocks',
      columns: const <String>['plain_text'],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['BOUNDARIES', 'heading'],
      orderBy: 'display_order',
    );
    expect(headingRows.map((row) => row['plain_text']), <String>[
      '01 - CHAPTER ONE',
      '02 - CHAPTER TWO',
      '03 - CHAPTER THREE',
    ]);
  });
}
