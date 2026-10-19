import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/library_speech_scroll_follower.dart';

void main() {
  test(
    'forward following never reverses a paragraph to the reading anchor',
    () {
      expect(
        recordedSpeechFollowDelta(
          spokenTop: 0,
          paragraphHeight: 1200,
          viewportHeight: 500,
        ),
        isNull,
      );
      expect(
        recordedSpeechFollowDelta(
          spokenTop: -5,
          paragraphHeight: 1200,
          viewportHeight: 500,
        ),
        isNull,
      );
      expect(
        recordedSpeechFollowDelta(
          spokenTop: 230,
          paragraphHeight: 250,
          viewportHeight: 500,
        ),
        isNull,
      );
      expect(
        recordedSpeechFollowDelta(
          spokenTop: 300,
          paragraphHeight: 1200,
          viewportHeight: 500,
        ),
        50,
      );
    },
  );
  testWidgets(
    'long paragraph advances without reversing and coalesces overlapping cues',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final setup = (await tester.runAsync(() async {
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('recorded_follow_');
        final db = await databaseFactoryFfi.openDatabase('${dir.path}/test.db');
        await ELibrarySchema.ensure(db);
        final file = File('${dir.path}/book.html');
        await file.writeAsString(
          '<h1>Chapter 3 Repentance</h1><p>Many ${List.filled(70, 'words remain visible during narration.').join(' ')}</p><p>Following paragraph.</p><table>${List.generate(14, (i) => '<tr><td>Row $i label</td><td>Author $i</td><td>Hebrews 8:${i + 1}</td></tr>').join()}</table><p>${List.filled(40, 'Following content provides space to center the spoken row.').join(' ')}</p><h2>He sprinkles with his blood</h2><p>The mercy-seat above.</p>',
        );
        await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'follow-book',
          source: file,
        );
        final controller = LibraryDocumentController(
          libraryItemId: 'follow-book',
          repository: LibraryDocumentRepository(db),
        );
        await controller.initialize();
        return (dir: dir, db: db, controller: controller);
      }))!;
      final follow = LibrarySpeechFollowHandle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanonicalLibraryDocumentBody(
              controller: setup.controller,
              autoScrollTarget: CallbackReaderAutoScrollTarget(),
              onVisibleOrderChanged: (_) {},
              textColor: Colors.black,
              speechFollow: follow,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText().startsWith('Many') ?? false),
      );
      double top() => tester.getTopLeft(paragraph).dy;
      final chapterTop = follow.follow(0, 0);
      await tester.pumpAndSettle();
      await chapterTop;
      final heading = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText().startsWith('Chapter 3 Repentance') ??
                false),
      );
      expect(tester.getTopLeft(heading).dy, closeTo(0, 24));
      var previous = top();
      final beginning = follow.follow(1, 0);
      await tester.pumpAndSettle();
      await beginning;
      expect(
        top(),
        closeTo(previous, 1),
        reason:
            'Keep the chapter heading visible instead of forcing the paragraph to an anchor.',
      );
      final pending = <Future<bool>>[];
      for (var i = 1; i <= 10; i++) {
        pending.add(follow.follow(1, i * .035));
        for (var f = 0; f < 6; f++) {
          await tester.pump(const Duration(milliseconds: 16));
          final current = top();
          expect(
            current,
            lessThanOrEqualTo(previous + 1),
            reason: 'Forward playback must not move text backwards.',
          );
          previous = current;
        }
      }
      await tester.pumpAndSettle();
      await Future.wait(pending);
      expect(top(), lessThan(0));
      // Center the actual wrapped line on a phone-sized viewport.
      final centered = follow.follow(1, .45);
      await tester.pumpAndSettle();
      await centered;
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: paragraph, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final sourceLength = setup.controller.blockAt(1)!.plainText.length;
      final offset = (sourceLength * .45).round();
      final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
      expect(editable.localToGlobal(caret.center).dy, closeTo(350, 24));
      final tableBlock = setup.controller.blockAt(3)!;
      final tableOffset = tableBlock.plainText.indexOf('Row 11 label');
      expect(tableOffset, greaterThan(0));
      final tableFollow = follow.follow(
        3,
        tableOffset / tableBlock.plainText.length,
      );
      await tester.pumpAndSettle();
      await tableFollow;
      final rowText = find.byWidgetPredicate(
        (w) =>
            w is SelectableText && w.textSpan?.toPlainText() == 'Row 11 label',
      );
      expect(rowText, findsOneWidget);
      final rowElement = tester.element(rowText);
      RenderBox? row;
      rowElement.visitAncestorElements((element) {
        if (element is RenderObjectElement &&
            element.renderObject is RenderFlex &&
            (element.renderObject as RenderFlex).direction == Axis.horizontal) {
          row = element.renderObject as RenderFlex;
          return false;
        }
        return true;
      });
      expect(row, isNotNull);
      expect(
        row!.localToGlobal(row!.size.center(Offset.zero)).dy,
        closeTo(350, 24),
      );
      final stanza = follow.follow(5, 0);
      await tester.pumpAndSettle();
      await stanza;
      final stanzaText = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            w.textSpan?.toPlainText() == 'He sprinkles with his blood',
      );
      expect(
        tester.getTopLeft(stanzaText).dy,
        greaterThan(80),
        reason:
            'A poem stanza heading must not jump flush to the chapter-title position.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        setup.controller.dispose();
        await setup.db.close();
        await setup.dir.delete(recursive: true);
      });
    },
  );
}
