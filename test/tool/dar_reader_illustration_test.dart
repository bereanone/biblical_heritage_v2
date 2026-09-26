// Actual reviewed DAR fixture, isolated from the live library.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_assets.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/canonical_reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'DAR illustration entry lands on its actual SVG-wrapped artwork',
    (tester) async {
      if (Platform.environment['RUN_DAR_READER'] != '1') return;
      final plate = Platform.environment['DAR_READER_PLATE'] ?? 'alexander';
      const targets = {
        'alexander': (
          'dar-illustration-entry-bc71368cac09e95686ec',
          'dar-image-c433e2f4f5f51beae2a4',
        ),
        'three_hebrews': (
          'dar-illustration-entry-bc0bc812940da06254de',
          'dar-image-4ff6588963075358f9a3',
        ),
        'lions_den': (
          'dar-illustration-entry-17659e5c572bfc15b173',
          'dar-illustration-daniel-in-lions-den',
        ),
      };
      final anchors = targets[plate]!;
      final output = p.absolute(
        'tool/Verification/cis_1914_restoration/output',
      );
      final report = jsonDecode(
        (await tester.runAsync(
          () => File(
            p.join(output, 'dar_single_import_audit.json'),
          ).readAsString(),
        ))!,
      );
      final root = report['root'] as String;
      final id = report['item_id'] as String;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => p.join(root, '.runtime'),
          );
      final setup = (await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        LibraryRootService.instance.invalidateCachedSelection();
        await LibraryRootService.instance.setLibraryRoot(path: root);
        final db = await ELibraryDatabase.instance.database;
        await UserDatabase.instance.database;
        final font = FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        await font.load();
        final entry = (await db.query(
          'library_document_blocks',
          where: 'library_item_id=? AND source_anchor=?',
          whereArgs: [id, anchors.$1],
        )).single;
        final target = (await db.query(
          'library_document_blocks',
          where: 'library_item_id=? AND source_anchor=?',
          whereArgs: [id, anchors.$2],
        )).single;
        final row = (await db.query(
          'library_items',
          where: 'id=?',
          whereArgs: [id],
        )).single;
        final item = LibraryCatalogItem.fromRow({
          ...row,
          'anchor_id': 'canonical:${entry['id']}',
          'last_opened': DateTime.now().toIso8601String(),
        });
        final assets = (await LibraryDocumentAssets.restore(
          db: db,
          itemId: id,
          libraryRoot: Directory(root),
        ))!;
        final node = LibraryFormattedContent.fromJson(
          target['formatted_content'] as String,
        ).nodes.single;
        final expected = await loadCanonicalReaderImage(
          File(p.join(assets.path, node['source'] as String)),
        );
        await Directory(
          p.join(output, 'reader_checks'),
        ).create(recursive: true);
        return (
          db: db,
          item: item,
          assets: assets,
          expected: expected,
          label: entry['plain_text'] as String,
        );
      }))!;
      Future<void> settle() async {
        for (var i = 0; i < 35; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      for (final width in [430.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Roboto'),
              home: CanonicalLibraryReaderScreen(
                item: setup.item,
                repository: LibraryDocumentRepository(setup.db),
                sourceRoot: setup.assets,
                macosAutoscroll: false,
              ),
            ),
          ),
        );
        await settle();
        final entry = find.byWidgetPredicate(
          (w) =>
              w is SelectableText && w.textSpan?.toPlainText() == setup.label,
        );
        expect(entry, findsOneWidget);
        final editable = tester.state<EditableTextState>(
          find.descendant(of: entry, matching: find.byType(EditableText)),
        );
        final boxes = editable.renderEditable.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 8),
        );
        await tester.tapAt(
          editable.renderEditable.localToGlobal(boxes.first.toRect().center),
        );
        await settle();
        expect(tester.takeException(), isNull);
        final expectedBytes = (setup.expected.provider as MemoryImage).bytes;
        final image = find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is MemoryImage &&
              listEquals((w.image as MemoryImage).bytes, expectedBytes),
        );
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final rendered = await boundary.toImage();
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            p.join(
              output,
              'reader_checks',
              'dar_${plate}_${width.toInt()}.png',
            ),
          ).writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
        expect(image, findsOneWidget);
        final rect = tester.getRect(image);
        expect(rect.overlaps(Rect.fromLTWH(0, 0, width, 900)), isTrue);
        expect(rect.top, greaterThanOrEqualTo(0));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(() async {
        await ELibraryDatabase.instance.close();
        await UserDatabase.instance.close();
      });
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
