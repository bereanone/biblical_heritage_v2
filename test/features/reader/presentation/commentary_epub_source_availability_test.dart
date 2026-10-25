import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/reader/presentation/commentary_research_screen.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late Directory temp;
  late File source;
  late LibraryDocumentRepository repository;
  late LibraryCatalogItem item;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ELibrarySchema.ensure(db);
    repository = LibraryDocumentRepository(db);
    temp = await Directory.systemTemp.createTemp('commentary-source-');
    source = File('${temp.path}/book.epub');
    item = LibraryCatalogItem.fromRow({
      'id': 'book',
      'title': 'Test book',
      'relative_path': 'book.epub',
      'file_format': 'epub',
    });
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<bool> readable() => commentaryEpubSourceIsReadable(
    item: item,
    source: source,
    repository: repository,
  );
  Future<void> prepared(String status, {bool withBlock = true}) async {
    await db.insert('library_document_conversion', {
      'library_item_id': 'book',
      'canonicalizer_version': 43,
      'status': status,
    });
    if (withBlock) {
      await db.insert('library_document_blocks', {
        'id': 'block',
        'library_item_id': 'book',
        'section_id': 'section',
        'display_order': 0,
        'block_type': 'paragraph',
        'plain_text': 'A complete paragraph.',
      });
    }
  }

  test('retained prepared book opens without the removed raw EPUB', () async {
    await prepared('complete');
    expect(await source.exists(), isFalse);
    expect(await readable(), isTrue);
  });
  test('missing book still reports unavailable', () async {
    expect(await readable(), isFalse);
  });
  test(
    'failed or empty preparation cannot bypass unavailable source',
    () async {
      await prepared('failed');
      expect(await readable(), isFalse);
      await db.update('library_document_conversion', {'status': 'complete'});
      await db.delete('library_document_blocks');
      expect(await readable(), isFalse);
    },
  );
  test('raw EPUB still opens before preparation', () async {
    await source.writeAsString('source witness');
    expect(await readable(), isTrue);
  });
}
