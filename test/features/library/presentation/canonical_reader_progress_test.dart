import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('saves a stable reading position while the screen remains open', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final setup = (await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('reader_progress_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      await LibraryRootService.instance.setLibraryRoot(path: dir.path);
      final path = p.join(dir.path, 'Databases', 'eLibrary.db');
      await Directory(p.dirname(path)).create(recursive: true);
      final seed = await openDatabase(path);
      await ELibrarySchema.ensure(seed);
      await seed.close();
      final db = await ELibraryDatabase.instance.database;
      await UserDatabase.instance.database;
      await db.insert('library_items', {
        'id': 'progress',
        'title': 'Progress book',
        'author': 'Test Author',
        'file_name': 'book.html',
        'relative_path': 'book.html',
        'file_format': 'html',
        'folder_type': 'research',
        'library_role': 'research',
        'source_type': 'egw_html_capture',
        'created_at': '2026-09-09',
        'updated_at': '2026-09-09',
        'device_id': 'test',
      });
      final source = File(p.join(dir.path, 'book.html'));
      await source.writeAsString(
        '<h2>Chapter One</h2>' +
            List.generate(
              60,
              (i) =>
                  '<p>Paragraph $i. Read these words and keep your place.</p>',
            ).join(),
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'progress',
        source: source,
      );
      final item = LibraryCatalogItem.fromRow(
        (await db.query('library_items')).single,
      );
      return (dir: dir, db: db, item: item);
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderScreen(
          item: setup.item,
          repository: LibraryDocumentRepository(setup.db),
          macosAutoscroll: false,
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final list = find.byKey(const ValueKey('canonical-flat-list'));
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -450));
    await settle();
    // Query before disposal: macOS process termination does not dispose widgets.
    final row = (await tester.runAsync(
      () async => (await setup.db.query(
        'library_items',
        where: 'id=?',
        whereArgs: ['progress'],
      )).single,
    ))!;
    expect(row['paragraph_index'] as int, greaterThan(1));
    expect(row['anchor_id'], startsWith('canonical:'));
    final block = (await tester.runAsync(
      () async => (await setup.db.query(
        'library_document_blocks',
        where: 'id=?',
        whereArgs: [(row['anchor_id'] as String).substring(10)],
      )).single,
    ))!;
    expect(block['display_order'], row['paragraph_index']);
    final saved = LibraryCatalogItem.fromRow(row);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderScreen(
          item: saved,
          repository: LibraryDocumentRepository(setup.db),
          macosAutoscroll: false,
        ),
      ),
    );
    await settle();
    final text = find.text(block['plain_text'] as String);
    expect(text, findsOneWidget);
    expect(
      tester.getTopLeft(text).dy - tester.getTopLeft(list).dy,
      lessThan(35),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.runAsync(() async {
      await ELibraryDatabase.instance.close();
      await UserDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await setup.dir.delete(recursive: true);
    });
  });
}
