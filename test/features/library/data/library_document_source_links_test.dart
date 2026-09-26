import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory directory;
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('source_links_');
    db = await databaseFactoryFfi.openDatabase('${directory.path}/test.db');
    await ELibrarySchema.ensure(db);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> block(
    String id,
    String item,
    String href,
    String? anchor,
    int order, {
    List<String> aliases = const [],
  }) async {
    final section = '$item-section';
    await db.insert('library_document_sections', {
      'id': section,
      'library_item_id': item,
      'display_order': 0,
      'title': 'Chapter',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('library_document_blocks', {
      'id': id,
      'library_item_id': item,
      'section_id': section,
      'display_order': order,
      'block_type': 'paragraph',
      'plain_text': 'Text for $id',
      'source_href': href,
      'source_anchor': anchor,
      'content_hash': id,
      'formatted_content': LibraryFormattedContent(
        nodes: [
          {'type': 'text', 'text': 'Text for $id'},
        ],
        metadata: {'source_anchor_aliases': aliases},
      ).toJson(),
    });
  }

  test(
    'source links resolve within the exact work, relative file and case-sensitive anchor',
    () async {
      await block(
        'wanted',
        'smith',
        'oebps/body.xhtml',
        'Page20',
        7,
        aliases: ['page-21', 'note 1'],
      );
      await block('another-file', 'smith', 'oebps/other.xhtml', 'Page20', 8);
      await block('another-author', 'jones', 'oebps/body.xhtml', 'Page20', 9);
      final repo = LibraryDocumentRepository(db);
      for (final href in [
        '../body.xhtml#Page20',
        '../body.xhtml#page-21',
        '../body.xhtml#note%201',
      ]) {
        expect(
          (await repo.resolveSourceLink(
            'smith',
            fromHref: 'oebps/index/authors.xhtml',
            href: href,
          ))?.id,
          'wanted',
        );
      }
      expect(
        (await repo.resolveSourceLink(
          'jones',
          fromHref: 'oebps/index.xhtml',
          href: 'body.xhtml#Page20',
        ))?.id,
        'another-author',
      );
      expect(
        await repo.resolveSourceLink(
          'smith',
          fromHref: 'oebps/index.xhtml',
          href: 'body.xhtml#page20',
        ),
        isNull,
      );
      expect(
        (await repo.resolveSourceLink(
          'smith',
          fromHref: 'oebps/body.xhtml',
          href: '#Page20',
        ))?.id,
        'wanted',
      );
      expect(
        (await repo.resolveSourceLink(
          'smith',
          fromHref: 'oebps/index.xhtml',
          href: 'body.xhtml',
        ))?.id,
        'wanted',
      );
      expect(
        await repo.resolveSourceLink(
          'missing-work',
          fromHref: 'oebps/index.xhtml',
          href: 'body.xhtml#Page20',
        ),
        isNull,
      );
    },
  );
  test(
    'ambiguous, malformed, remote and archive-escaping links do not choose a destination',
    () async {
      await block('a', 'smith', 'oebps/body.xhtml', 'duplicate', 1);
      await block(
        'b',
        'smith',
        'oebps/body.xhtml',
        'other',
        2,
        aliases: ['duplicate'],
      );
      final repo = LibraryDocumentRepository(db);
      for (final href in [
        'body.xhtml#duplicate',
        'body.xhtml#missing',
        'https://example.com/body.xhtml#duplicate',
        'file:///body.xhtml#duplicate',
        '//example.com/body.xhtml#duplicate',
        '../../body.xhtml#duplicate',
        'body.xhtml#bad%zz',
      ]) {
        expect(
          await repo.resolveSourceLink(
            'smith',
            fromHref: 'oebps/index.xhtml',
            href: href,
          ),
          isNull,
          reason: href,
        );
      }
    },
  );
}
