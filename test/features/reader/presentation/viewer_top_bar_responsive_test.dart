import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/viewer_top_bar.dart';
import 'package:studybible2/features/reader/presentation/highlight_render.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setViewport(WidgetTester tester, {required Size size}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget toolbar({
    String bookName = 'Genesis',
    int chapter = 1,
    int? verse = 1,
    ThemeData? theme,
    VoidCallback? onSearch,
    VoidCallback? onPaintSelection,
    VoidCallback? onColorSetup,
    VoidCallback? onSavedPresentations,
    VoidCallback? onPresentationSetup,
    VoidCallback? onStandardTag,
    VoidCallback? onTopics,
    VoidCallback? onRapidTag,
    VoidCallback? onChoosePassage,
  }) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(
          children: [
            ViewerTopBar(
              bookName: bookName,
              chapter: chapter,
              verse: verse,
              fontScale: 1,
              baseBibleFontSize: 16,
              onSearch: onSearch ?? () {},
              onPaintSelection: onPaintSelection,
              onColorSetup: onColorSetup,
              highlightColor: Colors.amber,
              highlightName: 'Sun',
              onSavedPresentations: onSavedPresentations ?? () {},
              onStandardTag: onStandardTag ?? () {},
              onDollarTag: onPresentationSetup ?? () {},
              onRapidTag: onRapidTag ?? () {},
              activeFamily: null,
              onTopics: onTopics ?? () {},
              onChoosePassage: onChoosePassage ?? () {},
            ),
            const Expanded(
              child: SizedBox(
                key: ValueKey('scripture-content'),
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }

  for (final width in [320.0, 430.0, 700.0, 1024.0]) {
    testWidgets('paint and color shortcuts fit at width $width', (
      tester,
    ) async {
      await setViewport(tester, size: Size(width, 900));
      var paints = 0;
      var setups = 0;
      await tester.pumpWidget(
        toolbar(onPaintSelection: () => paints++, onColorSetup: () => setups++),
      );
      final paint = find.byKey(const ValueKey('viewer-paint-selection'));
      final color = find.byKey(const ValueKey('viewer-highlight-color'));
      expect(
        tester.getRect(paint).right,
        lessThanOrEqualTo(tester.getRect(color).left),
      );
      expect(tester.getRect(color).right, lessThanOrEqualTo(width));
      expect(find.byTooltip('Color Setup: Sun'), findsOneWidget);
      final sample = tester.widget<Text>(find.text('Highlight'));
      expect(
        sample.style?.color,
        resolveHighlightRender(Colors.amber, false).textColor,
      );
      await tester.tap(paint);
      await tester.tap(color);
      expect(paints, 1);
      expect(setups, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'phone highlight controls stay on row two and long reference centers at $width',
      (tester) async {
        await setViewport(tester, size: Size(width, 932));
        await tester.pumpWidget(
          toolbar(
            bookName: 'Song of Solomon',
            chapter: 8,
            verse: 14,
            onPaintSelection: () {},
            onColorSetup: () {},
          ),
        );
        final reference = find.byKey(
          const ValueKey('viewer-reference-control'),
        );
        final row2 = tester.getRect(
          find.byKey(const ValueKey('viewer-phone-toolbar-row-2')),
        );
        for (final key in [
          'viewer-paint-selection',
          'viewer-highlight-color',
        ]) {
          final bounds = tester.getRect(find.byKey(ValueKey(key)));
          expect(bounds.top, greaterThanOrEqualTo(row2.top));
          expect(bounds.bottom, lessThanOrEqualTo(row2.bottom));
        }
        expect(tester.getCenter(reference).dx, closeTo(width / 2, 0.01));
        final text = find.text('Song of Solomon 8:14');
        expect(tester.getCenter(text).dx, closeTo(width / 2, 0.01));
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sample preview follows the active theme', (tester) async {
    await setViewport(tester, size: const Size(1024, 900));
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        toolbar(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          onColorSetup: () {},
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('Highlight'));
      final spec = resolveHighlightRender(Colors.amber, dark);
      expect(text.style?.color, spec.textColor);
      final preview = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Highlight'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((preview.decoration as BoxDecoration).color, spec.backgroundColor);
    }
  });

  testWidgets(
    'phone title uses the full canonical book name and stays centered',
    (tester) async {
      await setViewport(tester, size: const Size(430, 932));
      var choosePassageCount = 0;
      await tester.pumpWidget(
        toolbar(
          bookName: 'Ephesians',
          chapter: 3,
          verse: 1,
          onChoosePassage: () => choosePassageCount++,
        ),
      );

      final titleFinder = find.text('Ephesians 3:1');
      final referenceFinder = find.byKey(
        const ValueKey('viewer-reference-control'),
      );
      expect(titleFinder, findsOneWidget);
      expect(find.text('Eph 3:1'), findsNothing);
      final title = tester.widget<Text>(titleFinder);
      expect(title.textAlign, TextAlign.center);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(
        tester.getCenter(titleFinder).dx,
        closeTo(tester.getCenter(referenceFinder).dx, 0.01),
      );
      await tester.tap(referenceFinder);
      expect(choosePassageCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone toolbar keeps reader actions without old presentation shortcuts',
    (tester) async {
      await setViewport(tester, size: const Size(430, 932));
      var searchCount = 0;
      var savedCount = 0;
      var setupCount = 0;
      var standardTagCount = 0;
      var topicsCount = 0;
      var rapidTagCount = 0;

      await tester.pumpWidget(
        toolbar(
          bookName: 'A Very Long Bible Reference Name That Must Truncate',
          onSearch: () => searchCount++,
          onSavedPresentations: () => savedCount++,
          onPresentationSetup: () => setupCount++,
          onStandardTag: () => standardTagCount++,
          onTopics: () => topicsCount++,
          onRapidTag: () => rapidTagCount++,
        ),
      );

      final row1 = find.byKey(const ValueKey('viewer-phone-toolbar-row-1'));
      final row2 = find.byKey(const ValueKey('viewer-phone-toolbar-row-2'));
      expect(row1, findsOneWidget);
      expect(row2, findsOneWidget);
      expect(tester.getTopLeft(row2).dy, tester.getBottomLeft(row1).dy);

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byTooltip('Saved Presentations'), findsNothing);
      expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
      expect(find.byIcon(Icons.connected_tv), findsNothing);
      expect(find.byTooltip('Presentation Setup'), findsNothing);
      expect(find.byTooltip('# Tags'), findsOneWidget);
      expect(find.byIcon(Icons.list_alt), findsOneWidget);
      expect(find.byTooltip('! Rapid tag'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.tap(find.byTooltip('# Tags'));
      await tester.tap(find.byTooltip('Topics'));
      await tester.tap(find.byTooltip('! Rapid tag'));
      expect(searchCount, 1);
      expect(savedCount, 0);
      expect(setupCount, 0);
      expect(standardTagCount, 1);
      expect(topicsCount, 1);
      expect(rapidTagCount, 1);

      final backSize = tester.getSize(
        find.byKey(const ValueKey('viewer-back-button')),
      );
      final searchSize = tester.getSize(
        find.byKey(const ValueKey('viewer-search-button')),
      );
      final referenceSize = tester.getSize(
        find.byKey(const ValueKey('viewer-reference-control')),
      );
      expect(backSize.width, 48);
      expect(searchSize.width, backSize.width);
      expect(
        referenceSize.width,
        greaterThan(backSize.width + searchSize.width),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('viewer-back-button'))).dx,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('viewer-search-button')))
              .dx,
        ),
      );

      final title = tester.widget<Text>(
        find.text('A Very Long Bible Reference Name That Must Truncate 1:1'),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      final longTitleParagraph = tester.renderObject<RenderParagraph>(
        find.text('A Very Long Bible Reference Name That Must Truncate 1:1'),
      );
      expect(longTitleParagraph.didExceedMaxLines, isFalse);

      for (final finder in <Finder>[
        find.byKey(const ValueKey('viewer-back-button')),
        find.byKey(const ValueKey('viewer-search-button')),
        find.byTooltip('# Tags'),
        find.byKey(const ValueKey('viewer-topics-button')),
        find.byTooltip('! Rapid tag'),
      ]) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }

      final actionCellKeys = <String>[
        'viewer-phone-action-cell-standard-tag',
        'viewer-phone-action-cell-topics',
        'viewer-phone-action-cell-rapid-tag',
      ];
      final cellWidths = actionCellKeys
          .map((key) => tester.getSize(find.byKey(ValueKey(key))).width)
          .toList();
      for (final width in cellWidths.skip(1)) {
        expect(width, closeTo(cellWidths.first, 0.01));
      }
      expect(
        cellWidths.reduce((left, right) => left + right),
        closeTo(tester.getSize(row2).width - 20, 0.01),
      );

      expect(
        tester.getTopLeft(find.byKey(const ValueKey('scripture-content'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(row2).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back button retains Navigator pop behavior', (tester) async {
    await setViewport(tester, size: const Size(430, 932));
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ViewerTopBar(
            bookName: 'Genesis',
            chapter: 1,
            verse: 1,
            fontScale: 1,
            baseBibleFontSize: 16,
            onSearch: () {},
            onSavedPresentations: () {},
            onStandardTag: () {},
            onDollarTag: () {},
            onRapidTag: () {},
            activeFamily: null,
            onTopics: () {},
            onChoosePassage: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('viewer-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('iPad keeps the existing single-row wide toolbar', (
    tester,
  ) async {
    await setViewport(tester, size: const Size(1024, 1366));
    await tester.pumpWidget(toolbar());

    expect(
      find.byKey(const ValueKey('viewer-phone-two-row-toolbar')),
      findsNothing,
    );
    expect(find.byTooltip('Saved Presentations'), findsNothing);
    expect(find.byIcon(Icons.folder_open_outlined), findsNothing);
    expect(find.byIcon(Icons.connected_tv), findsNothing);
    expect(find.byTooltip('Presentation Setup'), findsNothing);
    expect(tester.getSize(find.byType(ViewerTopBar)).height, kToolbarHeight);
    expect(tester.takeException(), isNull);
  });
}
