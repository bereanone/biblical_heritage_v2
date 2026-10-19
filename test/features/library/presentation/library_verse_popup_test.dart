import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/core/theme/app_theme.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';

void main() {
  test(
    'margin-note Scripture citations become tappable without changing text',
    () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      const text = '1 Sam. 10:5-12; 19:23, 24.';
      final spans = canonicalMarginNoteTextSpans(
        text: text,
        bodyStyle: const TextStyle(),
        linkStyle: const TextStyle(decoration: TextDecoration.underline),
        linkRecognizer: (_) => recognizer,
        citationResolves: (_, _) => true,
      );
      expect(TextSpan(children: spans).toPlainText(), text);
      expect(
        spans.whereType<TextSpan>().where((span) => span.recognizer != null),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'popup can show surrounding context and still tags cited verses',
    (tester) async {
      var tagged = <LibraryPopupVerse>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryVersePopup(
              citation: 'Isaiah 28:10',
              loader: (_) async => const [
                LibraryPopupVerse(
                  LibraryVerseTarget(23, 28, 10),
                  'Isaiah 28:10',
                  'Cited verse',
                ),
              ],
              contextLoader: (_) async => const [
                LibraryPopupVerse(
                  LibraryVerseTarget(23, 28, 9),
                  'Isaiah 28:9',
                  'Previous context',
                ),
                LibraryPopupVerse(
                  LibraryVerseTarget(23, 28, 10),
                  'Isaiah 28:10',
                  'Cited verse',
                ),
                LibraryPopupVerse(
                  LibraryVerseTarget(23, 28, 11),
                  'Isaiah 28:11',
                  'Following context',
                ),
              ],
              tagger: (verses) async {
                tagged = verses;
                return 'Tagged cited verse';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Previous context'), findsNothing);
      await tester.tap(find.text('Show Bible context'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Previous context'), findsOneWidget);
      expect(find.textContaining('Following context'), findsOneWidget);
      await tester.tap(find.byTooltip('Add to active hashtag'));
      await tester.pumpAndSettle();
      expect(tagged.map((verse) => verse.label), ['Isaiah 28:10']);
      await tester.tap(find.text('Show cited verses'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Previous context'), findsNothing);
    },
  );

  testWidgets(
    'long chapter keeps action and back arrow visible at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => LibraryVersePopup(
                    citation: 'Leviticus 16',
                    loader: (_) async => List.generate(
                      34,
                      (i) => LibraryPopupVerse(
                        LibraryVerseTarget(3, 16, i + 1),
                        'Leviticus 16:${i + 1}',
                        'Chapter verse text. ' * 12,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open chapter'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open chapter'));
      await tester.pumpAndSettle();
      final button = find.text('Add to default hashtag');
      final arrow = find.byTooltip('Close verse popup');
      final beforeButton = tester.getRect(button);
      final beforeArrow = tester.getRect(arrow);
      await tester.drag(
        find.byKey(const ValueKey('library-popup-verses')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(button), beforeButton);
      expect(tester.getRect(arrow), beforeArrow);
      expect(button.hitTestable(), findsOneWidget);
      expect(arrow.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Open chapter'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'popup and labeled action follow day, sepia, night and theme changes',
    (tester) async {
      final themes = [
        buildAppTheme(
          AppThemeMode.sepia,
          settings: const AppVisualSettings(
            backgroundColor: Colors.white,
            textColor: Colors.black,
            appBarColor: Colors.white,
            bottomBarColor: Colors.white,
            accentColor: Color(0xFF2455A0),
            viewerFontScale: 1,
          ),
        ),
        buildAppTheme(
          AppThemeMode.sepia,
          settings: AppSettingsService.instance.presetForMode(
            AppThemeMode.sepia,
          ),
        ),
        buildAppTheme(
          AppThemeMode.night,
          settings: AppSettingsService.instance.presetForMode(
            AppThemeMode.night,
          ),
        ),
      ];
      for (final theme in [...themes, themes[1]]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: LibraryVersePopup(
                citation: 'Psalm 139:7',
                loader: (_) async => const [
                  LibraryPopupVerse(
                    LibraryVerseTarget(19, 139, 7),
                    'Psalms 139:7',
                    'Whither shall I go from thy spirit?',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
          theme.colorScheme.surface,
        );
        expect(
          tester
              .widget<SelectableText>(find.byType(SelectableText))
              .style!
              .color,
          theme.colorScheme.onSurface,
        );
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('Add to default hashtag'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, theme.colorScheme.primary);
        final textContext = tester.element(find.text('Add to default hashtag'));
        expect(
          DefaultTextStyle.of(textContext).style.color,
          theme.colorScheme.onPrimary,
        );
      }
    },
  );
  test(
    'reader allows verse popup links without allowing arbitrary external links',
    () {
      expect(
        canonicalReaderSupportsLink(
          'chapter.xhtml',
          'studybible-citation:John%203%3A16',
        ),
        isTrue,
      );
      expect(canonicalReaderSupportsLink('chapter.xhtml', '#verse'), isTrue);
      expect(
        canonicalReaderSupportsLink('chapter.xhtml', 'https://example.com'),
        isFalse,
      );
      expect(
        canonicalReaderSupportsLink('chapter.xhtml', 'javascript:alert(1)'),
        isFalse,
      );
    },
  );
  const books = [
    BookRecord(bookNumber: 43, bookName: 'John', bookIndex: 43),
    BookRecord(bookNumber: 46, bookName: '1 Corinthians', bookIndex: 46),
    BookRecord(bookNumber: 58, bookName: 'Hebrews', bookIndex: 58),
  ];
  test(
    'citation parser preserves comma gaps, ranges and chapter continuations',
    () {
      final verses = parseLibraryCitation(
        '(John 3:1,3-4; 4:2; Hebrews 11:1.)',
        books,
      );
      expect(verses.map((v) => '${v.book}:${v.chapter}:${v.verse}').toList(), [
        '43:3:1',
        '43:3:3',
        '43:3:4',
        '43:4:2',
        '58:11:1',
      ]);
      expect(parseLibraryCitation('(I Cor. 5:7)', books).single.book, 46);
      for (final invalid in [
        'John 3:1 margin',
        'John 3:4-1',
        'John 3:1 garbage',
        'Unknown 3:1',
        'John 3:1,',
      ]) {
        expect(
          () => parseLibraryCitation(invalid, books),
          throwsFormatException,
        );
      }
    },
  );
  testWidgets('unresolved citation cannot tag a partial passage', (
    tester,
  ) async {
    var tagged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryVersePopup(
            citation: 'Rev 20:4,16',
            loader: (_) async =>
                throw const FormatException('Verse unavailable'),
            tagger: (_) async {
              tagged = true;
              return 'Unexpected';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be fully resolved'), findsOneWidget);
    expect(find.byTooltip('Add to active hashtag'), findsNothing);
    expect(tagged, isFalse);
  });
  testWidgets(
    'popup tags displayed verses only and closes to unchanged reading position',
    (tester) async {
      final scroll = ScrollController(initialScrollOffset: 300);
      var tagged = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => LibraryVersePopup(
                        citation: 'John 3:16',
                        loader: (_) async => const [
                          LibraryPopupVerse(
                            LibraryVerseTarget(43, 3, 16),
                            'John 3:16',
                            'Fixture verse text',
                          ),
                        ],
                        tagger: (verses) async {
                          tagged += verses.length;
                          return 'Added to active tag';
                        },
                      ),
                    ),
                    child: const Text('Open verse'),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      children: List.generate(
                        100,
                        (i) =>
                            SizedBox(height: 40, child: Text('Paragraph $i')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = scroll.offset;
      await tester.tap(find.text('Open verse'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fixture verse text'), findsOneWidget);
      expect(tagged, 0);
      await tester.tap(find.byTooltip('Add to active hashtag'));
      await tester.pumpAndSettle();
      expect(tagged, 1);
      await tester.tap(find.byTooltip('Close verse popup'));
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
