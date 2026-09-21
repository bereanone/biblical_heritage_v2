import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

/// Drives real narration UI on whatever platform this runs on: builds a
/// small synthetic three-paragraph "book" in an isolated sqlite database
/// (so behavior is deterministic and independent of the real eLibrary
/// contents), opens it in the production CanonicalLibraryReaderScreen, and
/// exercises play/pause, speed, and passage progression through the actual
/// widgets a user would tap — not by calling controller methods directly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Library narration: play, pause, speed, progression', (
    tester,
  ) async {
    const itemId = 'ios-narration-probe';
    final setup = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('narration_probe_');
      final db = await openDatabase(p.join(dir.path, 'library.db'));
      await ELibrarySchema.ensure(db);
      final source = File(p.join(dir.path, 'source.html'));
      await source.writeAsString('''
<h1>Narration Probe</h1>
<p>Block one is a short opening sentence for narration testing.</p>
<p>Block two follows immediately after the first block completes.</p>
<p>Block three is the final short sentence in this probe book.</p>
''');
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: itemId,
        source: source,
      );
      final logFile = File(
        '${(await getTemporaryDirectory()).path}/narration-events.log',
      );
      if (await logFile.exists()) await logFile.delete();
      return (db: db, dir: dir, logFile: logFile);
    });
    final db = setup!.db;
    final logFile = setup.logFile;

    final item = LibraryCatalogItem(
      id: itemId,
      title: 'Narration Probe',
      author: 'Test Fixture',
      fileName: '$itemId.html',
      fileHash: null,
      relativePath: 'Books/$itemId.html',
      fileFormat: 'html',
      folderType: 'research',
      libraryRole: null,
      collectionName: null,
      sourceSite: null,
      sourceUrl: null,
      sourceType: null,
      coverPath: null,
      dateAdded: DateTime.utc(2026, 9, 19),
      lastOpened: null,
      indexStatus: 'indexed',
      fileSize: null,
      mimeType: null,
      spineIndex: null,
      anchorId: null,
      epubHref: null,
      paragraphIndex: null,
      navigationCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderScreen(
          item: item,
          repository: LibraryDocumentRepository(db),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ignore: avoid_print
    print('NARRATION_UI_STAGE reader_open');
    expect(find.textContaining('Block one'), findsOneWidget);

    // Bootstrap: audio starts disabled, so a "Read aloud" button should be
    // visible and tappable (this is the only entry point on platforms with
    // no persisted audioEnabled preference, including a fresh iOS install).
    final readAloud = find.widgetWithText(TextButton, 'Read aloud');
    expect(
      readAloud,
      findsOneWidget,
      reason: 'no reachable UI control to enable narration',
    );
    await tester.tap(readAloud);
    await tester.pump();
    // ignore: avoid_print
    print('NARRATION_UI_STAGE tapped_read_aloud');

    // Give the engine real wall-clock time to init + synthesize + start
    // playback of the first block.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    // ignore: avoid_print
    print('NARRATION_UI_STAGE after_first_wait');

    final pauseIcon = find.byIcon(Icons.pause);
    final playingStarted = pauseIcon.evaluate().isNotEmpty;
    // ignore: avoid_print
    print('NARRATION_UI_RESULT playingStarted=$playingStarted');

    if (playingStarted) {
      // Test pause.
      await tester.tap(pauseIcon);
      await tester.pump(const Duration(milliseconds: 500));
      final playIconAfterPause = find.byIcon(Icons.play_arrow);
      // ignore: avoid_print
      print(
        'NARRATION_UI_RESULT pausedShowsPlayIcon=${playIconAfterPause.evaluate().isNotEmpty}',
      );

      // Test speed: drag the slider.
      final slider = find.byType(Slider);
      if (slider.evaluate().isNotEmpty) {
        await tester.drag(slider, const Offset(60, 0));
        await tester.pump();
        // ignore: avoid_print
        print('NARRATION_UI_STAGE dragged_speed_slider');
      }

      // Resume and let it run long enough to progress past block one.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // ignore: avoid_print
      print('NARRATION_UI_STAGE after_resume_wait');

      // Pronunciation editor.
      final pronunciationsButton = find.widgetWithText(
        TextButton,
        'Pronunciations',
      );
      if (pronunciationsButton.evaluate().isNotEmpty) {
        await tester.tap(pronunciationsButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        // ignore: avoid_print
        print(
          'NARRATION_UI_RESULT pronunciationDialogOpened=${find.byType(Dialog).evaluate().isNotEmpty}',
        );
        final closeButtons = find.text('Cancel');
        if (closeButtons.evaluate().isNotEmpty) {
          await tester.tap(closeButtons.first);
          await tester.pumpAndSettle();
        } else {
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        }
      }
    }

    await tester.runAsync(() async {
      if (await logFile.exists()) {
        final lines = await logFile.readAsLines();
        // ignore: avoid_print
        print('NARRATION_EVENTS_LOG_START');
        for (final line in lines) {
          // ignore: avoid_print
          print('LOG: $line');
        }
        // ignore: avoid_print
        print('NARRATION_EVENTS_LOG_END count=${lines.length}');
      } else {
        // ignore: avoid_print
        print('NARRATION_EVENTS_LOG_MISSING');
      }
    });

    await tester.runAsync(() async {
      await db.close();
    });
    // ignore: avoid_print
    print(jsonEncode({'stage': 'done'}));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
