import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/canonical_local_image.dart';
import 'package:studybible2/features/library/presentation/canonical_scroll_diagnostics.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';

const _itemId = 'library_item_research_pioneer_stephen_nelson_haskell_SSP';
const _databasePath =
    '/private/tmp/studybible2_phase2_real_ssp.kSqOUh/eLibrary_phase2_ssp.db';
const _fixtureRoot = 'test/fixtures/elibrary/real_ssp';
const _expectedHashes = <String, String>{
  'capture.html':
      'b9f2f5dfe0518d18c2eb4028009b04b55df7ba10129b3779868aca904d15c0ce',
  'manifest.json':
      '7deaadb231fcf7240866f1f79683eb3b2ac81a729bcdeacb73c5e21a834f50e9',
  'manifest.pre-schema2-repair.json':
      '554bb79c49f4ebf0633975820ddf3e96aee1e3975413f8cde13689c9c03f8663',
  'images/image_0001.png':
      '27a5e6e439094075c0eaab84ff3bb5ad7b923861f3af46b94ad3d816fa7c5154',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late File capture;
  late LibraryDocumentRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    capture = File(p.join(_fixtureRoot, 'capture.html'));
    db = await openDatabase(_databasePath);
    await ELibrarySchema.ensure(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': _itemId,
      'title': 'The Story of the Seer of Patmos',
      'author': 'Stephen N. Haskell',
      'file_name': 'capture.html',
      'relative_path': capture.path,
      'source_work_id': 'SSP',
      'source_package_id': 'captureclipper:SSP',
      'source_type': 'egw_html_capture',
      'created_at': now,
      'updated_at': now,
      'device_id': 'phase2-development-proof',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    repository = LibraryDocumentRepository(db);
  });

  tearDownAll(() async => db.close());

  test('real SSP fixture hashes are unchanged before conversion', () async {
    for (final entry in _expectedHashes.entries) {
      final actual = sha256
          .convert(await File(p.join(_fixtureRoot, entry.key)).readAsBytes())
          .toString();
      expect(actual, entry.value, reason: entry.key);
    }
  });

  test('active schema-2 manifest identifies the current SSP package', () async {
    final active =
        jsonDecode(
              await File(p.join(_fixtureRoot, 'manifest.json')).readAsString(),
            )
            as Map<String, Object?>;
    final legacy =
        jsonDecode(
              await File(
                p.join(_fixtureRoot, 'manifest.pre-schema2-repair.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(active['schemaVersion'], 2);
    expect(active['workId'], 'SSP');
    expect(active['packageId'], 'captureclipper:SSP');
    expect(active['htmlFile'], 'capture.html');
    expect(legacy['schemaVersion'], 1);
  });

  test('real SSP canonicalizes transactionally and idempotently', () async {
    const canonicalizer = LibraryDocumentCanonicalizer();
    final first = await canonicalizer.canonicalize(
      db: db,
      libraryItemId: _itemId,
      source: capture,
    );
    final before = await db.query(
      'library_document_blocks',
      columns: const <String>['id', 'content_hash'],
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[_itemId],
      orderBy: 'display_order',
    );
    final second = await canonicalizer.canonicalize(
      db: db,
      libraryItemId: _itemId,
      source: capture,
    );
    final after = await db.query(
      'library_document_blocks',
      columns: const <String>['id', 'content_hash'],
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[_itemId],
      orderBy: 'display_order',
    );
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: const <Object?>[_itemId],
    );
    expect(first.sourceHash, _expectedHashes['capture.html']);
    expect(first.blockCount, greaterThan(1000));
    expect(second.skipped, isTrue);
    expect(after, before);
    expect(conversion.single['status'], 'complete');
    expect(
      conversion.single['canonicalizer_version'],
      LibraryDocumentCanonicalizer.version,
    );
  });

  test(
    'canonical content preserves references, order, and chapter boundaries',
    () async {
      final rows = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>[_itemId],
        orderBy: 'display_order',
      );
      expect(rows, isNotEmpty);
      expect(
        rows.map((row) => row['display_order']),
        orderedEquals(List<int>.generate(rows.length, (index) => index)),
      );
      expect(rows.first['block_type'], LibraryDocumentBlockType.image.name);
      final headings = rows
          .where((row) => row['block_type'] == 'heading')
          .toList(growable: false);
      final headingTexts = headings
          .map((row) => row['plain_text']?.toString() ?? '')
          .toList(growable: false);
      expect(headingTexts.toSet().length, headingTexts.length);
      final chapterHeadings = headingTexts
          .where((text) => text.startsWith('CHAPTER '))
          .toList(growable: false);
      expect(chapterHeadings.length, greaterThanOrEqualTo(24));
      expect(chapterHeadings.first, startsWith('CHAPTER I.'));
      expect(chapterHeadings[1], startsWith('CHAPTER II.'));

      final extraction = const EgwHtmlCaptureExtractor().extract(
        await capture.readAsString(),
      );
      final refCount = rows
          .where((row) => (row['source_refcode']?.toString() ?? '').isNotEmpty)
          .length;
      expect(refCount, extraction.refCount);
      expect(refCount, 1091);
      for (final heading in headings.where(
        (row) => (row['plain_text']?.toString() ?? '').startsWith('CHAPTER '),
      )) {
        final order = (heading['display_order'] as num).toInt();
        expect(order + 1, lessThan(rows.length));
        final nextChapterOrder = headings
            .where(
              (row) =>
                  (row['plain_text']?.toString() ?? '').startsWith(
                    'CHAPTER ',
                  ) &&
                  (row['display_order'] as num).toInt() > order,
            )
            .map((row) => (row['display_order'] as num).toInt())
            .firstOrNull;
        final chapterEnd = nextChapterOrder ?? rows.length;
        final chapterBody = rows
            .skip(order + 1)
            .take(chapterEnd - order - 1)
            .where((row) => row['block_type'] == 'paragraph')
            .toList(growable: false);
        expect(chapterBody, isNotEmpty);
        expect(chapterBody.first['source_refcode'], isNotEmpty);
        expect(chapterBody.last['source_refcode'], isNotEmpty);
        if (order > 1) expect(rows[order - 1]['plain_text'], isNotEmpty);
      }
      final maps = await db.query(
        'library_block_source_map',
        where: 'library_item_id = ?',
        whereArgs: const <Object?>[_itemId],
        orderBy: 'legacy_block_index',
      );
      expect(maps.length, rows.length);
      expect(maps.every((row) => row['source_href'] == 'capture.html'), isTrue);
    },
  );

  test('local image resolver accepts only contained local assets', () {
    final root = Directory(_fixtureRoot);
    final valid = resolveCanonicalLocalImage(
      sourceRoot: root,
      source: 'images/image_0001.png',
    );
    expect(valid.status, CanonicalLocalImageStatus.resolved);
    expect(valid.file!.lengthSync(), 2669099);
    expect(
      resolveCanonicalLocalImage(
        sourceRoot: root,
        source: 'images/missing.png',
      ).status,
      CanonicalLocalImageStatus.missing,
    );
    expect(
      resolveCanonicalLocalImage(
        sourceRoot: root,
        source: '../outside.png',
      ).status,
      CanonicalLocalImageStatus.rejected,
    );
    expect(
      resolveCanonicalLocalImage(
        sourceRoot: root,
        source: 'https://example.invalid/image.png',
      ).status,
      CanonicalLocalImageStatus.rejected,
    );
  });

  testWidgets(
    'valid images render and image failures fall back without blocking scroll',
    (tester) async {
      final temp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('canonical_image_failure_'),
      );
      final tempRoot = temp!;

      Future<
        ({
          LibraryDocumentController controller,
          CallbackReaderAutoScrollTarget target,
        })
      >
      pumpForRoot(Directory root) async {
        final controller = LibraryDocumentController(
          libraryItemId: _itemId,
          repository: repository,
          windowRadius: 80,
        );
        await tester.runAsync(() => controller.initialize());
        final target = CallbackReaderAutoScrollTarget();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 260,
                child: CanonicalLibraryDocumentBody(
                  controller: controller,
                  autoScrollTarget: target,
                  onVisibleOrderChanged: (_) {},
                  textColor: Colors.black,
                  sourceRoot: root,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        return (controller: controller, target: target);
      }

      final valid = await pumpForRoot(Directory(_fixtureRoot));
      expect(
        find.byKey(const ValueKey('canonical-local-image')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      valid.controller.dispose();

      final missing = await pumpForRoot(tempRoot);
      expect(
        find.byKey(const ValueKey('canonical-image-fallback')),
        findsOneWidget,
      );
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -10),
      );
      await tester.pump();
      expect(missing.target.scrollBy(40), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      missing.controller.dispose();

      await tester.runAsync(() async {
        final images = Directory(p.join(tempRoot.path, 'images'));
        await images.create();
        await File(
          p.join(images.path, 'image_0001.png'),
        ).writeAsBytes(const <int>[]);
      });
      final corrupt = await pumpForRoot(tempRoot);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('canonical-image-fallback')),
        findsOneWidget,
      );
      expect(find.byType(ScrollablePositionedList), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      corrupt.controller.dispose();
      await tester.runAsync(() => tempRoot.delete(recursive: true));
    },
  );

  test(
    'controller extends across real chapter boundaries without changing IDs',
    () async {
      final headings = await db.query(
        'library_document_blocks',
        columns: const <String>['id', 'display_order'],
        where:
            "library_item_id = ? AND block_type = 'heading' AND plain_text LIKE 'CHAPTER %'",
        whereArgs: const <Object?>[_itemId],
        orderBy: 'display_order',
        limit: 3,
      );
      final controller = LibraryDocumentController(
        libraryItemId: _itemId,
        repository: repository,
        windowRadius: 18,
      );
      final firstOrder = (headings[0]['display_order'] as num).toInt();
      final thirdOrder = (headings[2]['display_order'] as num).toInt();
      await controller.initialize(centerOrder: firstOrder);
      final firstId = controller.blockAt(firstOrder)!.id;
      await controller.ensureWindow(thirdOrder);
      await controller.ensureWindow(firstOrder);
      expect(controller.blockAt(firstOrder)!.id, firstId);
      controller.dispose();
    },
  );

  test('diagnostics detect no forward chapter regression or recreation', () {
    final diagnostics = CanonicalScrollDiagnostics();
    for (var order = 10; order <= 40; order += 5) {
      diagnostics.record(
        CanonicalScrollDiagnosticSample(
          timestamp: DateTime.utc(2026, 7, 17),
          requestedDelta: 2,
          appliedDelta: 2,
          firstVisibleBlockId: 'block-$order',
          firstVisibleDisplayOrder: order,
          headingBlockId: order < 25 ? 'chapter-1' : 'chapter-2',
          headingTitle: order < 25 ? 'CHAPTER I.' : 'CHAPTER II.',
          direction: 'forward',
          programmaticItemJump: false,
          controllerIdentity: 17,
          chapterNavigationFired: false,
        ),
      );
    }
    expect(diagnostics.hasForwardChapterRegression, isFalse);
    expect(
      diagnostics.samples.map((sample) => sample.controllerIdentity).toSet(),
      <int>{17},
    );
    expect(
      diagnostics.samples.any((sample) => sample.chapterNavigationFired),
      isFalse,
    );
  });

  testWidgets('real SSP flat list autoscroll crosses two headings forward', (
    tester,
  ) async {
    final controller = LibraryDocumentController(
      libraryItemId: _itemId,
      repository: repository,
      windowRadius: 80,
    );
    await tester.runAsync(() => controller.initialize());
    final target = CallbackReaderAutoScrollTarget();
    final diagnostics = CanonicalScrollDiagnostics();
    final visible = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: CanonicalLibraryDocumentBody(
              controller: controller,
              autoScrollTarget: target,
              onVisibleOrderChanged: visible.add,
              textColor: Colors.black,
              sourceRoot: Directory(_fixtureRoot),
              diagnostics: diagnostics,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -10),
    );
    await tester.pump();
    final chapterOrders = (await tester.runAsync(
      () => db.query(
        'library_document_blocks',
        columns: const <String>['display_order'],
        where:
            "library_item_id = ? AND block_type = 'heading' AND plain_text LIKE 'CHAPTER %'",
        whereArgs: const <Object?>[_itemId],
        orderBy: 'display_order',
        limit: 3,
      ),
    ))!.map((row) => (row['display_order'] as num).toInt()).toList(growable: false);
    for (
      var tick = 0;
      tick < 500 && (visible.isEmpty || visible.last < chapterOrders[2]);
      tick++
    ) {
      expect(target.scrollBy(120), isTrue);
      await tester.pump(const Duration(milliseconds: 8));
      if (tick % 20 == 0) {
        await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      }
    }
    expect(visible.last, greaterThanOrEqualTo(chapterOrders[2]));
    expect(diagnostics.hasForwardChapterRegression, isFalse);
    expect(
      diagnostics.samples.every((sample) => sample.appliedDelta >= 0),
      isTrue,
    );
    expect(
      diagnostics.samples.every((sample) => !sample.programmaticItemJump),
      isTrue,
    );
    expect(
      diagnostics.samples.every((sample) => !sample.chapterNavigationFired),
      isTrue,
    );
    expect(
      diagnostics.samples
          .map((sample) => sample.controllerIdentity)
          .toSet()
          .length,
      1,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('proof harness is labeled and uses injected repository', (
    tester,
  ) async {
    final item = LibraryCatalogItem.fromRow(<String, Object?>{
      'id': _itemId,
      'title': 'The Story of the Seer of Patmos',
      'author': 'Stephen N. Haskell',
      'file_name': 'capture.html',
      'relative_path': capture.path,
      'source_type': 'egw_html_capture',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalSspProofHarness(
          item: item,
          repository: repository,
          sourceRoot: Directory(_fixtureRoot),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('CANONICAL SSP PROOF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('legacy remains default and failed conversion falls back', () {
    expect(useCanonicalLibraryReader, isFalse);
    expect(
      selectLibraryReaderImplementation(
        featureEnabled: true,
        canonicalComplete: false,
      ),
      LibraryReaderImplementation.legacy,
    );
  });

  test('real SSP fixture hashes remain unchanged after proof', () async {
    for (final entry in _expectedHashes.entries) {
      final actual = sha256
          .convert(await File(p.join(_fixtureRoot, entry.key)).readAsBytes())
          .toString();
      expect(actual, entry.value, reason: entry.key);
    }
  });
}
