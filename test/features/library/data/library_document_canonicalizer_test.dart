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
    'text correction changes content hash but keeps locator-based IDs',
    () async {
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
      final corrected = String.fromCharCodes(
        fixtureBytes,
      ).replaceFirst('first paragraph', 'corrected paragraph');
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
    final targetOrder = await repository.displayOrderForSearchTarget(target);
    expect(targetOrder, isNotNull);
    expect(controller.blockAt(targetOrder!), isNull);
    await controller.ensureWindow(targetOrder);
    expect(controller.blockAt(targetOrder), isNotNull);
  });

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
    'bare numeric headings become paragraphs, not Contents entries',
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
      final pageMarker = blocks.firstWhere((row) => row['plain_text'] == '71');
      expect(pageMarker['block_type'], 'paragraph');
      expect(pageMarker['formatted_content'], isNot(contains('heading_role')));
      final loneDigit = blocks.firstWhere((row) => row['plain_text'] == '1');
      expect(loneDigit['block_type'], 'paragraph');
      final punctuated = blocks.firstWhere((row) => row['plain_text'] == '71.');
      expect(punctuated['block_type'], 'heading');
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
