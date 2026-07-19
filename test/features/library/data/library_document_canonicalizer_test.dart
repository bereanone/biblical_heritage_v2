import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
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
