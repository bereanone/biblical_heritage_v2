import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/theme/app_theme.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LibraryDocumentBlock block({
    String text = 'Visible heading',
    String? sourceRefcode = 'SSP 1.2',
    LibraryDocumentBlockType blockType = LibraryDocumentBlockType.paragraph,
  }) => LibraryDocumentBlock(
    id: 'stable-block',
    libraryItemId: 'item',
    sectionId: 'section',
    displayOrder: 3,
    blockType: blockType,
    plainText: text,
    formattedContent: LibraryFormattedContent.plain(text).toJson(),
    sourceRefcode: sourceRefcode,
    sourceHref: 'capture.html',
    contentHash: 'hash',
  );

  group('inline canonical reference codes', () {
    const bodyStyle = TextStyle(fontSize: 18, color: Colors.black);
    const referenceStyle = TextStyle(
      fontSize: 12.96,
      color: Color(0xA6000000),
      fontWeight: FontWeight.w500,
    );

    List<InlineSpan> spansFor(
      LibraryDocumentBlock sourceBlock, {
      bool visible = true,
    }) => canonicalInlineTextSpans(
      block: sourceBlock,
      formatted: LibraryFormattedContent.fromJson(sourceBlock.formattedContent),
      bodyStyle: bodyStyle,
      referenceStyle: referenceStyle,
      showReferenceCode: visible,
    );

    String plainText(List<InlineSpan> spans) =>
        TextSpan(children: spans).toPlainText();

    test('appends the code inline after one normal space', () {
      final sourceBlock = block(
        text: 'The Saviour revealed the truth in Revelation.',
        sourceRefcode: 'SSP 14.1',
      );

      final rendered = plainText(spansFor(sourceBlock));

      expect(
        rendered,
        'The Saviour revealed the truth in Revelation. SSP 14.1',
      );
      expect(rendered, isNot(contains('\nSSP 14.1')));
      expect(sourceBlock.plainText, endsWith('Revelation.'));
      expect(sourceBlock.id, 'stable-block');
    });

    test('hiding codes removes only the appended presentation span', () {
      final sourceBlock = block(text: 'Body text.', sourceRefcode: 'SSP 14.1');

      expect(plainText(spansFor(sourceBlock, visible: false)), 'Body text.');
      expect(sourceBlock.sourceRefcode, 'SSP 14.1');
      expect(sourceBlock.plainText, 'Body text.');
    });

    test('does not duplicate a code already present in source text', () {
      final sourceBlock = block(
        text: 'Body text. SSP 14.1',
        sourceRefcode: 'SSP 14.1',
      );

      expect(plainText(spansFor(sourceBlock)), 'Body text. SSP 14.1');
    });

    test('does not append codes to headings, images, or rules', () {
      for (final type in <LibraryDocumentBlockType>[
        LibraryDocumentBlockType.heading,
        LibraryDocumentBlockType.image,
        LibraryDocumentBlockType.horizontalRule,
      ]) {
        final sourceBlock = block(
          text: 'Non-paragraph content',
          sourceRefcode: 'SSP 14.1',
          blockType: type,
        );
        expect(plainText(spansFor(sourceBlock)), 'Non-paragraph content');
      }
    });

    test('uses the supplied subdued, smaller reference style', () {
      final spans = spansFor(
        block(text: 'Body text.', sourceRefcode: 'SSP 14.1'),
      );
      final reference = spans.last as TextSpan;

      expect(reference.text, ' SSP 14.1');
      expect(reference.style?.fontSize, lessThan(bodyStyle.fontSize!));
      expect(reference.style?.color?.a, lessThan(bodyStyle.color!.a));
      expect(reference.style?.fontWeight, FontWeight.w500);
    });
  });

  test('production subtitle hides acquisition provenance without mutation', () {
    for (final provenance in <String>[
      'capture',
      'capturedHtml',
      'CaptureClipper',
      'Imported HTML',
    ]) {
      final sourceBlock = block();
      final location = LibraryDocumentLocation(
        block: sourceBlock,
        sectionTitle: provenance,
        heading: null,
      );
      expect(canonicalVisibleReaderSubtitle(location), isNull);
      expect(sourceBlock.sourceHref, 'capture.html');
      expect(sourceBlock.sourceRefcode, 'SSP 1.2');
    }
    expect(
      canonicalVisibleReaderSubtitle(
        LibraryDocumentLocation(
          block: block(),
          sectionTitle: 'Second Edition',
          heading: null,
        ),
      ),
      'Second Edition',
    );
  });

  test('canonical palette follows established sepia and night themes', () {
    final sepiaTheme = buildAppTheme(AppThemeMode.sepia);
    final sepia = canonicalReaderPalette(sepiaTheme, AppThemeMode.sepia);
    expect(sepia.background, sepiaTheme.scaffoldBackgroundColor);
    expect(sepia.foreground, sepiaTheme.colorScheme.onSurface);

    final night = canonicalReaderPalette(
      buildAppTheme(AppThemeMode.night),
      AppThemeMode.night,
    );
    expect(night.background, const Color(0xFF0B0D11));
    expect(night.foreground, const Color(0xFFF7F1E5));
  });

  test(
    'feature selection defaults to legacy and falls back when unavailable',
    () {
      expect(useCanonicalLibraryReader, isFalse);
      expect(useCanonicalCaptureClipperReader, isFalse);
      expect(
        selectLibraryReaderImplementation(
          featureEnabled: false,
          canonicalComplete: true,
        ),
        LibraryReaderImplementation.legacy,
      );
      expect(
        selectLibraryReaderImplementation(
          featureEnabled: true,
          canonicalComplete: false,
        ),
        LibraryReaderImplementation.legacy,
      );
      expect(
        selectLibraryReaderImplementation(
          featureEnabled: true,
          canonicalComplete: true,
        ),
        LibraryReaderImplementation.canonical,
      );
    },
  );

  test('rollout supports CaptureClipper HTML and excludes EPUB', () {
    expect(
      supportsCanonicalCaptureClipperReader(
        _item(fileFormat: 'html', sourceType: 'egw_html_capture'),
      ),
      isTrue,
    );
    expect(
      supportsCanonicalCaptureClipperReader(
        _item(fileFormat: 'epub', sourceType: 'epub'),
      ),
      isFalse,
    );
    expect(
      supportsCanonicalCaptureClipperReader(
        _item(fileFormat: 'html', sourceType: 'user_added'),
      ),
      isFalse,
    );
  });

  test(
    'Mac keyboard autoscroll is platform scoped and leaves iOS path alone',
    () {
      expect(
        shouldUseMacReaderAutoscroll(isMacOS: true, isProofHarness: false),
        isTrue,
      );
      expect(
        shouldUseMacReaderAutoscroll(isMacOS: false, isProofHarness: false),
        isFalse,
      );
      expect(
        shouldUseMacReaderAutoscroll(isMacOS: true, isProofHarness: true),
        isFalse,
      );
    },
  );

  testWidgets('failed lazy preparation falls back to the legacy reader', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderGate(
          item: _item(fileFormat: 'html', sourceType: 'egw_html_capture'),
          prepare: (_) async {
            attempts++;
            throw StateError('injected conversion failure');
          },
          legacyBuilder: (_) =>
              const SizedBox(key: ValueKey('legacy-reader-fallback')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(
      find.byKey(const ValueKey('legacy-reader-fallback')),
      findsOneWidget,
    );
    expect(find.byType(CanonicalLibraryReaderScreen), findsNothing);
  });

  testWidgets(
    'flat native list crosses heading boundary with one scroll target',
    (tester) async {
      final setup = await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp('canonical_widget_');
        final db = await openDatabase(p.join(dir.path, 'test.db'));
        await ELibrarySchema.ensure(db);
        final source = File(p.join(dir.path, 'ssp.html'));
        await source.writeAsBytes(
          await File(
            'test/fixtures/elibrary/ssp_canonical_poc.html',
          ).readAsBytes(),
        );
        await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: 'item',
          source: source,
        );
        final controller = LibraryDocumentController(
          libraryItemId: 'item',
          repository: LibraryDocumentRepository(db),
        );
        await controller.initialize();
        return (controller: controller, db: db, dir: dir);
      });
      final completedSetup = setup!;
      final controller = completedSetup.controller;
      final target = CallbackReaderAutoScrollTarget();
      final visible = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 220,
              child: CanonicalLibraryDocumentBody(
                controller: controller,
                autoScrollTarget: target,
                onVisibleOrderChanged: visible.add,
                textColor: Colors.black,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      expect(target.isAttached, isTrue);
      expect(find.text('Chapter 1'), findsOneWidget);
      // The autoscroll target must own the visible position immediately; a
      // user drag must not be required to initialize that connection.
      final scrollableFinder = find.descendant(
        of: find.byKey(const ValueKey('canonical-flat-list')),
        matching: find.byType(Scrollable),
      );
      final visiblePosition = tester
          .state<ScrollableState>(scrollableFinder.first)
          .position;
      final mac = MacReaderAutoScrollController(
        scrollTarget: target,
        driveFrames: false,
      );
      addTearDown(mac.dispose);
      final initialOffset = visiblePosition.pixels;
      mac.setSignedStep(1);
      mac.tick(const Duration(seconds: 1));
      await tester.pump();
      final slowOffset = visiblePosition.pixels;
      expect(slowOffset, greaterThan(initialOffset));
      mac.setSignedStep(20);
      mac.tick(const Duration(milliseconds: 100));
      await tester.pump();
      final fastOffset = visiblePosition.pixels;
      expect(fastOffset - slowOffset, greaterThan(slowOffset - initialOffset));
      mac.setSignedStep(-1);
      mac.tick(const Duration(milliseconds: 500));
      await tester.pump();
      expect(visiblePosition.pixels, lessThan(fastOffset));
      expect(
        identical(
          visiblePosition,
          tester.state<ScrollableState>(scrollableFinder.first).position,
        ),
        isTrue,
      );
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -20),
      );
      await tester.pump();
      expect(target.scrollBy(260), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(visible.any((order) => order >= 4), isTrue);
      expect(controller.blockAt(0)!.plainText, 'Chapter 1');
      expect(controller.blockAt(4)!.plainText, 'Chapter 2');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await completedSetup.db.close();
        await completedSetup.dir.delete(recursive: true);
      });
    },
  );
}

LibraryCatalogItem _item({
  required String fileFormat,
  required String sourceType,
}) => LibraryCatalogItem(
  id: 'item',
  title: 'Test Book',
  author: 'Test Author',
  fileName: fileFormat == 'epub' ? 'book.epub' : 'capture.html',
  fileHash: null,
  relativePath: fileFormat == 'epub'
      ? 'ePubs/book.epub'
      : 'TextCaptures/book/capture.html',
  fileFormat: fileFormat,
  folderType: 'Research',
  libraryRole: 'book',
  collectionName: 'Pioneer Authors',
  sourceSite: null,
  sourceUrl: null,
  sourceType: sourceType,
  coverPath: null,
  dateAdded: null,
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
