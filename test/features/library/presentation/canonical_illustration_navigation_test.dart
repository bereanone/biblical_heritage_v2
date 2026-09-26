import 'dart:ui' as ui;
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
  testWidgets(
    'a highlighted illustration entry opens its exact distant image and preserves its annotation',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final setup = (await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp(
          'reader_source_link_',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => dir.path);
        await LibraryRootService.instance.setLibraryRoot(path: dir.path);
        final dbPath = p.join(dir.path, 'Databases/eLibrary.db');
        await Directory(p.dirname(dbPath)).create(recursive: true);
        final seed = await openDatabase(dbPath);
        await ELibrarySchema.ensure(seed);
        await seed.close();
        final db = await ELibraryDatabase.instance.database;
        await UserDatabase.instance.database;
        await db.insert('library_items', {
          'id': 'links',
          'title': 'Linked reading',
          'author': 'Source Author',
          'file_name': 'book.html',
          'relative_path': 'book.html',
          'file_format': 'html',
          'folder_type': 'research',
          'library_role': 'research',
          'source_type': 'egw_html_capture',
          'created_at': 'test',
          'updated_at': 'test',
          'device_id': 'test',
        });
        final source = File(p.join(dir.path, 'book.html'));
        await source.writeAsString(
          '<h2>Illustrations</h2><p id="index-entry"><a href="#plate">Daniel in the lions den — DAR 109</a></p>' +
              List.generate(
                80,
                (i) =>
                    '<p>Intervening paragraph $i with enough words to fill the reading view.</p>',
              ).join() +
              '<img id="plate" src="plate.png" alt="Daniel in the lions den" data-image-rotation="270"/>' +
              List.generate(
                20,
                (i) =>
                    '<p>Following paragraph $i provides room below the destination.</p>',
              ).join(),
        );
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 800, 1600),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final pixels = await picture.toImage(800, 1600);
        final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
        await File(
          p.join(dir.path, 'plate.png'),
        ).writeAsBytes(bytes!.buffer.asUint8List());
        pixels.dispose();
        picture.dispose();
        await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'links',
          source: source,
        );
        final index = (await db.query(
          'library_document_blocks',
          where: "source_anchor='index-entry'",
        )).single;
        final target = (await db.query(
          'library_document_blocks',
          where: "source_anchor='plate'",
        )).single;
        await db.update(
          'library_items',
          {'anchor_id': 'canonical:${index['id']}'},
          where: 'id=?',
          whereArgs: ['links'],
        );
        await db.insert('elibrary_markups', {
          'library_item_id': 'links',
          'epub_href': 'canonical:${index['id']}',
          'start_block_index': 0,
          'end_block_index': 0,
          'start_char_offset': 0,
          'end_char_offset': 6,
          'selected_text_snapshot': 'Daniel',
          'markup_type': 'highlight',
          'color': '#00FF00',
          'created_at': 'test',
          'updated_at': 'test',
        });
        final item = LibraryCatalogItem.fromRow(
          (await db.query('library_items')).single,
        );
        return (
          dir: dir,
          db: db,
          item: item,
          index: index,
          target: target,
          markups: await db.query('elibrary_markups'),
        );
      }))!;
      Future<void> settle() async {
        for (var i = 0; i < 28; i++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CanonicalLibraryReaderScreen(
            item: setup.item,
            sourceRoot: setup.dir,
            repository: LibraryDocumentRepository(setup.db),
            macosAutoscroll: false,
            highlightTerms: const ['Daniel'],
          ),
        ),
      );
      await settle();
      final paragraph = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            w.textSpan?.toPlainText() == 'Daniel in the lions den — DAR 109',
      );
      expect(paragraph, findsOneWidget);
      final editable = tester.state<EditableTextState>(
        find.descendant(of: paragraph, matching: find.byType(EditableText)),
      );
      final boxes = editable.renderEditable.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(boxes, isNotEmpty);
      await tester.tapAt(
        editable.renderEditable.localToGlobal(boxes.first.toRect().center),
      );
      await settle();
      expect(
        find.byKey(const ValueKey('canonical-local-image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('canonical-image-fallback')),
        findsNothing,
      );
      final rotated = tester.widget<RotatedBox>(
        find.byKey(const ValueKey('canonical-image-orientation')),
      );
      expect(rotated.quarterTurns, 3);
      final saved = (await tester.runAsync(
        () async => (await setup.db.query('library_items')).single,
      ))!;
      expect(saved['anchor_id'], 'canonical:${setup.target['id']}');
      expect(
        await tester.runAsync(() => setup.db.query('elibrary_markups')),
        setup.markups,
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
    },
  );
}
