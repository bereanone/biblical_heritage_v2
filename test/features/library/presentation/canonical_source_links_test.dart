import 'package:flutter/foundation.dart';
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
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

void main() {
  // This fixture owns its complete catalog. Mobile provisioning adds shipped
  // books automatically and is verified in the dedicated delivery tests.

  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'a highlighted index link reaches the exact distant paragraph and keeps its stored markup',
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
          '<h2>Index</h2><p id="index-entry">See page <a href="#Page421">421</a>.</p>' +
              List.generate(
                80,
                (i) =>
                    '<p>Intervening paragraph $i with enough words to fill the reading view.</p>',
              ).join() +
              '<p id="target" data-refcode="TEST 421.1">The <span id="Page421"></span>destination paragraph is here.</p>' +
              List.generate(
                20,
                (i) =>
                    '<p>Following paragraph $i provides room below the destination.</p>',
              ).join(),
        );
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
          where: "source_anchor='target'",
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
          'start_char_offset': 9,
          'end_char_offset': 12,
          'selected_text_snapshot': '421',
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
            repository: LibraryDocumentRepository(setup.db),
            macosAutoscroll: false,
            highlightTerms: const ['421'],
          ),
        ),
      );
      await settle();
      final paragraph = find.byWidgetPredicate(
        (w) =>
            w is SelectableText && w.textSpan?.toPlainText() == 'See page 421.',
      );
      expect(paragraph, findsOneWidget);
      final editable = tester.state<EditableTextState>(
        find.descendant(of: paragraph, matching: find.byType(EditableText)),
      );
      final boxes = editable.renderEditable.getBoxesForSelection(
        const TextSelection(baseOffset: 9, extentOffset: 12),
      );
      expect(boxes, isNotEmpty);
      await tester.tapAt(
        editable.renderEditable.localToGlobal(boxes.first.toRect().center),
      );
      await settle();
      expect(find.text('The destination paragraph is here.'), findsOneWidget);
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
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
  testWidgets('long-press selection on linked text does not navigate', (
    tester,
  ) async {
    final setup = (await tester.runAsync(() async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('select_link_');
      final db = await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
      await ELibrarySchema.ensure(db);
      final file = File('${dir.path}/book.html');
      await file.writeAsString(
        '<p>Read the linked page <a href="#destination">421</a> without losing selection.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'select-link',
        source: file,
      );
      final controller = LibraryDocumentController(
        libraryItemId: 'select-link',
        repository: LibraryDocumentRepository(db),
      );
      await controller.initialize();
      return (dir: dir, db: db, controller: controller);
    }))!;
    final followed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanonicalLibraryDocumentBody(
            controller: setup.controller,
            autoScrollTarget: CallbackReaderAutoScrollTarget(),
            onVisibleOrderChanged: (_) {},
            textColor: Colors.black,
            onFollowLink: (_, href) => followed.add(href),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final boxes = editable.renderEditable.getBoxesForSelection(
      const TextSelection(baseOffset: 21, extentOffset: 24),
    );
    final point = editable.renderEditable.localToGlobal(
      boxes.first.toRect().center,
    );
    await tester.longPressAt(point);
    await tester.pumpAndSettle();
    expect(editable.renderEditable.selection?.isCollapsed, false);
    expect(followed, isEmpty);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(
      followed,
      isEmpty,
      reason: 'An active selected range must retain the annotation interaction',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      setup.controller.dispose();
      await setup.db.close();
      await setup.dir.delete(recursive: true);
    });
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
}
