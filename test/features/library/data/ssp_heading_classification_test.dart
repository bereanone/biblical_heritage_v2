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

const _itemId = 'library_item_research_pioneer_stephen_nelson_haskell_SSP';
const _fixtureRoot = 'test/fixtures/elibrary/real_ssp';
const _hashes = <String, String>{
  'capture.html':
      'b9f2f5dfe0518d18c2eb4028009b04b55df7ba10129b3779868aca904d15c0ce',
  'manifest.json':
      '7deaadb231fcf7240866f1f79683eb3b2ac81a729bcdeacb73c5e21a834f50e9',
  'manifest.pre-schema2-repair.json':
      '554bb79c49f4ebf0633975820ddf3e96aee1e3975413f8cde13689c9c03f8663',
  'images/image_0001.png':
      '27a5e6e439094075c0eaab84ff3bb5ad7b923861f3af46b94ad3d816fa7c5154',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryRoot;
  late Database db;
  late LibraryDocumentRepository repository;
  late List<LibraryDocumentBlock> blocks;

  setUpAll(() async {
    sqfliteFfiInit();
    temporaryRoot = await Directory.systemTemp.createTemp('ssp_heading_v3_');
    db = await databaseFactoryFfi.openDatabase(
      p.join(temporaryRoot.path, 'isolated_heading_classification.db'),
    );
    await ELibrarySchema.ensure(db);
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: _itemId,
      source: File(p.join(_fixtureRoot, 'capture.html')),
    );
    repository = LibraryDocumentRepository(db);
    blocks = (await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[_itemId],
      orderBy: 'display_order',
    )).map(LibraryDocumentBlock.fromRow).toList(growable: false);
  });

  tearDownAll(() async => db.close());

  test('fixture is unchanged and conversion is isolated version 3', () async {
    for (final entry in _hashes.entries) {
      expect(
        sha256
            .convert(await File(p.join(_fixtureRoot, entry.key)).readAsBytes())
            .toString(),
        entry.value,
      );
    }
    expect(db.path, startsWith(temporaryRoot.path));
    final conversion = await db.query('library_document_conversion');
    expect(conversion.single['canonicalizer_version'], 3);
    expect(conversion.single['status'], 'complete');
  });

  test('SSP roles preserve 24 chapters and legitimate structural headings', () {
    final headings = blocks.where((block) => block.isHeading).toList();
    final chapters = headings
        .where((block) => block.headingRole == 'chapter')
        .toList();
    final frontMatter = headings
        .where((block) => block.headingRole == 'front_matter')
        .toList();
    final sections = headings
        .where((block) => block.headingRole == 'section')
        .toList();
    final minor = headings
        .where((block) => block.headingRole == 'minor')
        .toList();
    expect(headings, hasLength(34));
    expect(chapters, hasLength(24));
    expect(frontMatter, hasLength(4));
    expect(sections, hasLength(5));
    expect(minor.map((block) => block.plainText), <String>[
      'QUESTIONS FOR STUDY',
    ]);
    expect(chapters.first.plainText, startsWith('CHAPTER I.'));
    expect(chapters.last.plainText, startsWith('CHAPTER XXIV.'));
    expect(
      chapters.map((block) => block.displayOrder),
      orderedEquals(
        chapters.map((block) => block.displayOrder).toList()..sort(),
      ),
    );
    expect(
      sections.map((block) => block.plainText),
      containsAll(<String>['JOHN THE BELOVED', 'EPHESUS', 'SARDIS']),
    );
    expect(
      frontMatter.map((block) => block.plainText),
      contains('AUTHOR’S PREFACE'),
    );
  });

  test(
    'truncated repeated study labels become paragraphs without text loss',
    () async {
      const corrected = <String>[
        'CHAPTER IV. THE MESSAGE TO THE CHURCHES.—CON',
        'CHAPTER XI. THE VOICE OF THE MIGHTY ANGEL',
      ];
      for (final text in corrected) {
        final match = blocks.singleWhere((block) => block.plainText == text);
        expect(match.blockType, LibraryDocumentBlockType.paragraph);
        expect(
          match.formatted.metadata['classification_reason'],
          'non-monotonic repeated chapter label retained as text',
        );
      }
      expect(blocks, hasLength(1148));
      expect(
        blocks.fold<int>(0, (sum, block) => sum + block.plainText.length),
        573425,
      );
      expect(
        blocks.map((block) => block.displayOrder),
        orderedEquals(List<int>.generate(blocks.length, (index) => index)),
      );
      expect(
        await db.query(
          'library_block_source_map',
          where: 'library_item_id = ?',
          whereArgs: const <Object?>[_itemId],
        ),
        hasLength(1148),
      );
    },
  );

  test('primary chapter status ignores secondary and minor headings', () async {
    final john = blocks.singleWhere(
      (block) => block.plainText == 'JOHN THE BELOVED',
    );
    final location = await repository.resolveLocation(
      _itemId,
      john.displayOrder,
    );
    expect(location!.renderedHeading!.plainText, 'JOHN THE BELOVED');
    expect(location.secondaryHeading!.plainText, 'JOHN THE BELOVED');
    expect(location.heading!.plainText, startsWith('CHAPTER I.'));
    final questions = blocks.singleWhere(
      (block) => block.plainText == 'QUESTIONS FOR STUDY',
    );
    final questionsLocation = await repository.resolveLocation(
      _itemId,
      questions.displayOrder,
    );
    expect(questionsLocation!.heading!.plainText, startsWith('CHAPTER XXIV.'));
  });

  test('weak visual signals alone never create headings', () async {
    final source = File(p.join(temporaryRoot.path, 'weak-signals.html'));
    await source.writeAsString('''
      <h1>Semantic Book Title</h1>
      <p>SHORT UPPERCASE STATEMENT</p>
      <p style="text-align:center">Centered Label</p>
      <p><strong>Bold Label</strong></p>
      <p>April 24, 1905</p>
      <p>FULL-PAGE ILLUSTRATION CAPTION</p>
      <p data-refcode="SSP 1.1">SSP 1.1</p>
    ''');
    const item = 'weak_heading_signals';
    await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: item,
      source: source,
    );
    final rows = (await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[item],
      orderBy: 'display_order',
    )).map(LibraryDocumentBlock.fromRow).toList();
    expect(rows.first.headingRole, 'book_title');
    expect(rows.skip(1).every((block) => !block.isHeading), isTrue);
  });

  test('heading metadata supports a compact source inventory', () async {
    final headings = blocks.where((block) => block.isHeading).toList();
    final inventory = headings.indexed.map((entry) {
      final block = entry.$2;
      final metadata = block.formatted.metadata;
      return <String, Object?>{
        'heading_number': entry.$1 + 1,
        'display_order': block.displayOrder,
        'block_id': block.id,
        'text': block.plainText,
        'role': block.headingRole,
        'source_href': block.sourceHref,
        'source_anchor': block.sourceAnchor,
        'source_tag': metadata['source_tag'],
        'source_class': metadata['source_class'],
        'source_ordinal': metadata['source_ordinal'],
        'classification_reason': metadata['classification_reason'],
      };
    }).toList();
    const output =
        '/private/tmp/canonical_ssp_phase4_v3_heading_inventory.json';
    await File(output).writeAsString(
      const JsonEncoder.withIndent('  ').convert(inventory),
      flush: true,
    );
    expect(inventory, hasLength(34));
    expect(
      inventory.every((row) => row['classification_reason'] != null),
      isTrue,
    );
  });
}
