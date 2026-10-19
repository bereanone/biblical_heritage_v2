import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

void main() {
  testWidgets(
    'single taps select words in successive paragraphs, including narration highlight',
    (tester) async {
      final setup = (await tester.runAsync(() async {
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('word_tap_');
        final db = await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
        await ELibrarySchema.ensure(db);
        final file = File('${dir.path}/book.html');
        await file.writeAsString(
          '<p>Many especially those who are young have questions.</p><p>God never asks us to believe without evidence.</p>',
        );
        await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'tap-book',
          source: file,
        );
        final controller = LibraryDocumentController(
          libraryItemId: 'tap-book',
          repository: LibraryDocumentRepository(db),
        );
        await controller.initialize();
        final rows = await db.query(
          'library_document_blocks',
          orderBy: 'display_order',
        );
        return (
          dir: dir,
          db: db,
          controller: controller,
          firstId: rows.first['id'] as String,
        );
      }))!;
      String? selected;
      final opened = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanonicalLibraryDocumentBody(
              controller: setup.controller,
              autoScrollTarget: CallbackReaderAutoScrollTarget(),
              onVisibleOrderChanged: (_) {},
              textColor: Colors.black,
              narrationBlockId: setup.firstId,
              onSelectionChanged: (block, selection) {
                if (!selection.isCollapsed) {
                  selected = block.plainText.substring(
                    selection.start,
                    selection.end,
                  );
                }
              },
              onOpenSelectionMenu: () => opened.add(selected),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapWord(String prefix, TextSelection selection) async {
        final paragraph = find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.textSpan?.toPlainText().startsWith(prefix) ?? false),
        );
        final editable = tester.state<EditableTextState>(
          find.descendant(of: paragraph, matching: find.byType(EditableText)),
        );
        final boxes = editable.renderEditable.getBoxesForSelection(selection);
        await tester.tapAt(
          editable.renderEditable.localToGlobal(boxes.first.toRect().center),
        );
        await tester.pumpAndSettle();
      }

      await tapWord(
        'Many',
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(opened, ['Many']);
      await tapWord('God', const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(opened, ['Many', 'God']);
      await tapWord(
        'Many',
        const TextSelection(baseOffset: 5, extentOffset: 15),
      );
      expect(opened, ['Many', 'God', 'especially']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        setup.controller.dispose();
        await setup.db.close();
        await setup.dir.delete(recursive: true);
      });
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
