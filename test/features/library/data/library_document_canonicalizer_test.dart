import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/library_search_navigation_target.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  late File source;
  late List<int> fixtureBytes;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('canonical_elibrary_');
    db = await openDatabase(p.join(directory.path, 'test.db'));
    await ELibrarySchema.ensure(db);
    fixtureBytes = await File(
      'test/fixtures/elibrary/ssp_canonical_poc.html',
    ).readAsBytes();
    source = File(p.join(directory.path, 'ssp.html'));
    await source.writeAsBytes(fixtureBytes, flush: true);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('explicit chapter title supersedes a preceding poem heading', () async {
    await source.writeAsString(
      '<h2>The Perfect Sacrifice</h2>'
      '<p>Poem line.</p><h1>Chapter 18 - The Burnt-Offering</h1>'
      '<p id="body">The whole burnt-offering had its origin.</p>',
    );
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'chapter-title',
      source: source,
    );
    final body = (await db.query(
      'library_document_blocks',
      where: "library_item_id=? AND source_anchor='body'",
      whereArgs: ['chapter-title'],
    )).single;
    final location = await LibraryDocumentRepository(
      db,
    ).resolveLocation('chapter-title', body['display_order'] as int);
    expect(location?.heading?.plainText, 'Chapter 18 - The Burnt-Offering');
  });

  test(
    'inline relative sizes survive nested emphasis without changing text',
    () async {
      await source.writeAsString(
        '<style>.ref {font-size:85%;}</style>'
        '<p>Text <span class="ref">(John <em>3:16</em>)</span> after.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'inline-size',
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['inline-size'],
      )).single;
      final formatted = jsonDecode(row['formatted_content'] as String) as Map;
      final nodes = formatted['nodes'] as List;
      expect(nodes.map((n) => n['text']).join(), 'Text (John 3:16) after.');
      expect(
        nodes
            .where((n) => n['relative_font_scale'] == .85)
            .map((n) => n['text'])
            .join(),
        '(John 3:16)',
      );
      expect(nodes.first['relative_font_scale'], isNull);
      expect(nodes.last['relative_font_scale'], isNull);
    },
  );

  test(
    'marked citation keeps its whole lookup across nested emphasis',
    () async {
      await source.writeAsString(
        '<p>Read <span class="cis-inline-bible">'
        '(John <em>3:16</em>,18)</span> now.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'nested-citation',
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['nested-citation'],
      )).single;
      final nodes =
          (jsonDecode(row['formatted_content'] as String) as Map)['nodes']
              as List;
      final links = nodes
          .where((n) => n['link'] != null)
          .map((n) => n['link'])
          .toSet();
      expect(links, {
        'studybible-citation:${Uri.encodeComponent('(John 3:16,18)')}',
      });
    },
  );

  test(
    'relative note sizes remain scalable and bounded, fixed sizes ignored',
    () async {
      await source.writeAsString(
        '<p style="font-size:0.8em">Note one.</p>'
        '<p style="font-size:85%">Note two.</p>'
        '<p style="font-size:2px">Fixed print size.</p>'
        '<p style="font-size:0.1em">Tiny source size.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'note-sizes',
        source: source,
      );
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['note-sizes'],
        orderBy: 'display_order',
      );
      final scales = rows
          .map(
            (row) => LibraryFormattedContent.fromJson(
              row['formatted_content'] as String,
            ).metadata['relative_font_scale'],
          )
          .toList();
      expect(scales, [0.8, 0.85, null, 0.7]);
    },
  );

  test(
    'marked inline citation preserves prose and gets a Bible popup target',
    () async {
      await source.writeAsString(
        '<p>Before <span class="cis-inline-bible"> (John 3:16)<span id="note1"></span></span> after.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'citation-book',
        source: source,
      );
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['citation-book'],
      );
      final content = LibraryFormattedContent.fromJson(
        rows.single['formatted_content'] as String,
      );
      expect(rows.single['plain_text'], 'Before (John 3:16) after.');
      final citation = content.nodes.firstWhere(
        (n) => n['text'].toString().contains('John 3:16'),
      );
      expect(
        Uri.decodeComponent(citation['link'] as String),
        'studybible-citation:(John 3:16)',
      );
    },
  );

  test(
    'tables preserve cell text, merged headings, emphasis and anchors',
    () async {
      await source.writeAsString(
        '<h1>Chapter</h1><table id="comparison">'
        '<tr><th>Type</th><th>Antitype</th></tr>'
        '<tr><td colspan="2">One shared heading</td></tr>'
        '<tr><td id="cell-a"><p>First <em>cell</em></p><p>Second line</p></td>'
        '<td>Matching cell</td></tr></table><p>After table.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'table-book',
        source: source,
      );
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['table-book'],
        orderBy: 'display_order',
      );
      expect(rows.length, 3);
      final table = LibraryFormattedContent.fromJson(
        rows[1]['formatted_content'] as String,
      );
      final cells = table.metadata['table_rows'] as List;
      expect(cells.length, 3);
      expect(cells[1][0]['colspan'], 2);
      expect(cells[2][0]['text'], 'First cell\nSecond line');
      expect(rows[1]['plain_text'], contains('Matching cell'));
      expect(table.metadata['source_anchor_aliases'], contains('cell-a'));
      expect(
        (cells[2][0]['nodes'] as List).any(
          (n) => n['text'] == 'cell' && (n['marks'] as List).contains('italic'),
        ),
        isTrue,
      );
    },
  );

  test(
    'explicit unpaginated gap stops inherited source pages until a new marker',
    () async {
      await source.writeAsString(
        '''<p><span epub:type="pagebreak" title="6"></span>End of Preface.</p>
      <h1 data-source-page-reset="true">Contents</h1>
      <p data-refcode="DAR 7.4">Original outline.</p>
      <p>Unpaginated continuation.</p>
      <p><span epub:type="pagebreak" title="18"></span>Introduction.</p>
      <p>Continues on the known page.</p>''',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'page-gap',
        source: source,
      );
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id=?',
        whereArgs: ['page-gap'],
        orderBy: 'display_order',
      );
      Map metadata(int i) =>
          (jsonDecode(rows[i]['formatted_content'] as String)
                  as Map)['metadata']
              as Map;
      expect(rows.length, 6);
      expect(metadata(0)['source_page_end'], 6);
      for (final i in [1, 2, 3]) {
        expect(metadata(i).containsKey('source_page_start'), false);
        expect(metadata(i).containsKey('source_page_end'), false);
      }
      expect(rows[2]['source_refcode'], 'DAR 7.4');
      expect(metadata(4)['source_page_start'], 18);
      expect(metadata(5)['source_page_start'], 18);
    },
  );

  test('schema is additive and retains legacy tables', () async {
    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((row) => row['name']).toSet();
    expect(
      names,
      containsAll(<String>{
        'library_items',
        'library_text_blocks',
        'elibrary_markups',
        'library_document_conversion',
        'library_document_sections',
        'library_document_blocks',
        'library_block_source_map',
      }),
    );
  });

  test(
    'fresh EGW import stores paragraph refcodes and opens at Chapter 1',
    () async {
      final actsSource = File(p.join(directory.path, 'en_AA.html'));
      await actsSource.writeAsString('''
      <h1>The Acts of the Apostles</h1>
      <p>Copyright and publication front matter.</p>
      <h2>Chapter 1—God's Purpose for His Church</h2>
      <p>First chapter paragraph.</p>
      <p>Second paragraph before <span epub:type="pagebreak" title="10">[10]</span> the page turn.</p>
      <p>First paragraph on the next page.</p>
    ''');

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'AA',
        source: actsSource,
      );
      final repository = LibraryDocumentRepository(db);
      final opening = await repository.openingDisplayOrder(
        'AA',
        bookTitle: 'The Acts of the Apostles',
      );
      final rows = await db.query(
        'library_document_blocks',
        columns: const <String>[
          'plain_text',
          'source_refcode',
          'reference_origin',
        ],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>['AA', LibraryDocumentBlockType.paragraph.name],
        orderBy: 'display_order',
      );

      expect(opening, 2);
      expect(rows[1]['source_refcode'], 'AA 9.1');
      expect(rows[2]['source_refcode'], 'AA 9.2');
      expect(rows[3]['source_refcode'], 'AA 10.1');
      expect(rows[3]['reference_origin'], 'synthetic_epub_pagebreak');
    },
  );

  test(
    'approved Pioneer page markers synthesize stable per-page citations',
    () async {
      const itemId = 'cor-synthetic';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': itemId,
        'title': 'Christ Our Righteousness',
        'file_name': 'christ_our_righteousness.epub',
        'relative_path': 'ImportedPioneerEpubs/christ_our_righteousness.epub',
        'source_type': 'pioneer_epub_import',
        'created_at': now,
        'updated_at': now,
        'device_id': 'test',
      });
      await source.writeAsString('''
        <p>Unnumbered front matter.</p>
        <p>57</p>
        <p>First paragraph beginning on page 57.</p>
        <h2>A heading on page 57</h2>
        <img alt="A non-body image" />
        <p>Second paragraph which began on page 57.</p>
        <p>58</p>
        <p>First paragraph beginning on page 58.</p>
      ''');

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: itemId,
        source: source,
      );
      final rows = await db.query(
        'library_document_blocks',
        columns: const <String>[
          'block_type',
          'plain_text',
          'source_refcode',
          'formatted_content',
        ],
        where: 'library_item_id = ?',
        whereArgs: const <Object?>[itemId],
        orderBy: 'display_order',
      );
      final byText = <String, Map<String, Object?>>{
        for (final row in rows) row['plain_text']!.toString(): row,
      };

      expect(byText['Unnumbered front matter.']!['source_refcode'], isNull);
      expect(
        byText['First paragraph beginning on page 57.']!['source_refcode'],
        'COR 57.1',
      );
      expect(
        byText['Second paragraph which began on page 57.']!['source_refcode'],
        'COR 57.2',
      );
      expect(
        byText['First paragraph beginning on page 58.']!['source_refcode'],
        'COR 58.1',
      );
      expect(byText['A heading on page 57']!['source_refcode'], isNull);
      expect(byText['A non-body image']!['source_refcode'], isNull);
      final firstMetadata =
          jsonDecode(
                byText['First paragraph beginning on page 57.']!['formatted_content']!
                    .toString(),
              )
              as Map<String, dynamic>;
      expect(
        firstMetadata['metadata']['reference_origin'],
        'synthetic_source_page_marker',
      );
    },
  );

  test(
    'native Acts refcodes are never replaced by Pioneer synthesis',
    () async {
      const itemId = 'acts-native';
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': itemId,
        'title': 'The Acts of the Apostles',
        'file_name': 'AA.epub',
        'relative_path': 'ePubs/EGW/EGW_Books/en_AA.epub',
        'source_type': 'official_download',
        'created_at': now,
        'updated_at': now,
        'device_id': 'test',
      });
      await source.writeAsString('''
      <h2>Chapter 1</h2>
      <p data-refcode="AA 10.1">Native citation remains authoritative.</p>
    ''');

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: itemId,
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        columns: const <String>['source_refcode', 'formatted_content'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: const <Object?>[itemId, 'paragraph'],
      )).single;
      expect(row['source_refcode'], 'AA 10.1');
      expect(
        row['formatted_content'].toString(),
        isNot(contains('synthetic_source_page_marker')),
      );
    },
  );

  test('EPUB refcode spans remain toggleable metadata, not prose', () async {
    final refSource = File(p.join(directory.path, 'SL27.html'));
    await refSource.writeAsString('''
      <h2>INTRODUCTION</h2>
      <p data-refcode="SL27 iii.1">Readable paragraph.
        <span class="refcode">{SL27 iii.1}</span></p>
    ''');

    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'SL27',
      source: refSource,
    );
    final rows = await db.query(
      'library_document_blocks',
      columns: const <String>[
        'plain_text',
        'source_refcode',
        'formatted_content',
      ],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['SL27', LibraryDocumentBlockType.paragraph.name],
    );

    expect(rows, hasLength(1));
    expect(rows.single['plain_text'], 'Readable paragraph.');
    expect(rows.single['source_refcode'], 'SL27 iii.1');
    expect(
      rows.single['formatted_content'].toString(),
      isNot(contains('iii.1')),
    );
  });

  test(
    'inline styled spans preserve the Christ Our Righteousness word boundaries',
    () async {
      await source.writeAsString('''
      <p><span class="c7">&quot;By </span><span class="c8"><i>faith</i></span><span class="c7"> he [the sinner, who has so grievously wronged and offended God] can ...</span></p>
    ''');

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'COR-INLINE',
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'formatted_content'],
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['COR-INLINE'],
      )).single;
      final nodes =
          (jsonDecode(row['formatted_content']!.toString())
                  as Map<String, dynamic>)['nodes']
              as List<dynamic>;

      expect(
        row['plain_text'],
        '"By faith he [the sinner, who has so grievously wronged and offended God] can ...',
      );
      expect(nodes.map((node) => node['text']).join(), row['plain_text']);
      expect(nodes[1]['marks'], contains('italic'));
    },
  );

  test(
    'inline bold and italic spans retain one ordinary word-boundary space',
    () async {
      await source.writeAsString(
        '<p>Normal <b>bold</b> and <i>italic</i> prose.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'INLINE-MARKS',
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'formatted_content'],
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['INLINE-MARKS'],
      )).single;
      final nodes =
          (jsonDecode(row['formatted_content']!.toString())
                  as Map<String, dynamic>)['nodes']
              as List<dynamic>;

      expect(row['plain_text'], 'Normal bold and italic prose.');
      expect(
        nodes.map((node) => node['text']).join(),
        'Normal bold and italic prose.',
      );
      expect(nodes[1]['marks'], contains('bold'));
      expect(nodes[3]['marks'], contains('italic'));
    },
  );

  test(
    'inline whitespace has no true-edge padding or punctuation gap',
    () async {
      await source.writeAsString(
        '<p>  <b>Hello </b><i>,</i><span> world! </span>  </p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'INLINE-PUNCTUATION',
        source: source,
      );
      final row = (await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'formatted_content'],
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['INLINE-PUNCTUATION'],
      )).single;
      final nodes =
          (jsonDecode(row['formatted_content']!.toString())
                  as Map<String, dynamic>)['nodes']
              as List<dynamic>;

      // The plain-text path intentionally remains source-faithful; only
      // formatted inline rendering removes the meaningless punctuation gap.
      expect(row['plain_text'], 'Hello , world!');
      expect(nodes.map((node) => node['text']).join(), 'Hello, world!');
    },
  );

  test(
    'canonicalization preserves source heading text without corrections',
    () async {
      final sourceWithOriginalSpelling = File(
        p.join(directory.path, 'source-heading.xhtml'),
      );
      await sourceWithOriginalSpelling.writeAsString('''
      <h1>ARGUMET</h1>
      <p>The source edition is preserved verbatim.</p>
    ''');

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'source-preservation',
        source: sourceWithOriginalSpelling,
      );

      final headings = await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: const <Object?>['source-preservation', 'heading'],
      );
      expect(headings.single['plain_text'], 'ARGUMET');
    },
  );

  test(
    'conversion is immutable, ordered, deterministic, and idempotent',
    () async {
      final before = sha256.convert(await source.readAsBytes()).toString();
      const canonicalizer = LibraryDocumentCanonicalizer();
      final first = await canonicalizer.canonicalize(
        db: db,
        libraryItemId: 'SSP',
        source: source,
      );
      final firstRows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final second = await canonicalizer.canonicalize(
        db: db,
        libraryItemId: 'SSP',
        source: source,
      );
      final secondRows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final after = sha256.convert(await source.readAsBytes()).toString();
      expect(first.blockCount, 8);
      expect(second.skipped, isTrue);
      expect(
        secondRows.map((row) => row['id']),
        firstRows.map((row) => row['id']),
      );
      expect(
        secondRows.map((row) => row['display_order']),
        orderedEquals(List<int>.generate(8, (index) => index)),
      );
      expect(
        secondRows.where((row) => row['block_type'] == 'heading').length,
        2,
      );
      expect(after, before);
      expect(await source.readAsBytes(), fixtureBytes);
    },
  );

  test('stale canonicalizer version is safely reconverted', () async {
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    await db.update(
      'library_document_conversion',
      <String, Object?>{'canonicalizer_version': 2},
      where: 'library_item_id = ?',
      whereArgs: const <Object?>['SSP'],
    );

    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    expect(result.skipped, isFalse);
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>['SSP'],
    );
    expect(
      conversion.single['canonicalizer_version'],
      LibraryDocumentCanonicalizer.version,
    );
    expect(conversion.single['status'], 'complete');
  });

  test(
    'text correction changes content hash but keeps source-anchored IDs',
    () async {
      // A source anchor establishes paragraph identity across a text edit;
      // a bare ordinal alone cannot distinguish a correction from replacement.
      final anchored = String.fromCharCodes(fixtureBytes).replaceFirst(
        '<p>The first paragraph',
        '<p id="paragraph-one">The first paragraph',
      );
      await source.writeAsString(anchored, flush: true);
      const canonicalizer = LibraryDocumentCanonicalizer();
      await canonicalizer.canonicalize(
        db: db,
        libraryItemId: 'SSP',
        source: source,
      );
      final before = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final corrected = anchored.replaceFirst(
        'first paragraph',
        'corrected paragraph',
      );
      await source.writeAsString(corrected, flush: true);
      await canonicalizer.canonicalize(
        db: db,
        libraryItemId: 'SSP',
        source: source,
      );
      final after = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(after.map((row) => row['id']), before.map((row) => row['id']));
      expect(after[1]['content_hash'], isNot(before[1]['content_hash']));
    },
  );

  test(
    'failed conversion rolls back block rows and records failed status',
    () async {
      final canonicalizer = LibraryDocumentCanonicalizer(
        failureHook: (index) {
          if (index == 2) throw StateError('injected');
        },
      );
      await expectLater(
        canonicalizer.canonicalize(
          db: db,
          libraryItemId: 'SSP',
          source: source,
        ),
        throwsStateError,
      );
      expect(
        (await db.rawQuery(
          'SELECT COUNT(*) FROM library_document_blocks WHERE library_item_id = ?',
          <Object?>['SSP'],
        )).first.values.first,
        0,
      );
      final conversion = await db.query(
        'library_document_conversion',
        where: 'library_item_id = ?',
        whereArgs: <Object?>['SSP'],
      );
      expect(conversion.single['status'], 'failed');
    },
  );

  test('repository and bounded controller preserve global identity', () async {
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    final repository = LibraryDocumentRepository(db);
    expect(await repository.openingDisplayOrder('SSP'), 0);
    final controller = LibraryDocumentController(
      libraryItemId: 'SSP',
      repository: repository,
      windowRadius: 2,
    );
    await controller.initialize(centerOrder: 1);
    final id = controller.blockAt(1)!.id;
    await controller.ensureWindow(6);
    await controller.ensureWindow(1);
    expect(controller.blockAt(1)!.id, id);
    final locationBefore = await repository.resolveLocation('SSP', 3);
    final locationAfter = await repository.resolveLocation('SSP', 5);
    expect(locationBefore!.heading!.plainText, 'Chapter 1');
    expect(locationAfter!.heading!.plainText, 'Chapter 2');

    final sourceMap = await db.query(
      'library_block_source_map',
      where: 'library_item_id = ? AND legacy_paragraph_index IS NOT NULL',
      whereArgs: const <Object?>['SSP'],
      orderBy: 'legacy_paragraph_index DESC',
      limit: 1,
    );
    final target = LibrarySearchNavigationTarget(
      libraryItemId: 'SSP',
      textBlockId: 42,
      href: sourceMap.single['source_href']!.toString(),
      paragraphIndex: (sourceMap.single['legacy_paragraph_index'] as num)
          .toInt(),
      paragraphOnSection: (sourceMap.single['legacy_paragraph_index'] as num)
          .toInt(),
    );
    // This fixture has multiple non-heading blocks sharing one legacy
    // paragraph locator. Refuse to guess; exact canonical identity still works.
    expect(await repository.displayOrderForSearchTarget(target), isNull);
    final exactTarget = LibrarySearchNavigationTarget(
      libraryItemId: target.libraryItemId,
      textBlockId: target.textBlockId,
      href: target.href,
      paragraphIndex: target.paragraphIndex,
      canonicalBlockId: sourceMap.single['block_id']!.toString(),
    );
    final targetOrder = await repository.displayOrderForSearchTarget(
      exactTarget,
    );
    expect(targetOrder, isNotNull);
    expect(controller.blockAt(targetOrder!), isNull);
    await controller.ensureWindow(targetOrder);
    expect(controller.blockAt(targetOrder), isNotNull);
  });

  test('explicit target prefers the linked paragraph over an adjacent heading '
      'sharing its legacy paragraph index', () async {
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    final repository = LibraryDocumentRepository(db);
    final paragraph = (await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>['SSP', LibraryDocumentBlockType.paragraph.name],
      orderBy: 'display_order',
      limit: 1,
    )).single;
    final sourceMap = (await db.query(
      'library_block_source_map',
      where: 'library_item_id = ? AND block_id = ?',
      whereArgs: <Object?>['SSP', paragraph['id']],
      limit: 1,
    )).single;
    await db.insert('library_document_blocks', <String, Object?>{
      'id': 'adjacent-heading',
      'library_item_id': 'SSP',
      'section_id': paragraph['section_id'],
      'display_order': 99,
      'block_type': LibraryDocumentBlockType.heading.name,
      'plain_text': 'Adjacent heading',
      'formatted_content': LibraryFormattedContent.plain(
        'Adjacent heading',
      ).toJson(),
      'source_href': paragraph['source_href'],
      'content_hash': 'adjacent-heading-hash',
    });
    await db.insert('library_block_source_map', <String, Object?>{
      'library_item_id': 'SSP',
      'block_id': 'adjacent-heading',
      'source_href': sourceMap['source_href'],
      'legacy_paragraph_index': sourceMap['legacy_paragraph_index'],
    });

    final target = LibrarySearchNavigationTarget(
      libraryItemId: 'SSP',
      textBlockId: 42,
      href: sourceMap['source_href']!.toString(),
      paragraphIndex: (sourceMap['legacy_paragraph_index'] as num).toInt(),
      paragraphOnSection: (sourceMap['legacy_paragraph_index'] as num).toInt(),
      stableSourceReference: paragraph['plain_text']!.toString(),
    );

    expect(
      await repository.displayOrderForSearchTarget(target),
      paragraph['display_order'],
    );
  });

  test(
    'autoscroll cache remains stable through stop for the session',
    () async {
      final html = StringBuffer('<html><body><h1>Chapter 1</h1>');
      for (var index = 0; index < 420; index++) {
        html.write('<p>Paragraph $index has enough readable body text.</p>');
      }
      html.write('</body></html>');
      await source.writeAsString(html.toString(), flush: true);
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'long-book',
        source: source,
      );
      final controller = LibraryDocumentController(
        libraryItemId: 'long-book',
        repository: LibraryDocumentRepository(db),
        windowRadius: 50,
      );
      await controller.initialize(centerOrder: 100);
      expect(controller.blockAt(50), isNotNull);

      await controller.beginAutoScroll(100, direction: 1);
      expect(controller.blockAt(50), isNotNull, reason: 'retain blocks behind');
      expect(controller.blockAt(300), isNotNull, reason: 'prefetch 200 ahead');

      await controller.beginAutoScroll(170, direction: 1);
      expect(
        controller.blockAt(50),
        isNotNull,
        reason: 'do not evict in motion',
      );
      expect(controller.blockAt(370), isNotNull);

      controller.endAutoScroll(170);
      expect(
        controller.blockAt(50),
        isNotNull,
        reason: 'stopping must not mutate visible scroll geometry',
      );
      expect(controller.blockAt(170), isNotNull);
      expect(controller.blockAt(300), isNotNull);
    },
  );

  test(
    'reader session cache never collapses measured rows behind viewport',
    () async {
      final html = StringBuffer('<html><body><h1>Chapter 1</h1>');
      for (var index = 0; index < 180; index++) {
        html.write('<p>Variable-height readable paragraph $index.</p>');
      }
      html.write('</body></html>');
      await source.writeAsString(html.toString(), flush: true);
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'stable-reader',
        source: source,
      );
      final controller = LibraryDocumentController(
        libraryItemId: 'stable-reader',
        repository: LibraryDocumentRepository(db),
        windowRadius: 12,
        preserveLoadedGeometry: true,
      );

      await controller.initialize(centerOrder: 12);
      final firstMeasuredId = controller.blockAt(1)!.id;
      await controller.ensureWindow(90);

      expect(
        controller.blockAt(1)?.id,
        firstMeasuredId,
        reason:
            'an already measured row must not become a zero-height placeholder',
      );
      expect(controller.blockAt(90), isNotNull);
      controller.dispose();
    },
  );

  test('canonical ordinary opening skips front matter for Chapter 1', () async {
    await source.writeAsString('''
      <html><body>
        <h1>Preface</h1><p>Readable introductory material.</p>
        <h1>Chapter I — The Beginning</h1><p>Substantive chapter text.</p>
      </body></html>
    ''');
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'front-matter-book',
      source: source,
    );

    final repository = LibraryDocumentRepository(db);
    final order = await repository.openingDisplayOrder('front-matter-book');
    expect(order, isNotNull);
    final location = await repository.resolveLocation(
      'front-matter-book',
      order!,
    );
    expect(location!.block.plainText, 'Chapter I — The Beginning');
  });

  test(
    'explicit Chapter 1 wins over an earlier inferred poem chapter',
    () async {
      await source.writeAsString('''
        <html><body>
          <h2 class="chapterhead">The Cross of Christ</h2>
          <p class="center">Poem line before the first numbered chapter.</p>
          <h1>Chapter 1 - Light in the Darkness</h1>
          <p>The first chapter body.</p>
        </body></html>
      ''');
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'poem-before-chapter-one',
        source: source,
      );

      final repository = LibraryDocumentRepository(db);
      final order = await repository.openingDisplayOrder(
        'poem-before-chapter-one',
      );
      expect(order, isNotNull);
      final location = await repository.resolveLocation(
        'poem-before-chapter-one',
        order!,
      );
      expect(location!.block.plainText, 'Chapter 1 - Light in the Darkness');
    },
  );

  test('canonical opening uses first structural chapter when it has no '
      'chapter number', () async {
    await source.writeAsString('''
      <html><body>
        <h2>Information about this Book</h2>
        <p>Publisher metadata and licensing information for this edition.</p>
        <h2>The Sanctuary Truth</h2>
        <p>This is the first substantive chapter of the book.</p>
      </body></html>
    ''');
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'structural-chapter-book',
      source: source,
    );

    final repository = LibraryDocumentRepository(db);
    final order = await repository.openingDisplayOrder(
      'structural-chapter-book',
    );
    expect(order, isNotNull);
    final location = await repository.resolveLocation(
      'structural-chapter-book',
      order!,
    );
    expect(location!.block.plainText, 'The Sanctuary Truth');
  });

  test('canonical title-led article skips metadata section', () async {
    await source.writeAsString('''
      <html><body>
        <section><h1>Information about this Book</h1>
          <p>Publisher metadata, copyright, credits, and navigation help.</p>
        </section>
        <section><h1>The Enlargement of Our Work</h1>
          <p>This is the first substantive article and contains the actual
          reading text of the pamphlet for the reader.</p>
          <p>A second substantive paragraph confirms that this is body text.</p>
        </section>
      </body></html>
    ''');
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: 'title-led-article',
      source: source,
    );

    final repository = LibraryDocumentRepository(db);
    final order = await repository.openingDisplayOrder(
      'title-led-article',
      bookTitle: 'The Enlargement of Our Work',
    );
    expect(order, isNotNull);
    final location = await repository.resolveLocation(
      'title-led-article',
      order!,
    );
    expect(location!.block.plainText, 'The Enlargement of Our Work');
  });

  test(
    'bare numeric page-marker headings are omitted from reader content',
    () async {
      final html = '''
<!doctype html>
<html><head><title>Numeric Heading Fixture</title></head><body>
<h1>Chapter 1</h1>
<p>Real chapter body.</p>
<h1>71</h1>
<p>Body that followed a page-number heading.</p>
<h2>Chapter 71</h2>
<p>Body after a real heading that merely contains digits.</p>
<h3>71.</h3>
<p>Body after a heading with trailing punctuation.</p>
<h1>1</h1>
<p>Body after a lone single-digit heading.</p>
<ol><li>2</li><li>A legitimate descriptive list item</li></ol>
</body></html>
''';
      await source.writeAsString(html, flush: true);
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'NUM',
        source: source,
      );
      final headings = await LibraryDocumentRepository(db).loadHeadings('NUM');
      expect(headings.map((block) => block.plainText), <String>[
        'Chapter 1',
        'Chapter 71',
        '71.',
      ]);
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['NUM'],
        orderBy: 'display_order ASC',
      );
      expect(blocks.where((row) => row['plain_text'] == '71'), isEmpty);
      expect(blocks.where((row) => row['plain_text'] == '1'), isEmpty);
      // A lone list item is reader content, not evidence of a print-layout
      // page marker.
      expect(blocks.where((row) => row['plain_text'] == '2'), hasLength(1));
      expect(
        blocks.where(
          (row) => row['plain_text'] == 'A legitimate descriptive list item',
        ),
        hasLength(1),
      );
      final punctuated = blocks.firstWhere((row) => row['plain_text'] == '71.');
      expect(punctuated['block_type'], 'heading');
    },
  );

  test(
    'extracts sandwiched paragraph page markers while retaining real numbered content',
    () async {
      await source.writeAsString('''
<p>The preceding paragraph continues the reader's flow.</p>
<p>57</p>
<p>The following paragraph starts on the printed page.</p>
<h2>Genesis 1</h2>
<p class="verse">1</p>
<p>In the beginning God created the heaven and the earth.</p>
<ol><li>1</li><li>A real numbered-list entry.</li></ol>
''', flush: true);

      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'PAGE-MARKERS',
        source: source,
      );
      final blocks = await db.query(
        'library_document_blocks',
        columns: const <String>[
          'plain_text',
          'block_type',
          'formatted_content',
        ],
        where: 'library_item_id = ?',
        whereArgs: const <Object?>['PAGE-MARKERS'],
        orderBy: 'display_order ASC',
      );

      expect(blocks.where((row) => row['plain_text'] == '57'), isEmpty);
      final following = blocks.firstWhere(
        (row) =>
            row['plain_text'] ==
            'The following paragraph starts on the printed page.',
      );
      expect(
        following['formatted_content'],
        contains('"source_page_marker":"57"'),
      );

      // A Bible verse and an ordered-list numeral are real content, even
      // though both are short numeric blocks.
      expect(blocks.where((row) => row['plain_text'] == '1'), hasLength(2));
      expect(
        blocks.where((row) => row['block_type'] == 'listItem'),
        hasLength(2),
      );
    },
  );

  test('force bypasses the skip check and rebuilds in place', () async {
    const canonicalizer = LibraryDocumentCanonicalizer();
    final first = await canonicalizer.canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    expect(first.skipped, isFalse);

    final skipped = await canonicalizer.canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
    );
    expect(skipped.skipped, isTrue);

    final forced = await canonicalizer.canonicalize(
      db: db,
      libraryItemId: 'SSP',
      source: source,
      force: true,
    );
    expect(forced.skipped, isFalse);
    expect(forced.blockCount, first.blockCount);
  });

  test('block ID normalization excludes content', () {
    final first = stableLibraryDocumentBlockId(
      libraryItemId: 'SSP',
      sourceHref: r'/OEBPS\\Text/../Text/CH1.XHTML#x',
      sourceAnchor: 'p1',
      blockType: LibraryDocumentBlockType.paragraph,
      sourceBlockOrdinal: 4,
    );
    final second = stableLibraryDocumentBlockId(
      libraryItemId: 'SSP',
      sourceHref: 'oebps/text/ch1.xhtml',
      sourceAnchor: 'p1',
      blockType: LibraryDocumentBlockType.paragraph,
      sourceBlockOrdinal: 4,
    );
    expect(first, second);
  });
}
