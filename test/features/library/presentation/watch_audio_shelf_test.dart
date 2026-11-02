import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/watch_library_catalog.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Database db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('watch-audio-shelf-');
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE library_document_blocks (id TEXT, library_item_id TEXT, display_order INTEGER, plain_text TEXT)',
    );
    await db.execute(
      'CREATE TABLE library_document_navigation (library_item_id TEXT,label TEXT,depth INTEGER,target_block_id TEXT,display_order INTEGER)',
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  LibraryCatalogItem item(String id, {String status = 'indexed'}) =>
      LibraryCatalogItem.fromRow({
        'id': id,
        'title': 'Audio $id',
        'file_hash': 'edition-$id',
        'index_status': status,
      });
  Future<void> audio(
    String id, {
    bool missing = false,
    String? requiredSource,
  }) async {
    final dir = Directory('${root.path}/elibrary_audio/manual-$id');
    await dir.create(recursive: true);
    if (!missing) await File('${dir.path}/chapter.mp3').writeAsBytes([1, 2, 3]);
    await File('${dir.path}/audio-manifest.json').writeAsString(
      jsonEncode({
        'title': 'Audio $id',
        'total_chapters': 2,
        'requires_source_sha256': requiredSource ?? 'edition-$id',
        'tracks': [
          {
            'chapter': 2,
            'title': 'Chapter 2',
            'file': 'chapter.mp3',
            'cues': [
              {
                'start_ms': 100,
                'source_cursor': '10',
                'text': 'A promised rest.',
              },
            ],
          },
        ],
      }),
    );
    await db.insert('library_document_blocks', {
      'id': 'block-$id',
      'library_item_id': id,
      'display_order': 10,
      'plain_text': 'A promised rest.',
    });
    await db.insert('library_document_navigation', {
      'library_item_id': id,
      'label': 'The Promised Rest',
      'depth': 0,
      'target_block_id': 'block-$id',
      'display_order': 0,
    });
  }

  test(
    'Watch sees only readable Top Shelf books with installed edition-matched audio',
    () async {
      for (final id in [
        'ready',
        'not-on-shelf',
        'missing',
        'wrong',
        'unreadable',
      ]) {
        await audio(
          id,
          missing: id == 'missing',
          requiredSource: id == 'wrong' ? 'different-edition' : null,
        );
      }
      final result = await WatchLibraryCatalog.buildShelf(
        docs: root,
        items: [
          item('ready'),
          item('not-on-shelf'),
          item('missing'),
          item('wrong'),
          item('no-recording'),
          item('unreadable', status: 'needs_attention'),
        ],
        ids: [
          'ready',
          'missing',
          'wrong',
          'no-recording',
          'unreadable',
          'ready',
        ],
        database: db,
        readPosition: (_) async => null,
      );
      expect(result.map((r) => r['id']), ['ready']);
      expect(
        result.single['manifest'],
        'elibrary_audio/manual-ready/audio-manifest.json',
      );
      expect((result.single['toc'] as List).single, {
        'title': 'The Promised Rest',
        'depth': 0,
        'chapter': 2,
        'paragraph': 1,
      });
    },
  );
  test(
    'audio shelf grows beyond six books and keeps shelf order and saved position',
    () async {
      final ids = List.generate(12, (i) => 'book-$i');
      for (final id in ids) {
        await audio(id);
      }
      final order = ids.reversed.toList();
      final result = await WatchLibraryCatalog.buildShelf(
        docs: root,
        items: ids.map(item).toList(),
        ids: order,
        database: db,
        readPosition: (_) async =>
            '{"chapter":2,"position_ms":4567,"include_margin_notes":true}',
      );
      expect(result.map((r) => r['id']), order);
      expect(result.first['position'], {
        'chapter': 2,
        'position_ms': 4567,
        'include_margin_notes': true,
      });
    },
  );
}
