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
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
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

  group('canonical Contents hierarchy', () {
    LibraryDocumentBlock heading(
      String id,
      String text,
      String href, {
      String role = 'chapter',
    }) => LibraryDocumentBlock(
      id: id,
      libraryItemId: 'item',
      sectionId: 'section',
      displayOrder: 1,
      blockType: LibraryDocumentBlockType.heading,
      plainText: text,
      formattedContent: LibraryFormattedContent(
        nodes: <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        metadata: <String, Object?>{'heading_role': role},
      ).toJson(),
      sourceHref: href,
      contentHash: 'hash-$id',
    );

    LibraryCatalogNavigationItem nav(
      String id,
      String label,
      String href, {
      String? parentId,
      int depth = 0,
      String? contentKind,
    }) => LibraryCatalogNavigationItem(
      id: id,
      parentId: parentId,
      label: label,
      href: href,
      anchorId: null,
      spineIndex: null,
      sortOrder: depth,
      depth: depth,
      navType: null,
      contentKind: contentKind,
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: null,
    );

    test('uses the EPUB navigation tree to group cross-file chapters', () {
      final depths = canonicalContentsHeadingDepths(
        headings: <LibraryDocumentBlock>[
          heading('section', 'Experience and Views', 'section.xhtml'),
          heading('chapter', 'My First Vision', 'vision.xhtml'),
          heading(
            'subheading',
            'Texts Referred to on Preceding Page',
            'vision.xhtml',
            role: 'section',
          ),
        ],
        navigationItems: <LibraryCatalogNavigationItem>[
          nav('section-nav', 'Experience and Views', 'section.xhtml'),
          nav(
            'chapter-nav',
            'My First Vision',
            'vision.xhtml#start',
            parentId: 'section-nav',
            depth: 1,
          ),
        ],
      );

      expect(depths, <String, int>{
        'section': 0,
        'chapter': 1,
        'subheading': 2,
      });
    });

    test('falls back to heading roles when navigation rows are absent', () {
      final depths = canonicalContentsHeadingDepths(
        headings: <LibraryDocumentBlock>[
          heading('chapter', 'Chapter', 'chapter.xhtml'),
          heading('section', 'Section', 'chapter.xhtml', role: 'section'),
          heading('minor', 'Minor', 'chapter.xhtml', role: 'minor'),
        ],
        navigationItems: const <LibraryCatalogNavigationItem>[],
      );

      expect(depths, <String, int>{'chapter': 0, 'section': 1, 'minor': 2});
    });

    test('ignores support rows and can fall back to normalized labels', () {
      final depths = canonicalContentsHeadingDepths(
        headings: <LibraryDocumentBlock>[
          heading('chapter', 'My First Vision!', 'synthetic/vision.xhtml'),
        ],
        navigationItems: <LibraryCatalogNavigationItem>[
          nav('about', 'About', 'about.xhtml', contentKind: 'about'),
          nav(
            'chapter-nav',
            'My First Vision',
            'actual/vision.xhtml',
            parentId: 'about',
            depth: 1,
          ),
        ],
      );

      expect(depths['chapter'], 0);
    });
  });

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

  test('legacy rollout flags no longer control production routing', () {
    expect(useCanonicalLibraryReader, isFalse);
    expect(useCanonicalCaptureClipperReader, isFalse);
    expect(
      shouldAttemptCanonicalDocumentReader(
        item: _item(fileFormat: 'html', sourceType: 'egw_html_capture'),
      ),
      isTrue,
    );
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
  });

  test('capability routing supports CaptureClipper and managed EPUBs', () {
    final ssp = _item(fileFormat: 'html', sourceType: 'egw_html_capture');
    final managedEpub = _item(
      fileFormat: 'epub',
      sourceType: 'official_download',
      relativePath: 'ePubs/EGW/EGW_Books/book.epub',
      collectionName: 'EGW Books',
    );
    expect(LibraryBookReaderScreen(item: ssp).enableCanonicalReader, isTrue);
    expect(
      LibraryBookReaderScreen(item: managedEpub).enableCanonicalReader,
      isTrue,
    );
    expect(shouldAttemptCanonicalDocumentReader(item: ssp), isTrue);
    expect(shouldAttemptCanonicalDocumentReader(item: managedEpub), isTrue);
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
    expect(shouldAttemptCanonicalDocumentReader(item: managedEpub), isTrue);
    expect(
      shouldAttemptCanonicalDocumentReader(
        item: _item(fileFormat: 'html', sourceType: 'user_added'),
      ),
      isFalse,
    );
  });

  test(
    'steady autoscroll covers Android and Mac while leaving iOS tilt alone',
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
      expect(
        shouldUseSteadyReaderAutoscroll(isIOS: false, isProofHarness: false),
        isTrue,
      );
      expect(
        shouldUseSteadyReaderAutoscroll(
          isIOS: false,
          isAndroid: true,
          isProofHarness: false,
        ),
        isFalse,
      );
      expect(
        shouldUseSteadyReaderAutoscroll(isIOS: true, isProofHarness: false),
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
      final steady = MacReaderAutoScrollController(
        scrollTarget: target,
        driveFrames: false,
      );
      addTearDown(steady.dispose);
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
                onManualScroll: steady.stopForManualInteraction,
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
      final initialOffset = visiblePosition.pixels;
      steady.setSignedStep(1);
      steady.tick(const Duration(seconds: 1));
      await tester.pump();
      final slowOffset = visiblePosition.pixels;
      expect(slowOffset, greaterThan(initialOffset));
      steady.setSignedStep(20);
      steady.tick(const Duration(milliseconds: 100));
      await tester.pump();
      final fastOffset = visiblePosition.pixels;
      expect(fastOffset - slowOffset, greaterThan(slowOffset - initialOffset));
      steady.setSignedStep(-1);
      steady.tick(const Duration(milliseconds: 500));
      await tester.pump();
      expect(visiblePosition.pixels, lessThan(fastOffset));
      steady.setSignedStep(0);
      final stoppedOffset = visiblePosition.pixels;
      steady.tick(const Duration(seconds: 2));
      await tester.pump();
      expect(visiblePosition.pixels, stoppedOffset);
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
      expect(steady.isActive, isFalse);
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

  testWidgets('explicit search target scrolls to its exact canonical block', (
    tester,
  ) async {
    final setup = await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp(
        'canonical_search_target_',
      );
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
    var positioned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: CanonicalLibraryDocumentBody(
              controller: completedSetup.controller,
              autoScrollTarget: CallbackReaderAutoScrollTarget(),
              onVisibleOrderChanged: (_) {},
              textColor: Colors.black,
              onManualScroll: () {},
              initialScrollOrder: 4,
              onInitialScrollCompleted: () => positioned = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(positioned, isTrue);
    expect(find.text('Chapter 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await completedSetup.db.close();
      await completedSetup.dir.delete(recursive: true);
    });
  });

  group('canonicalContentsCurrentHeading', () {
    LibraryDocumentBlock headingAt(int order, String text) =>
        LibraryDocumentBlock(
          id: 'heading-$order',
          libraryItemId: 'item',
          sectionId: 'section',
          displayOrder: order,
          blockType: LibraryDocumentBlockType.heading,
          plainText: text,
          formattedContent: LibraryFormattedContent.plain(text).toJson(),
          sourceHref: 'chapter-$order.xhtml',
          contentHash: 'hash-$order',
        );

    final headings = <LibraryDocumentBlock>[
      headingAt(0, 'Foreword'),
      headingAt(20, 'Chapter 1 - Christ Our Righteousness'),
      headingAt(105, 'Chapter 2 - A Message of Supreme Importance'),
      headingAt(133, 'Chapter 3 - Preparatory Messages'),
    ];

    test('selects the heading actually containing the current position', () {
      // Reproduces the reported bug: the reader has scrolled into Chapter 2
      // (a paragraph right after its heading at order 105) — Contents must
      // highlight Chapter 2, not the previous, already-passed Chapter 1.
      final current = canonicalContentsCurrentHeading(
        headings: headings,
        currentOrder: 106,
      );
      expect(current?.plainText, 'Chapter 2 - A Message of Supreme Importance');
    });

    test('selects the heading exactly at the current order', () {
      final current = canonicalContentsCurrentHeading(
        headings: headings,
        currentOrder: 105,
      );
      expect(current?.plainText, 'Chapter 2 - A Message of Supreme Importance');
    });

    test('returns null before the first heading', () {
      final current = canonicalContentsCurrentHeading(
        headings: headings,
        currentOrder: -1,
      );
      expect(current, isNull);
    });

    test('selects the last heading once past every heading', () {
      final current = canonicalContentsCurrentHeading(
        headings: headings,
        currentOrder: 9000,
      );
      expect(current?.plainText, 'Chapter 3 - Preparatory Messages');
    });
  });
}

LibraryCatalogItem _item({
  required String fileFormat,
  required String sourceType,
  String? relativePath,
  String collectionName = 'Pioneer Authors',
}) => LibraryCatalogItem(
  id: 'item',
  title: 'Test Book',
  author: 'Test Author',
  fileName: fileFormat == 'epub' ? 'book.epub' : 'capture.html',
  fileHash: null,
  relativePath:
      relativePath ??
      (fileFormat == 'epub'
          ? 'ePubs/book.epub'
          : 'TextCaptures/book/capture.html'),
  fileFormat: fileFormat,
  folderType: 'Research',
  libraryRole: 'book',
  collectionName: collectionName,
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
